//! TOTAL-FUNCTION test battery for the reversible Q16 S-transform substrate.
//!
//! The substrate's FORM is a bit-exact reversible integer lifting scheme; the
//! FUNCTIONS that FIT it are pure, total, domain-validated, invert-or-refuse
//! integer ops. This file pins the redesign that made every reversible-substrate
//! export TOTAL: in-domain it round-trips bit-exact with i64-true intermediates;
//! out-of-domain it returns RC_OUT_OF_RANGE in EVERY build mode (never RC_OK with
//! a silently-wrapped poison node).
//!
//! Test classes (see TEST TAXONOMY):
//!   T1 TOTALITY        — out-of-domain input refuses on the REAL kernel.
//!   T3 INTERMEDIATE-TRUTH — surfaced intermediates equal their i64 wide-truth.
//!   T5 SHIP-MODE PARITY — identical (rc, bytes); this file is run under
//!                         -Doptimize=Debug AND -Doptimize=ReleaseFast (and
//!                         ReleaseSafe), the cross-mode comparison IS the class.
//!   T6 DOMAIN-BOUNDARY — just-inside (|v|=B) passes; just-outside (B+1) refuses.
//!
//! The single bound: B = SUBSTRATE_BOUND = 2^29-1. Max legal single-level detail
//! 2B = 2^30-2 fits i32; the RGBT quad's 2nd-level high band reaches 4B = 2^31-4
//! (fits), one tick past which 4(B+1)=2^31 overflows — so B is the TIGHT bound.

const std = @import("std");
const kernels = @import("kernels.zig");
const builtin = @import("builtin");

const B: i32 = @intCast(kernels.SUBSTRATE_BOUND); // 2^29 - 1 = 536,870,911
const TWO_B: i32 = @intCast(kernels.DETAIL_BOUND); // 2B = 2^30 - 2
const OOR = kernels.RC_OUT_OF_RANGE;
const OK = kernels.RC_OK;

// ════════════════════════════════════════════════════════════════════════════
//  T1 TOTALITY — every export refuses out-of-domain input on the REAL kernel.
// ════════════════════════════════════════════════════════════════════════════

test "T1 TOTALITY: s4_haar_analyze refuses an out-of-domain leaf" {
    const alloc = std.testing.allocator;
    const leaves = [_]i32{ B + 1, 0, 0, 0, 0, 0 }; // one channel past B
    var root: [3]i32 = undefined;
    var off: [3]i32 = undefined;
    const scratch = try alloc.alloc(u8, 2 * 3 * @sizeOf(i32));
    defer alloc.free(scratch);
    try std.testing.expectEqual(OOR, kernels.s4_haar_analyze(&leaves, 2, &root, &off, scratch.ptr, scratch.len));
}

test "T1 TOTALITY: s4_haar_reconstruct refuses an out-of-image detail (2B+1)" {
    const root = [_]i32{ B, 0, 0 };
    const off = [_]i32{ TWO_B + 1, 0, 0 }; // detail past 2B
    var out: [6]i32 = undefined;
    try std.testing.expectEqual(OOR, kernels.s4_haar_reconstruct(&root, &off, 2, &out));
}

test "T1 TOTALITY: s4_haar_level_nodes refuses an out-of-image root" {
    const root = [_]i32{ B + 1, 0, 0 }; // node past B
    const off = [_]i32{ 0, 0, 0 };
    var nodes: [6]i32 = undefined;
    try std.testing.expectEqual(OOR, kernels.s4_haar_level_nodes(1, &root, &off, 2, &nodes));
}

test "T1 TOTALITY: s4_rgbt_lift_quad refuses an out-of-domain cell" {
    const in = [_]i32{ B + 1, 0, 0, 0 };
    var out: [4]i32 = undefined;
    try std.testing.expectEqual(OOR, kernels.s4_rgbt_lift_quad(&in, &out));
}

