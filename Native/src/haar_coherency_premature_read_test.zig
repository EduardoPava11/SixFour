//! ADVERSARIAL invariant test for break-vector
//! `unified-memory-coherency-premature-read`.
//!
//! THREAT MODEL (future Metal port, Apple-Silicon UNIFIED memory, CLAUDE.md):
//! The reversible Haar/S-transform lift is LEVEL-SEQUENTIAL. A hybrid port may
//! split the cascade across the CPU/GPU boundary: a GPU dispatch lifts level ℓ
//! into an `MTLStorageModeShared` buffer (same physical memory the Zig/CPU core
//! sees), and the very NEXT sequential level — or the GIF assembler — is run on
//! the CPU reading that buffer. On unified memory CPU and GPU share the bytes,
//! but they do NOT share an automatic ordering guarantee: until the level-ℓ
//! command buffer COMPLETES ([commandBuffer waitUntilCompleted] / a completion
//! handler / an MTLEvent), the CPU may observe the shared buffer with only a
//! PARTIAL PREFIX of the GPU's writes published — write-combining / cache-line
//! flush granularity means some lifted slots have landed and some still hold the
//! pre-dispatch (stale) value. The CPU then feeds that half-published state into
//! the sequential inverse.
//!
//! This is NOT an arithmetic break (the integer lift is exact) and NOT the
//! GPU-internal threadgroup race (`haar_barrier_race_test`) nor the untracked
//! inter-pass MTLFence drop (`haar_barrier_hazard_test`). Both of those are
//! ordering bugs WITHIN the GPU timeline. This vector is the CPU<->GPU HANDOFF:
//! exact bits, wrong TIMING — the consumer reads before the producer's command
//! buffer signalled completion. Same byte values eventually; observed too early.
//!
//! Metal can't run on this headless Mac, but the FAILURE a premature read
//! produces is a property of the data dependency, not of the GPU: a CPU level
//! consuming a buffer in which only the first `k` of the producer level's writes
//! are visible. We model that exact schedule in Zig and assert:
//!
//!   (1) WITNESS — running the reconstruct cascade where ONE inter-level handoff
//!       reads the shared buffer with only a PREFIX of the prior level's writes
//!       published (the missing-waitUntilCompleted schedule) DESTROYS the
//!       round-trip: reconstruct∘analyze != id. Proves the completion fence is
//!       load-bearing.
//!   (2) GUARD — the SAME cascade where the handoff reads the buffer only after
//!       FULL publication (the waitUntilCompleted-fenced schedule) round-trips
//!       BYTE-EXACT, matching the owned in-place s4_haar_reconstruct.
//!
//! INVARIANT: reconstruct∘analyze == id holds across a CPU<->GPU shared-buffer
//! handoff ONLY when the consumer reads after the producer's command buffer has
//! fully completed. Any read that observes a partial-publication prefix of a
//! Haar level breaks byte-exact invertibility.
//!
//! CONTRACT THIS PINS for the port: every CPU read of a GPU-written shared Haar
//! buffer (and vice-versa) MUST be gated by waitUntilCompleted / a completion
//! handler / an MTLEvent wait. Never read a shared lift buffer "because it's
//! unified memory, the bytes are already there" — partial publication is real.

const std = @import("std");
const kernels = @import("kernels.zig");

// floor-div pair unlift, byte-identical to the kernel's inner reconstruct cell
// (kernels.zig:571-575). Re-stated so the test is self-contained and can model
// alternative PUBLICATION schedules of the same exact arithmetic.
fn unliftPair(node: i32, d: i32) [2]i32 {
    const y = node - @divFloor(d, 2);
    return .{ y + d, y }; // {x, y}
}

const N: usize = 8; // 2^3 leaves — depth 3, expansion levels cur = 1,2,4
const C: usize = 3; // L,a,b interleaved

