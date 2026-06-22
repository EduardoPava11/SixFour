//! Adversarial invariant test — break-vector "level-sequential-missing-barrier".
//!
//! The integer Haar/S-transform lift is LEVEL-SEQUENTIAL: level ℓ+1's parents
//! consume level ℓ's freshly-lifted parents out of the SAME working buffer
//! (`s4_haar_analyze` writes `work[i*3+c] = y + floor(d/2)` for level ℓ, then the
//! next iteration reads `work[(2i)*3+c]` / `work[(2i+1)*3+c]` as that level's
//! inputs). On the CPU this is a plain `while (cur > 1)` loop, so the ordering is
//! free.
//!
//! A Metal port that tiles levels across THREADGROUPS in ONE dispatch cannot get
//! that ordering for free: `threadgroup_barrier` only orders one threadgroup, and
//! `simdgroup_barrier` is execution-only with no memory fence. So a level-(ℓ+1)
//! threadgroup can read `work` BEFORE the level-ℓ threadgroup has written its
//! lifted parents — it reads the STALE original-leaf value instead of the parent.
//!
//! This test MODELS that race in pure Zig (no Metal needed): `analyzeRaced`
//! computes each level from a SNAPSHOT taken before the previous level wrote its
//! parents into the low half — exactly the stale read a missing global barrier
//! produces. The invariant under attack:
//!
//!     reconstruct(analyzeRaced(x)) == x        -- MUST FAIL (proves barrier is load-bearing)
//!     reconstruct(analyze(x))      == x        -- holds (the correct sequential kernel)
//!
//! Severity is MED and the guard state is "N/A — future port": today's Zig is
//! correct (sequential while-loops). The contract this test pins for the port is:
//! ONE dispatch per Haar level (log2(n) dispatches), OR keep the whole tree in one
//! threadgroup with threadgroup_barrier(mem_threadgroup) between levels. Never split
//! a single level's producers and the next level's consumers across threadgroups in
//! one barrier-less dispatch.

const std = @import("std");
const kernels = @import("kernels.zig");

/// Reference S-transform forward, identical arithmetic to `s4_haar_analyze`'s
/// inner cell, but driven from a per-level SNAPSHOT so we can inject the race.
///
/// `analyzeRaced` deliberately reads the level-ℓ INPUTS from `snap` (a copy of the
/// buffer taken at the START of level ℓ's processing — i.e. BEFORE level ℓ−1's
/// parents have been flushed to the low half), instead of from the live `work`.
/// For the very first level (cur == n) there is nothing stale yet, so it matches.
/// From the second level on, the low-half slots it reads still hold the ORIGINAL
/// leaf values rather than the level-1 lifted parents → corrupted cascade. This is
/// precisely the byte-for-byte effect of a level-(ℓ+1) threadgroup racing ahead of
/// the level-ℓ threadgroup with no global memory barrier between them.
fn analyzeRaced(
    leaves: []const i32,
    n: usize,
    out_root: *[3]i32,
    out_offsets: []i32, // (n-1)*3
    work: []i32, // n*3 scratch
    snap: []i32, // n*3 scratch (the stale snapshot)
) void {
    for (0..n * 3) |i| work[i] = leaves[i];

    var cur: usize = n;
    var level: usize = 0;
    while (cur > 1) : (level += 1) {
        // Take the snapshot the racing consumer would see: for level 0 it is the
        // live (correct) buffer; for level ≥ 1 it is the buffer state from BEFORE
        // the previous level wrote its parents — modelled here as the original
        // leaves (the un-flushed producer output a barrier-less read would catch).
        if (level == 0) {
            for (0..n * 3) |i| snap[i] = work[i];
        } else {
            // stale: previous level's parents NOT yet visible in the low half.
            for (0..n * 3) |i| snap[i] = leaves[i];
        }

        const half = cur / 2;
        const out_start = half - 1;
        for (0..half) |i| {
            for (0..3) |c| {
                const x = snap[(2 * i) * 3 + c]; // <-- stale read on level ≥ 1
                const y = snap[(2 * i + 1) * 3 + c];
                const d = x - y;
                work[i * 3 + c] = y + @divFloor(d, 2);
                out_offsets[(out_start + i) * 3 + c] = d;
            }
        }
        cur = half;
    }
    out_root.* = .{ work[0], work[1], work[2] };
}