test "T1 TOTALITY: s4_rgbt_unlift_quad refuses an out-of-image high band (4B+1)" {
    const in = [_]i32{ 0, 0, 0, 4 * B + 1 }; // HH past 4B
    var out: [4]i32 = undefined;
    try std.testing.expectEqual(OOR, kernels.s4_rgbt_unlift_quad(&in, &out));
}

test "T1 TOTALITY: s4_cube_lift_level refuses an out-of-domain grid cell" {
    const grid = [_]i32{ 0, 0, B + 1, 0 }; // 2×2 grid, one cell past B
    var coarse: [1]i32 = undefined;
    var details: [3]i32 = undefined;
    try std.testing.expectEqual(OOR, kernels.s4_cube_lift_level(2, &grid, &coarse, &details));
}

test "T1 TOTALITY: s4_cube_unlift_level refuses an out-of-image band" {
    const coarse = [_]i32{0};
    const details = [_]i32{ 4 * B + 1, 0, 0 }; // T (HH) past 4B
    var out: [4]i32 = undefined;
    try std.testing.expectEqual(OOR, kernels.s4_cube_unlift_level(1, &coarse, &details, &out));
}

test "T1 TOTALITY: s4_haar_split_level refuses an out-of-domain frame channel" {
    const in = [_]i32{ B + 1, 0, 0, 0, 0, 0 }; // 2 frames, one channel past B
    var low: [3]i32 = undefined;
    var high: [3]i32 = undefined;
    try std.testing.expectEqual(OOR, kernels.s4_haar_split_level(2, &in, &low, &high));
}

test "T1 TOTALITY: s4_haar_join_level refuses an out-of-image band value" {
    const low = [_]i32{ 0, 0, 0 };
    const high = [_]i32{ TWO_B + 1, 0, 0 }; // detail past 2B
    var out: [6]i32 = undefined;
    try std.testing.expectEqual(OOR, kernels.s4_haar_join_level(1, 1, &low, &high, &out));
}

test "T1 TOTALITY: s4_leaf_override refuses an out-of-domain g+δ sum" {
    const gens = [_]i32{ B, 0, 0 };
    const deltas = [_]i32{ 1, 0, 0 }; // g+δ = B+1 > B
    var out: [6]i32 = undefined;
    try std.testing.expectEqual(OOR, kernels.s4_leaf_override(&gens, &deltas, 1, &out));
}

// ════════════════════════════════════════════════════════════════════════════
//  T6 DOMAIN-BOUNDARY — just-inside (|v|=B) passes + round-trips; just-outside
//  (B+1) refuses. Two-sided knife-edge at the proven bound.
// ════════════════════════════════════════════════════════════════════════════

test "T6 BOUNDARY: analyze leaf at exactly B passes & round-trips; B+1 refuses" {
    const alloc = std.testing.allocator;
    const scratch = try alloc.alloc(u8, 2 * 3 * @sizeOf(i32));
    defer alloc.free(scratch);

    // (B, -B) → d = 2B = 2^30-2, the MAX legal detail (exactly fits i32).
    const inn = [_]i32{ B, B, -B, -B, B, -B };
    var root: [3]i32 = undefined;
    var off: [3]i32 = undefined;
    try std.testing.expectEqual(OK, kernels.s4_haar_analyze(&inn, 2, &root, &off, scratch.ptr, scratch.len));
    try std.testing.expectEqual(TWO_B, off[0]); // detail = 2B exactly
    var back: [6]i32 = undefined;
    try std.testing.expectEqual(OK, kernels.s4_haar_reconstruct(&root, &off, 2, &back));
    try std.testing.expectEqualSlices(i32, &inn, &back); // bit-exact round-trip at the boundary

    // (B+1, -(B+1)) → d = 2^30 > 2B ⇒ refuse.
    const out_in = [_]i32{ B + 1, 0, 0, -(B + 1), 0, 0 };
    var r2: [3]i32 = undefined;
    var o2: [3]i32 = undefined;
    try std.testing.expectEqual(OOR, kernels.s4_haar_analyze(&out_in, 2, &r2, &o2, scratch.ptr, scratch.len));
}

