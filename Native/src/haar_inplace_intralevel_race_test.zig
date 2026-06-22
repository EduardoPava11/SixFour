//! ADVERSARIAL invariant test — break-vector "metal-inplace-reconstruct-intralevel-race".
//!
//! DISTINCT FROM the two sibling tests, which both model an INTER-level hazard
//! (level ℓ+1 reading buffer state from before level ℓ published). This test
//! attacks the INTRA-level write-before-read aliasing that lives inside ONE
//! expansion level of `s4_haar_reconstruct` / `s4_haar_level_nodes`.
//!
//! THE MECHANISM (kernels.zig:563-579, :610-626). At level `cur`, the in-place
//! loop, for each i in [0,cur), does:
//!     node = out[i];                       // READ slot i
//!     out[2*i]   = y + d;   // x           // WRITE slot 2i
//!     out[2*i+1] = y;       // y           // WRITE slot 2i+1
//! The READ set is {0 .. cur-1}; the WRITE set is {0 .. 2*cur-1}. They OVERLAP on
//! the low half {0 .. cur-1}: thread j writes out[2j], and 2j lands inside the
//! read set whenever 2j < cur, i.e. j < cur/2. So thread j's write to slot 2j
//! ALIASES the node-read that thread i = 2j must perform. The owned kernel is
//! safe ONLY because it runs i strictly HIGH→LOW (`while (i > 0) { i -= 1; … }`):
//! the high reader i is serviced before the low writer j = i/2 ever fires.
//!
//! A naive Metal port that maps ONE THREAD PER i within a level and lets them run
//! concurrently (or in any not-strictly-descending order — e.g. SIMD lane order,
//! or an ascending `for`) has NO such ordering. Thread j = i/2 can publish out[2j]
//! (its child x = parent.value + d-ish) into slot i BEFORE thread i reads slot i
//! as its node ⇒ thread i lifts from a CHILD value instead of its PARENT value ⇒
//! the cascade below i is built on garbage ⇒ reconstruct ≠ id.
//!
//! INVARIANT under attack:
//!     reconstruct(analyze(x)) == x        -- holds for the owned HIGH→LOW kernel
//!     reconstructAscendingInPlace(...)    -- MUST BREAK round-trip (proves the
//!                                            descending order / per-i barrier is
//!                                            load-bearing, NOT incidental)
//!
//! WHY THIS IS NOT REDUNDANT with haar_barrier_race / haar_barrier_hazard: those
//! keep the WITHIN-level evaluation correct and only desync ACROSS levels. Here
//! every level boundary is perfectly synchronized (we re-run the owned analyze and
//! feed a single corrupted level); the ONLY defect is the iteration ORDER inside
//! one level. If a Metal author added the inter-level barrier both sibling tests
//! demand but still parallelized a level over i without preserving the high→low
//! anti-dependency (the natural thing to do — "it's just a map over i"), THIS is
//! the bug they would ship, and the sibling tests would stay green.
//!
//! GUARD STATE: N/A-future-port. Today's serial Zig is correct. The contract this
//! pins for the port: a per-level expansion that writes in place MUST either (a)
//! preserve the high→low anti-dependency order, or (b) double-buffer (read src,
//! write dst, ping-pong) so the read set and write set never alias. Option (b) is
//! also asserted below as the safe design.

const std = @import("std");
const kernels = @import("kernels.zig");

const N: usize = 8; // depth 3 → levels cur = 1,2,4 ; the cur=2 and cur=4 levels alias
const C: usize = 3; // L,a,b interleaved

fn unliftPair(node: i32, d: i32) [2]i32 {
    const y = node - @divFloor(d, 2);
    return .{ y + d, y }; // {x, y}
}