test "barrier-race: stale level-ℓ read breaks reconstruct∘analyze (port must barrier per level)" {
    const alloc = std.testing.allocator;

    // n = 4 leaves (depth 2) is the smallest case with a cross-level dependency:
    // level 0 lifts {leaf0,leaf1}→parent A and {leaf2,leaf3}→parent B, then level 1
    // lifts {A,B}→root. A barrier-less port races level 1 reading A,B before level 0
    // writes them ⇒ it reads leaf0,leaf2 instead.
    const n: usize = 4;

    // Adversarial witness: chosen so each level-0 lift MOVES the value
    //   parent = y + floor((x−y)/2) != x   (so the stale read is observably wrong),
    // and the values are large Q16 magnitudes (also touches the i32-headroom suspect,
    // though the race, not overflow, is what this test targets).
    // leaf pairs: (1<<20, 0) and ((1<<20)+7, 0). Odd delta exercises floor.
    const big: i32 = 1 << 20; // 0x100000, far above any real Q16 colour but legal i32
    const leaves = [_]i32{
        big,     0,  -3, // leaf0
        0,       11, 5, // leaf1
        big + 7, -9, 2, // leaf2
        0,       0,  0, // leaf3
    };

    var work: [n * 3]i32 = undefined;
    var snap: [n * 3]i32 = undefined;

    // --- correct sequential kernel: round-trips exactly (control) ---
    var good_root: [3]i32 = undefined;
    var good_off: [(n - 1) * 3]i32 = undefined;
    const scratch = try alloc.alloc(u8, n * 3 * @sizeOf(i32));
    defer alloc.free(scratch);
    const rc_a = kernels.s4_haar_analyze(&leaves, @intCast(n), &good_root, &good_off, scratch.ptr, scratch.len);
    try std.testing.expectEqual(kernels.RC_OK, rc_a);

    var good_leaves: [n * 3]i32 = undefined;
    const rc_r = kernels.s4_haar_reconstruct(&good_root, &good_off, @intCast(n), &good_leaves);
    try std.testing.expectEqual(kernels.RC_OK, rc_r);
    try std.testing.expectEqualSlices(i32, &leaves, &good_leaves); // INVARIANT holds for correct kernel

    // --- raced ("missing barrier") port: feed its output through the EXACT inverse ---
    var bad_root: [3]i32 = undefined;
    var bad_off: [(n - 1) * 3]i32 = undefined;
    analyzeRaced(&leaves, n, &bad_root, &bad_off, &work, &snap);

    var bad_leaves: [n * 3]i32 = undefined;
    const rc_br = kernels.s4_haar_reconstruct(&bad_root, &bad_off, @intCast(n), &bad_leaves);
    try std.testing.expectEqual(kernels.RC_OK, rc_br);

    // THE ASSERTION: the raced cascade does NOT round-trip — reconstruct∘analyzeRaced ≠ id.
    // If a future Metal port "optimised" away the per-level barrier, this is the bug it ships.
    const round_trips = std.mem.eql(i32, &leaves, &bad_leaves);
    try std.testing.expect(!round_trips);

    // And concretely: the corruption is in the level-1 parent (the root), because the
    // stale read used leaf0/leaf2 instead of the level-0 parents A,B.
    // Document the witnessed divergence for the failure report.
    if (!std.mem.eql(i32, &good_root, &bad_root)) {
        std.debug.print(
            "\n  [witness] race corrupts root: correct L-root={d} raced L-root={d} (stale level-0 parents)\n",
            .{ good_root[0], bad_root[0] },
        );
    }
}