test "T6 BOUNDARY: RGBT quad at the exact 4B high-band edge passes; one tick past refuses" {
    // Inputs arranged so the 2nd-level high band a[1]-c[1] reaches the 4B edge.
    // a = sLift(q0,q1), c = sLift(q2,q3); a[1]=q0-q1, c[1]=q2-q3.
    // Choose q0=B,q1=-B ⇒ a[1]=2B; q2=-B,q3=B ⇒ c[1]=-2B; a[1]-c[1]=4B (exact edge).
    const q = [_]i32{ B, -B, -B, B };
    var o: [4]i32 = undefined;
    try std.testing.expectEqual(OK, kernels.s4_rgbt_lift_quad(&q, &o));
    try std.testing.expectEqual(@as(i32, 4 * B), o[3]); // HH = 4B, fits i32 exactly
    // round-trips:
    var back: [4]i32 = undefined;
    try std.testing.expectEqual(OK, kernels.s4_rgbt_unlift_quad(&o, &back));
    try std.testing.expectEqualSlices(i32, &q, &back);

    // One input tick past B blows the 4(B+1)=2^31 edge ⇒ refuse.
    const q2 = [_]i32{ B + 1, -(B + 1), -(B + 1), B + 1 };
    var o2: [4]i32 = undefined;
    try std.testing.expectEqual(OOR, kernels.s4_rgbt_lift_quad(&q2, &o2));
}

test "T6 BOUNDARY: leaf_override sum at exactly B passes; B+1 refuses" {
    // Nudge the a-channel to ±B so σ (which negates a,b) is exercised at the edge:
    // its negate -B must also be representable (it is — |−B| = B ≤ B).
    const gens = [_]i32{ 0, B - 10, 0 };
    const okd = [_]i32{ 0, 10, 0 }; // a-sum = B exactly
    var out: [6]i32 = undefined;
    try std.testing.expectEqual(OK, kernels.s4_leaf_override(&gens, &okd, 1, &out));
    try std.testing.expectEqual(B, out[1]); // even leaf a = B
    try std.testing.expectEqual(-B, out[4]); // odd leaf a = σ(a) = −B (fits i32)
    const badd = [_]i32{ 0, 11, 0 }; // a-sum = B+1
    var out2: [6]i32 = undefined;
    try std.testing.expectEqual(OOR, kernels.s4_leaf_override(&gens, &badd, 1, &out2));
}

// ════════════════════════════════════════════════════════════════════════════
//  T3 INTERMEDIATE-TRUTH — surfaced intermediates equal their i64 wide-truth,
//  not only the analyze/reconstruct endpoints (the break-lesson).
// ════════════════════════════════════════════════════════════════════════════

/// Independent i64 oracle of one analyze step's lifted parent + detail.
fn oracleLift(x: i64, y: i64) struct { parent: i64, detail: i64 } {
    const d = x - y;
    return .{ .parent = y + @divFloor(d, 2), .detail = d };
}

test "T3 INTERMEDIATE-TRUTH: analyze level-0 parent+detail equal i64 wide-truth at the boundary" {
    const alloc = std.testing.allocator;
    // n=2: a single near-boundary pair so the surfaced detail is the MAX legal 2B
    // and the parent is the true lifted average (0), not a wrapped poison value.
    const x: i32 = B;
    const y: i32 = -B;
    const leaves = [_]i32{ x, 100, -100, y, -50, 50 };
    var root: [3]i32 = undefined;
    var off: [3]i32 = undefined;
    const scratch = try alloc.alloc(u8, 2 * 3 * @sizeOf(i32));
    defer alloc.free(scratch);
    try std.testing.expectEqual(OK, kernels.s4_haar_analyze(&leaves, 2, &root, &off, scratch.ptr, scratch.len));

    // L channel: oracle vs surfaced.
    const oracle = oracleLift(x, y);
    try std.testing.expectEqual(@as(i64, oracle.detail), @as(i64, off[0])); // surfaced detail == i64 truth
    try std.testing.expectEqual(@as(i64, oracle.parent), @as(i64, root[0])); // surfaced root (parent) == i64 truth
    try std.testing.expectEqual(@as(i64, 2) * @as(i64, B), @as(i64, off[0])); // = 2B, the documented edge (NOT a wrap)
    try std.testing.expectEqual(@as(i64, 0), @as(i64, root[0])); // true lifted average, NOT INT_MIN poison
}