// Producer/consumer model of the inverse cascade across a CPU<->GPU handoff.
//
// `publish_prefix` selects, for the handoff level (level index 1 — the first
// level that depends on a prior level's writes), how many of that prior level's
// output slots are VISIBLE to the consumer when it reads the shared buffer:
//   publish_prefix = full  → waitUntilCompleted fired, all writes landed (GUARD)
//   publish_prefix = 1      → premature read, only slot 0 of the prior level's
//                             writes is published; the rest still hold the stale
//                             pre-dispatch value (WITNESS)
//
// We model "the producer level ran on the GPU into the shared buffer; the CPU
// read it before completion" by: after computing the producer level fully into a
// staging copy, only COPY the first `publish_prefix` written slots into the
// buffer the consumer level reads; the remaining consumer-visible slots keep the
// value they held BEFORE the producer dispatch (stale).
fn reconstructHandoff(root: i32, offsets: [N - 1]i32, out: *[N]i32, publish_prefix: usize) void {
    out[0] = root;
    var cur: usize = 1;
    var level: usize = 0;
    while (cur < N) : (level += 1) {
        const out_start = cur - 1;

        // Snapshot the buffer state the consumer would see BEFORE this level's
        // producer writes (the stale/pre-dispatch contents of the slots).
        const stale: [N]i32 = out.*;

        // Compute this level's full (correct) output into a staging buffer —
        // this is "the GPU dispatch result", complete in the GPU's view.
        var staged: [N]i32 = out.*;
        var i: usize = cur;
        while (i > 0) {
            i -= 1;
            const node = out[i]; // producer reads the (correct) parent
            const d = offsets[out_start + i];
            const r = unliftPair(node, d);
            staged[2 * i] = r[0];
            staged[2 * i + 1] = r[1];
        }

        // PUBLICATION across the CPU<->GPU handoff. On the level-1 handoff, only
        // a prefix of the producer's writes are visible to the consumer if the
        // completion fence was skipped. Every OTHER level is fully in-timeline
        // (no boundary), so it publishes fully.
        const handoff = (level == 1);
        if (handoff and publish_prefix < 2 * cur) {
            // Premature read: publish only the first `publish_prefix` written
            // child slots; the rest stay stale (pre-dispatch value).
            var slot: usize = 0;
            // children are written at indices 0..2*cur-1
            while (slot < 2 * cur) : (slot += 1) {
                if (slot < publish_prefix) {
                    out[slot] = staged[slot];
                } else {
                    out[slot] = stale[slot]; // not yet flushed → consumer sees stale
                }
            }
        } else {
            // Fully published (waitUntilCompleted / no boundary at this level).
            var slot: usize = 0;
            while (slot < 2 * cur) : (slot += 1) out[slot] = staged[slot];
        }
        cur *= 2;
    }
}

test "ADVERSARIAL unified-memory-coherency-premature-read: CPU reads GPU shared Haar buffer before command-buffer completion ⇒ reconstruct∘analyze != id; waitUntilCompleted-fenced read survives" {
    // Adversarial WITNESS: every level-0 lift MOVES the value (parent != either
    // child) and details are large + mixed-sign so a stale (unpublished) slot
    // cannot coincide with the correct lifted value. Includes near-i32-edge and
    // odd-negative details to also stress @divFloor at the publication boundary.
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
        try std.testing.expectEqual(kernels.RC_OK, kernels.s4_haar_analyze(&leaves_il, N, &root_il, &off_il, &scratch, scratch.len));

        const root_c = root_il[c];
        var off_c: [N - 1]i32 = undefined;
        var k: usize = 0;
        while (k < N - 1) : (k += 1) off_c[k] = off_il[k * 3 + c];

        var expect: [N]i32 = undefined;
        r = 0;
        while (r < N) : (r += 1) expect[r] = leaves3[r][c];

        // CONTROL: owned kernel round-trips this channel exactly.
        var got_owned: [N * 3]i32 = undefined;
        try std.testing.expectEqual(kernels.RC_OK, kernels.s4_haar_reconstruct(&root_il, &off_il, N, &got_owned));
        r = 0;
        while (r < N) : (r += 1) try std.testing.expectEqual(expect[r], got_owned[r * 3 + c]);

        // (2) GUARD — FULLY-published handoff (waitUntilCompleted fired): byte-exact.
        var got_fenced: [N]i32 = undefined;
        reconstructHandoff(root_c, off_c, &got_fenced, N); // full publication
        try std.testing.expectEqualSlices(i32, &expect, &got_fenced);

        // (1) WITNESS — PREMATURE read: only slot 0 of the handoff level's writes
        // published; the rest of the consumer-visible slots hold stale bytes.
        var got_premature: [N]i32 = undefined;
        reconstructHandoff(root_c, off_c, &got_premature, 1); // partial publication
        if (!std.mem.eql(i32, &expect, &got_premature)) any_channel_broke = true;
    }

    // The completion fence MUST be load-bearing: at least one channel's round-trip
    // is destroyed when the CPU reads the shared buffer before the producing
    // command buffer completed. If this DID round-trip, the handoff would be safe
    // without waitUntilCompleted and the vector refuted. It is NOT safe: it fails.
    try std.testing.expect(any_channel_broke);
}
