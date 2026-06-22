//! ADVERSARIAL invariant test for break-vector
//! `untracked-hazard-mode-inplace-no-barrier`.
//!
//! THREAT MODEL (future Metal port, MTLHazardTrackingMode.untracked):
//! `s4_haar_reconstruct` expands the tree IN PLACE, level by level. At level ℓ,
//! the node at index i is read from `leaves[i]` and its two children are written
//! to `leaves[2i]` and `leaves[2i+1]`. The NEXT level (ℓ+1) reads those very
//! indices. So there is a HARD data dependency: level ℓ+1's reads alias level ℓ's
//! writes. With `.tracked` heaps Metal auto-inserts the inter-pass barrier; with
//! `.untracked` (the perf-tuned path) the developer must insert MTLFence /
//! memoryBarrier(resources:) BY HAND, and forgetting one lets level ℓ+1 read a
//! STALE (pre-ℓ) value — a silent, device/driver-dependent non-identity.
//!
//! Metal can't run on this headless Mac, but the FAILURE the missing barrier
//! produces is a property of the in-place algorithm, not of the GPU: a level
//! reading the buffer state from BEFORE the previous level's writes landed. We
//! model that schedule exactly in Zig and assert two things:
//!
//!   (1) WITNESS — running level ℓ+1 against a SNAPSHOT taken before level ℓ's
//!       writes were published (the dropped-barrier schedule) DESTROYS the
//!       round-trip: reconstruct∘analyze != id. This proves the inter-level
//!       barrier is load-bearing (a no-op barrier here would mean the bug is
//!       invisible and we'd have nothing to guard).
//!   (2) GUARD — the barrier-free-SAFE port (double-buffered, ping-pong, no
//!       aliasing so no fence needed) round-trips BYTE-EXACT, matching the owned
//!       in-place s4_haar_reconstruct. This is the design a Metal author should
//!       ship under .untracked instead of in-place + manual fences.
//!
//! INVARIANT: reconstruct∘analyze == id holds ONLY when each Haar expansion level
//! observes the fully-published output of the previous level. Any schedule that
//! lets level ℓ+1 read pre-ℓ buffer state breaks byte-exact invertibility.

const std = @import("std");
const kernels = @import("kernels.zig");

// floor-div pair lift / unlift, byte-identical to kernels.sLift / sUnlift
// (which are file-private). Re-stated here so the test is self-contained and
// can model alternative SCHEDULES of the same arithmetic.
fn unliftPair(node: i32, d: i32) [2]i32 {
    const y = node - @divFloor(d, 2);
    return .{ y + d, y }; // {x, y}
}

const N: usize = 8; // 2^3 leaves — depth 3, three expansion levels (ℓ = 1,2,4)
const C: usize = 3; // L,a,b

// Reference in-place reconstruct restricted to ONE channel, mirroring the owned
// kernel's per-level loop. Returns the full N-leaf reconstruction.
fn reconstructInPlace(root: i32, offsets: [N - 1]i32, out: *[N]i32) void {
    out[0] = root;
    var cur: usize = 1;
    while (cur < N) {
        const out_start = cur - 1;
        var i: usize = cur;
        while (i > 0) {
            i -= 1;
            const node = out[i];
            const d = offsets[out_start + i];
            const r = unliftPair(node, d);
            out[2 * i] = r[0];
            out[2 * i + 1] = r[1];
        }
        cur *= 2;
    }
}

// THE DROPPED-BARRIER SCHEDULE. Identical math, but level ℓ+1 reads from a
// SNAPSHOT of the buffer captured BEFORE level ℓ published its writes — exactly
// what an untracked resource with a missing inter-pass MTLFence yields when the
// ℓ+1 dispatch is allowed to observe pre-ℓ memory. Concretely: we run each level
// against `prev` (the state as of the start of the previous level) instead of
// the freshly-written `out`.
fn reconstructMissingBarrier(root: i32, offsets: [N - 1]i32, out: *[N]i32) void {
    out[0] = root;
    var prev: [N]i32 = out.*; // buffer state the NEXT level will (wrongly) read
    var cur: usize = 1;
    var level: usize = 0;
    while (cur < N) {
        const out_start = cur - 1;
        // Source of node reads: level 0 legitimately reads `out` (root just
        // written, no prior level to race). Every subsequent level reads `prev`
        // — the stale, not-yet-synchronized buffer (the missing-barrier hazard).
        const src: *const [N]i32 = if (level == 0) out else &prev;
        var snapshot: [N]i32 = out.*; // capture BEFORE this level writes
        var i: usize = cur;
        while (i > 0) {
            i -= 1;
            const node = src[i];
            const d = offsets[out_start + i];
            const r = unliftPair(node, d);
            out[2 * i] = r[0];
            out[2 * i + 1] = r[1];
        }
        prev = snapshot; // next level reads THIS (pre-write) state ⇒ stale
        _ = &snapshot;
        cur *= 2;
        level += 1;
    }
}