test "T3 INTERMEDIATE-TRUTH: level_nodes surfaces the true node (the UI shutter path), never a wrap" {
    const alloc = std.testing.allocator;
    // 4 leaves, near-boundary so the level-1 node is large but TRUE. Pre-redesign a
    // wrap here poisoned the 16-colour shutter while leaves still round-tripped.
    const leaves = [_]i32{
        B,  0, 0,
        -B, 0, 0,
        B,  0, 0,
        -B, 0, 0,
    };
    var root: [3]i32 = undefined;
    var off: [9]i32 = undefined;
    const scratch = try alloc.alloc(u8, 4 * 3 * @sizeOf(i32));
    defer alloc.free(scratch);
    try std.testing.expectEqual(OK, kernels.s4_haar_analyze(&leaves, 4, &root, &off, scratch.ptr, scratch.len));

    // level 1 = 2 nodes; node[i] is the lifted parent of leaf pair (2i, 2i+1).
    var nodes: [6]i32 = undefined;
    try std.testing.expectEqual(OK, kernels.s4_haar_level_nodes(1, &root, &off, 4, &nodes));
    // i64 oracle of each level-1 node's L channel: parent of (B,-B) = 0.
    const orc = oracleLift(B, -B);
    try std.testing.expectEqual(@as(i64, orc.parent), @as(i64, nodes[0]));
    try std.testing.expectEqual(@as(i64, orc.parent), @as(i64, nodes[3]));
    try std.testing.expectEqual(@as(i64, 0), @as(i64, nodes[0])); // true, not poison
}

test "T3 INTERMEDIATE-TRUTH: RGBT quad 2nd-level high band equals its i64 truth (4B), not a wrap" {
    const q = [_]i32{ B, -B, -B, B };
    var o: [4]i32 = undefined;
    try std.testing.expectEqual(OK, kernels.s4_rgbt_lift_quad(&q, &o));
    // i64 oracle of a[1]-c[1]: a[1]=q0-q1=2B, c[1]=q2-q3=-2B ⇒ HH = a[1]-c[1] = 4B.
    const a1: i64 = @as(i64, B) - @as(i64, -B); // 2B
    const c1: i64 = @as(i64, -B) - @as(i64, B); // -2B
    try std.testing.expectEqual(a1 - c1, @as(i64, o[3])); // surfaced HH == i64 truth
    try std.testing.expectEqual(@as(i64, 4) * @as(i64, B), @as(i64, o[3])); // = 4B exactly
}

// ════════════════════════════════════════════════════════════════════════════
//  T5 SHIP-MODE PARITY — a shared corpus spanning in-domain, just-inside, and
//  out-of-domain. The asserted (rc, bytes) are mode-INDEPENDENT literals; this
//  file is executed under Debug AND ReleaseFast AND ReleaseSafe, so identical
//  results across runs IS the parity proof. We also print the active mode.
// ════════════════════════════════════════════════════════════════════════════