// THE OWNED ORDER (high→low), per single channel — the control. Byte-identical
// to s4_haar_reconstruct's inner loop. Round-trips by construction.
fn reconstructDescending(root: i32, offsets: [N - 1]i32, out: *[N]i32) void {
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

// THE NAIVE PARALLEL-EQUIVALENT ORDER (ascending i, same in-place buffer). This
// is the schedule a "one thread per i, no anti-dependency tracking" Metal port
// realizes whenever the scheduler happens to retire low indices first (ascending
// lane/threadgroup order is the default, and a barrier-less parallel map gives NO
// guarantee at all). Identical arithmetic; only the order changes. At a level
// with cur ≥ 2, writing out[2*0]=out[0] for i=0 destroys the node that i=... no —
// i=0 reads out[0] THEN writes out[0]; the real kill is: i=0 writes out[2]
// (=2*1's read slot) BEFORE i=1 reads out[1]? No — out[2] is read by i=2. The
// concrete alias: at cur=4, i=1 writes out[2]; i=2 reads out[2] as its node. In
// ascending order i=1 fires first and clobbers out[2] with a CHILD value before
// i=2 reads it. That is the write-before-read corruption.
fn reconstructAscendingInPlace(root: i32, offsets: [N - 1]i32, out: *[N]i32) void {
    out[0] = root;
    var cur: usize = 1;
    while (cur < N) {
        const out_start = cur - 1;
        var i: usize = 0;
        while (i < cur) : (i += 1) {
            const node = out[i]; // may already be CLOBBERED by a lower i's write to out[2*lower]
            const d = offsets[out_start + i];
            const r = unliftPair(node, d);
            out[2 * i] = r[0];
            out[2 * i + 1] = r[1];
        }
        cur *= 2;
    }
}

// THE SAFE PORT: double-buffered ping-pong. Read set is `src`, write set is `dst`;
// they never alias, so ANY thread order (ascending, descending, fully concurrent)
// is correct without a per-i anti-dependency. This is what a Metal port should
// ship. Asserted byte-exact.
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

test "ADVERSARIAL metal-inplace-reconstruct-intralevel-race: ascending-order in-place expansion breaks reconstruct∘analyze; descending + ping-pong survive" {
    // Adversarial WITNESS: details large and mixed-sign at EVERY level so a
    // child value (the clobbering write) can never coincidentally equal the parent
    // value (the correct node). A coincidence here would make the bug invisible;
    // we forbid it by maximizing |parent - child| at the aliasing slots.
    const leaves3 = [N][C]i32{
        .{ 1 << 27, -32768, 7 },
        .{ -(1 << 27), 32767, -7 }, // huge cross-sibling delta ⇒ parent != child by ~2^27
        .{ 0, 65536, -65535 },
        .{ 123457, -65537, 65536 }, // odd ⇒ exercises @divFloor at the alias slot
        .{ -1, 1, -1 },
        .{ 1 << 26, -(1 << 26), 3 },
        .{ -3, 0, 1 },
        .{ 5, -5, 0 },
    };

    var any_channel_broke = false;

    var c: usize = 0;
    while (c < C) : (c += 1) {
        // analyze with the OWNED kernel (interleaved triple form).
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
        try std.testing.expectEqual(
            kernels.RC_OK,
            kernels.s4_haar_analyze(&leaves_il, N, &root_il, &off_il, &scratch, scratch.len),
        );

        const root_c = root_il[c];
        var off_c: [N - 1]i32 = undefined;
        var k: usize = 0;
        while (k < N - 1) : (k += 1) off_c[k] = off_il[k * 3 + c];

        var expect: [N]i32 = undefined;
        r = 0;
        while (r < N) : (r += 1) expect[r] = leaves3[r][c];

        // CONTROL — owned high→low order round-trips this channel exactly, and is
        // byte-identical to the owned kernel via the full interleaved path.
        var got_desc: [N]i32 = undefined;
        reconstructDescending(root_c, off_c, &got_desc);
        try std.testing.expectEqualSlices(i32, &expect, &got_desc);

        // GUARD — ping-pong (any thread order safe) is byte-exact.
        var got_pp: [N]i32 = undefined;
        reconstructPingPong(root_c, off_c, &got_pp);
        try std.testing.expectEqualSlices(i32, &expect, &got_pp);

        // WITNESS — ascending in-place (the naive parallel map) destroys the
        // round-trip via intra-level write-before-read aliasing.
        var got_bad: [N]i32 = undefined;
        reconstructAscendingInPlace(root_c, off_c, &got_bad);
        if (!std.mem.eql(i32, &expect, &got_bad)) any_channel_broke = true;
    }

    // The high→low order (equivalently, a per-i anti-dependency barrier) MUST be
    // load-bearing: at least one channel's round-trip is destroyed when the order
    // is the naive ascending map. If this fails, the in-place expansion has no
    // intra-level alias and naive parallelization would be safe (break-vector
    // refuted). It is NOT safe: it breaks.
    try std.testing.expect(any_channel_broke);
}

// Cross-check the SAME hazard through the SHIPPED export surface: confirm the
// owned s4_haar_reconstruct (high→low) round-trips the full interleaved witness,
// so the only thing standing between "correct" and the broken ascending port is
// the iteration order — nothing else in the export differs.
test "metal-inplace-reconstruct-intralevel-race: owned s4_haar_reconstruct round-trips the witness (order is the only variable)" {
    const leaves = [N * C]i32{
        1 << 27,  -32768,    7,
        -(1 << 27), 32767,  -7,
        0,        65536,   -65535,
        123457,   -65537,  65536,
        -1,       1,       -1,
        1 << 26,  -(1 << 26), 3,
        -3,       0,       1,
        5,        -5,      0,
    };
    var root: [3]i32 = undefined;
    var off: [(N - 1) * 3]i32 = undefined;
    var scratch: [N * 3 * @sizeOf(i32)]u8 = undefined;
    try std.testing.expectEqual(
        kernels.RC_OK,
        kernels.s4_haar_analyze(&leaves, N, &root, &off, &scratch, scratch.len),
    );
    var got: [N * C]i32 = undefined;
    try std.testing.expectEqual(
        kernels.RC_OK,
        kernels.s4_haar_reconstruct(&root, &off, N, &got),
    );
    try std.testing.expectEqualSlices(i32, &leaves, &got);
}