// THE BARRIER-FREE-SAFE PORT: double-buffered ping-pong. Level ℓ reads `src`,
// writes `dst`; no index is both read and written in the same pass, so NO fence
// is required even under .untracked. This is what a correct Metal port ships.
fn reconstructPingPong(root: i32, offsets: [N - 1]i32, out: *[N]i32) void {
    var a: [N]i32 = undefined;
    var b: [N]i32 = undefined;
    a[0] = root;
    var src: *[N]i32 = &a;
    var dst: *[N]i32 = &b;
    var cur: usize = 1;
    while (cur < N) {
        const out_start = cur - 1;
        var i: usize = 0;
        while (i < cur) : (i += 1) {
            const node = src[i];
            const d = offsets[out_start + i];
            const r = unliftPair(node, d);
            dst[2 * i] = r[0];
            dst[2 * i + 1] = r[1];
        }
        const t = src;
        src = dst;
        dst = t;
        cur *= 2;
    }
    out.* = src.*;
}

test "ADVERSARIAL untracked-hazard-mode-inplace-no-barrier: dropped inter-level barrier breaks reconstruct∘analyze; ping-pong port survives" {
    // Adversarial WITNESS: leaves whose detail coefficients are large and of
    // mixed sign at EVERY level, so a stale read at level ℓ+1 cannot accidentally
    // coincide with the correct value. Mix of extremes + a sign-flip across the
    // floor-div boundary (odd negative detail) to also exercise @divFloor.
    const leaves3 = [N][C]i32{
        .{ 1 << 28, -32768, 7 },
        .{ -(1 << 28), 32767, -7 },
        .{ 0, 65536, -65535 },
        .{ 123456, -65537, 65536 },
        .{ -1, 1, -1 },
        .{ 2147483647 >> 2, -(2147483647 >> 2), 3 },
        .{ -3, 0, 1 },
        .{ 5, -5, 0 },
    };

    var any_channel_broke = false;

    var c: usize = 0;
    while (c < C) : (c += 1) {
        // analyze this channel with the OWNED kernel (interleaved triple form).
        var leaves_il: [N * 3]i32 = undefined;
        var r: usize = 0;
        while (r < N) : (r += 1) {
            leaves_il[r * 3 + 0] = leaves3[r][0];
            leaves_il[r * 3 + 1] = leaves3[r][1];
            leaves_il[r * 3 + 2] = leaves3[r][2];
        }
        var root_il: [3]i32 = undefined;
        var off_il: [(N - 1) * 3]i32 = undefined;
        var scratch: [N * 3 * @sizeOf(i32)]u8 = undefined;
        try std.testing.expectEqual(kernels.RC_OK, kernels.s4_haar_analyze(&leaves_il, N, &root_il, &off_il, &scratch, scratch.len));

        // de-interleave this channel's root + offsets
        const root_c = root_il[c];
        var off_c: [N - 1]i32 = undefined;
        var k: usize = 0;
        while (k < N - 1) : (k += 1) off_c[k] = off_il[k * 3 + c];

        var expect: [N]i32 = undefined;
        r = 0;
        while (r < N) : (r += 1) expect[r] = leaves3[r][c];

        // (control) owned in-place model round-trips this channel exactly.
        var got_inplace: [N]i32 = undefined;
        reconstructInPlace(root_c, off_c, &got_inplace);
        try std.testing.expectEqualSlices(i32, &expect, &got_inplace);

        // (2) GUARD — barrier-free-safe ping-pong port is byte-exact.
        var got_pp: [N]i32 = undefined;
        reconstructPingPong(root_c, off_c, &got_pp);
        try std.testing.expectEqualSlices(i32, &expect, &got_pp);

        // (1) WITNESS — dropped inter-level barrier reads stale buffer state.
        var got_bad: [N]i32 = undefined;
        reconstructMissingBarrier(root_c, off_c, &got_bad);
        if (!std.mem.eql(i32, &expect, &got_bad)) any_channel_broke = true;
    }

    // The barrier MUST be load-bearing: at least one channel's round-trip is
    // destroyed when the inter-level synchronization is dropped. If this fails,
    // the in-place algorithm has no actual cross-level dependency and the whole
    // break-vector is a non-issue (refuted). It is NOT a non-issue: it fails.
    try std.testing.expect(any_channel_broke);
}