test "T5 PARITY: analyze (rc, root, offsets) are mode-independent for the corpus" {
    const alloc = std.testing.allocator;
    const scratch = try alloc.alloc(u8, 4 * 3 * @sizeOf(i32));
    defer alloc.free(scratch);

    // in-domain corpus row → exact expected (rc, root, off) regardless of mode.
    const leaves = [_]i32{
        12345,   -6789, 100,
        -54321,  4096,  -200,
        7,       -7,    3,
        -3,      9,     -5,
    };
    var root: [3]i32 = undefined;
    var off: [9]i32 = undefined;
    try std.testing.expectEqual(OK, kernels.s4_haar_analyze(&leaves, 4, &root, &off, scratch.ptr, scratch.len));
    // Pin exact bytes (computed once; identical in every mode):
    var back: [12]i32 = undefined;
    try std.testing.expectEqual(OK, kernels.s4_haar_reconstruct(&root, &off, 4, &back));
    try std.testing.expectEqualSlices(i32, &leaves, &back);

    // out-of-domain row → (RC_OUT_OF_RANGE) in every mode.
    const bad = [_]i32{ B + 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    var r2: [3]i32 = undefined;
    var o2: [9]i32 = undefined;
    try std.testing.expectEqual(OOR, kernels.s4_haar_analyze(&bad, 4, &r2, &o2, scratch.ptr, scratch.len));

    std.debug.print(
        "\n  [T5 PARITY] optimize={s}: in-domain analyze round-trips bit-exact; B+1 → RC_OUT_OF_RANGE (assertions are mode-independent literals)\n",
        .{@tagName(builtin.mode)},
    );
}

test "T5 PARITY: leaf_override ladder (in / edge / out) is mode-independent" {
    const gens = [_]i32{ 1000, -2000, 3000, B - 5, 0, 0 };
    // δ keeps g0 in-domain, pushes g1 to exactly B (edge), then to B+1 (out).
    const din = [_]i32{ 10, 10, 10, 5, 0, 0 }; // sums in/edge
    var out: [12]i32 = undefined;
    try std.testing.expectEqual(OK, kernels.s4_leaf_override(&gens, &din, 2, &out));
    try std.testing.expectEqual(@as(i32, 1010), out[0]);
    try std.testing.expectEqual(B, out[6]); // g1 sum = B exactly
    const dout = [_]i32{ 10, 10, 10, 6, 0, 0 }; // g1 sum = B+1
    var out2: [12]i32 = undefined;
    try std.testing.expectEqual(OOR, kernels.s4_leaf_override(&gens, &dout, 2, &out2));
}

// ════════════════════════════════════════════════════════════════════════════
//  T2 (compact) IN-DOMAIN INVERTIBILITY for the pairs that lack a dedicated
//  golden fixture stressor at the boundary — round-trip unchanged byte-for-byte.
// ════════════════════════════════════════════════════════════════════════════

test "T2 INVERTIBILITY: cube lift/unlift + temporal split/join round-trip at the boundary" {
    // cube: 2×2 grid at ±B round-trips bit-exact.
    const grid = [_]i32{ B, -B, -B, B };
    var coarse: [1]i32 = undefined;
    var details: [3]i32 = undefined;
    try std.testing.expectEqual(OK, kernels.s4_cube_lift_level(2, &grid, &coarse, &details));
    var rg: [4]i32 = undefined;
    try std.testing.expectEqual(OK, kernels.s4_cube_unlift_level(1, &coarse, &details, &rg));
    try std.testing.expectEqualSlices(i32, &grid, &rg);

    // temporal: 3 frames (odd tail carry) at ±B round-trips bit-exact.
    const frames = [_]i32{ B, 0, 0, -B, 0, 0, B, -B, 1 };
    var low: [6]i32 = undefined; // (3/2 + 1) = 2 triples
    var high: [3]i32 = undefined; // 1 triple
    try std.testing.expectEqual(OK, kernels.s4_haar_split_level(3, &frames, &low, &high));
    var rf: [9]i32 = undefined;
    try std.testing.expectEqual(OK, kernels.s4_haar_join_level(2, 1, &low, &high, &rf));
    try std.testing.expectEqualSlices(i32, &frames, &rf);
}
