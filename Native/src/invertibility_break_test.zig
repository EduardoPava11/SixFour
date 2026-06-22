//! ADVERSARIAL invertibility break-hunt for the owned integer Haar/S-transform.
//!
//! GOAL: try to break `reconstruct ∘ analyze == id` (byte-exact) on the Zig →
//! Metal-shared-buffer → SIMT/tensor → Core AI ship path. Each test is a concrete,
//! runnable witness for one hazard class.
//!
//! POST-REDESIGN (total-function substrate): the reversible-substrate exports are
//! now TOTAL — out-of-domain inputs (|v| > B = 2^29−1, or a supplied detail/node
//! outside the legal image) return RC_OUT_OF_RANGE in EVERY build mode instead of
//! panicking (Debug/ReleaseSafe) or silently wrapping (ReleaseFast). So the former
//! overflow witnesses, which used to only MODEL the wrap with `-%`/`+%` because the
//! unguarded kernel was uncallable, now CALL THE REAL KERNEL and assert it REFUSES.
//! The retained `@subWithOverflow`/i64 commentary documents WHY the value is
//! out-of-domain (the historical defect's signature). Ship-mode parity for these
//! refusals is asserted in totality_test.zig.
//!
//! Witnesses that stay inside i32 (negative-odd-detail floor/trunc fork, in-place
//! aliasing race, fp16 tensor loss, unified-memory stale read, ULP/grid bypass)
//! run the REAL kernel directly with in-domain values.

const std = @import("std");
const kernels = @import("kernels.zig");

// ════════════════════════════════════════════════════════════════════════════
//  Helpers
// ════════════════════════════════════════════════════════════════════════════

/// Run the real analyze→reconstruct round trip on `leaves` (n triples). Returns
/// true iff byte-exact. SAFE to call only when no intermediate overflows i32.
fn realRoundTrips(alloc: std.mem.Allocator, leaves: []const i32, n: i32) !bool {
    const nn: usize = @intCast(n);
    var root: [3]i32 = undefined;
    const off = try alloc.alloc(i32, (nn - 1) * 3);
    defer alloc.free(off);
    const scratch = try alloc.alloc(u8, nn * 3 * @sizeOf(i32));
    defer alloc.free(scratch);
    const rc_a = kernels.s4_haar_analyze(leaves.ptr, n, &root, off.ptr, scratch.ptr, scratch.len);
    if (rc_a != kernels.RC_OK) return error.AnalyzeFailed;
    const got = try alloc.alloc(i32, nn * 3);
    defer alloc.free(got);
    const rc_r = kernels.s4_haar_reconstruct(&root, off.ptr, n, got.ptr);
    if (rc_r != kernels.RC_OK) return error.ReconstructFailed;
    return std.mem.eql(i32, leaves, got);
}

// ════════════════════════════════════════════════════════════════════════════
//  (a) i32 OVERFLOW in d = x - y / y + d — the unbounded-input hazard.
//      Vectors: i32-overflow-d-x-minus-y, build-mode-flip-debug-to-releasefast,
//               i32-overflow-releasefast-silent, releasefast-i32-overflow-silent,
//               metal-int-divzero-intmin-ub, msl-signed-overflow-UB.
// ════════════════════════════════════════════════════════════════════════════

test "OVERFLOW: d=x-y at extreme opposite-sign Q16 — REAL analyze now REFUSES (RC_OUT_OF_RANGE)" {
    const alloc = std.testing.allocator;
    // Witness: x = +2,000,000,000, y = -2,000,000,000 (both legal i32, ~18x past
    // the substrate bound B=2^29-1, reachable via s4_leaf_override's δ). d = x - y =
    // 4,000,000,000 > i32 max. PRE-redesign: Debug panicked, ReleaseFast wrapped d
    // to -294,967,296 (RC_OK + poison surfaced parent). POST-redesign: REFUSE.
    const x: i32 = 2_000_000_000;
    const y: i32 = -2_000_000_000;
    const d_true: i64 = @as(i64, x) - @as(i64, y);
    try std.testing.expectEqual(@as(i64, 4_000_000_000), d_true); // the wide-truth detail

    const leaves = [_]i32{ x, 1, -1, y, 2, -2 }; // n=2; first L-channel pair is the OOR witness
    var root: [3]i32 = .{ 0, 0, 0 };
    var off: [3]i32 = .{ 0, 0, 0 };
    const scratch = try alloc.alloc(u8, 2 * 3 * @sizeOf(i32));
    defer alloc.free(scratch);
    const rc = kernels.s4_haar_analyze(&leaves, 2, &root, &off, scratch.ptr, scratch.len);
    // THE ASSERTION: total function — explicit refusal, not RC_OK-with-corruption.
    try std.testing.expectEqual(kernels.RC_OUT_OF_RANGE, rc);
    std.debug.print(
        "\n  [TOTALITY a] analyze(x=2e9,y=-2e9): true d={d} would overflow i32 → REAL kernel returns RC_OUT_OF_RANGE (was: ReleaseFast RC_OK + poison parent)\n",
        .{d_true},
    );
}

test "OVERFLOW: absolute-extreme leaves INT_MAX/INT_MIN — REAL analyze REFUSES" {
    const alloc = std.testing.allocator;
    const x: i32 = std.math.maxInt(i32);
    const y: i32 = std.math.minInt(i32);
    const leaves = [_]i32{ x, 0, 0, y, 0, 0 };
    var root: [3]i32 = undefined;
    var off: [3]i32 = undefined;
    const scratch = try alloc.alloc(u8, 2 * 3 * @sizeOf(i32));
    defer alloc.free(scratch);
    // Both leaves are far out of domain ⇒ refuse at the input-validation head.
    try std.testing.expectEqual(kernels.RC_OUT_OF_RANGE, kernels.s4_haar_analyze(&leaves, 2, &root, &off, scratch.ptr, scratch.len));
    std.debug.print("\n  [TOTALITY a] analyze(INT_MAX,INT_MIN): out-of-domain leaves → RC_OUT_OF_RANGE\n", .{});
}

test "OVERFLOW: reconstruct-side hand-crafted out-of-image offsets — REAL reconstruct REFUSES" {
    // PRE: root=INT_MAX, d=INT_MAX → x=y+d overflowed in reconstruct (silent wrap in
    // ReleaseFast). POST: the supplied node/detail are outside the legal image
    // (|node| ≤ B, |detail| ≤ 2B), so reconstruct refuses.
    const root = [_]i32{ std.math.maxInt(i32), 0, 0 };
    const off = [_]i32{ std.math.maxInt(i32), 0, 0 };
    var out: [6]i32 = undefined;
    try std.testing.expectEqual(kernels.RC_OUT_OF_RANGE, kernels.s4_haar_reconstruct(&root, &off, 2, &out));

    // Also a node that is IN-range but a detail just past 2B: y+d would overflow the
    // ±B image → refuse on the per-detail check inside unliftChecked.
    const root2 = [_]i32{ @intCast(kernels.SUBSTRATE_BOUND), 0, 0 };
    const off2 = [_]i32{ @intCast(kernels.DETAIL_BOUND + 1), 0, 0 };
    var out2: [6]i32 = undefined;
    try std.testing.expectEqual(kernels.RC_OUT_OF_RANGE, kernels.s4_haar_reconstruct(&root2, &off2, 2, &out2));
    std.debug.print("\n  [TOTALITY a] reconstruct with out-of-image root/offsets → RC_OUT_OF_RANGE\n", .{});
}

// ════════════════════════════════════════════════════════════════════════════
//  s4_leaf_override unbounded add — the USER-CONTROLLED entry point (taste δ,
//  Core AI float re-entry). Vectors: leaf-override-unclamped-feeds-lift,
//  sigma-override-unbounded-add-then-lift, coreai-float-not-quarantined-behind-reenterq16.
// ════════════════════════════════════════════════════════════════════════════

test "LEAF-OVERRIDE: null δ ≡ zero δ ≡ floor byte-exact (the zero-genome==floor quarantine)" {
    const gens = [_]i32{ 50000, -12000, 9000, -3000, 40000, -25000 }; // 2 generators
    const zero = [_]i32{ 0, 0, 0, 0, 0, 0 };
    var out_null: [12]i32 = undefined;
    var out_zero: [12]i32 = undefined;
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_leaf_override(&gens, null, 2, &out_null));
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_leaf_override(&gens, &zero, 2, &out_zero));
    // null path == zero-δ path byte-for-byte (the no-op short-circuit IS the floor):
    try std.testing.expectEqualSlices(i32, &out_null, &out_zero);
    // and equals the raw σ-pair of the generators (the floor):
    const expect = [_]i32{
        50000,  -12000, 9000,  50000,  12000,  -9000, // g0, σ(g0)
        -3000,  40000,  -25000, -3000, -40000, 25000, // g1, σ(g1)
    };
    try std.testing.expectEqualSlices(i32, &expect, &out_null);
}

test "LEAF-OVERRIDE: g+δ at i32 ceiling — REAL kernel REFUSES at the producer (RC_OUT_OF_RANGE)" {
    // PRE: generator at maxInt, δ=+1 → g+δ overflowed (panic Debug / wrap ReleaseFast,
    // RC_OK with a wildly wrong leaf aliased onto the floor). POST: the producer
    // validates |g+δ| ≤ B in i64 and refuses — the cheapest place to reject.
    const gens = [_]i32{ std.math.maxInt(i32), 0, 0 };
    const deltas = [_]i32{ 1, 0, 0 };
    var out: [6]i32 = undefined;
    try std.testing.expectEqual(kernels.RC_OUT_OF_RANGE, kernels.s4_leaf_override(&gens, &deltas, 1, &out));

    // Even a "legal-looking" sum past B refuses: ga = 2^30 (the old widen ceiling) >
    // B = 2^29-1, and would have made the downstream analyze detail ga-(-ga)=2^31
    // overflow. The producer stops it here.
    const gens2 = [_]i32{ 0, 1 << 30, 0 }; // a-channel sum = 2^30 > B
    var out2: [6]i32 = undefined;
    try std.testing.expectEqual(kernels.RC_OUT_OF_RANGE, kernels.s4_leaf_override(&gens2, null, 1, &out2));
    std.debug.print(
        "\n  [TOTALITY a/override] s4_leaf_override refuses |g+δ| > B: g=INT_MAX+δ AND legal-looking ga=2^30 both → RC_OUT_OF_RANGE\n",
        .{},
    );
}

test "LEAF-OVERRIDE: ga = INT_MIN (σ-negate had no i32 counterpart) — REAL kernel REFUSES" {
    // PRE: out[o+4] = -ga negated INT_MIN (overflow). POST: |ga| = 2^31 ≫ B, so the
    // producer refuses before any negate — the σ-pair can never be malformed.
    const gens = [_]i32{ 0, std.math.minInt(i32), 0 };
    var out: [6]i32 = undefined;
    try std.testing.expectEqual(kernels.RC_OUT_OF_RANGE, kernels.s4_leaf_override(&gens, null, 1, &out));
    std.debug.print("\n  [TOTALITY a/override] σ-generator INT_MIN out of domain → RC_OUT_OF_RANGE (no malformed negate)\n", .{});
}

// ════════════════════════════════════════════════════════════════════════════
//  (b) @divFloor vs @divTrunc sign — the negative-odd-detail floor contract.
//      Vectors: divfloor-sign-correct-not-divtrunc, divfloor-vs-divtrunc-sign,
//               divfloor-vs-trunc-sign-trap, divfloor-vs-c-trunc-on-metal-port.
// ════════════════════════════════════════════════════════════════════════════

/// Trunc-port inverse (the C `/` / signed `>>1` an MSL/Metal port emits).
fn reconstructTrunc(alloc: std.mem.Allocator, root: *const [3]i32, off: []const i32, n: i32) ![]i32 {
    const nn: usize = @intCast(n);
    const out = try alloc.alloc(i32, nn * 3);
    out[0] = root[0];
    out[1] = root[1];
    out[2] = root[2];
    var cur: usize = 1;
    while (cur < nn) {
        const out_start = cur - 1;
        var i: usize = cur;
        while (i > 0) {
            i -= 1;
            for (0..3) |c| {
                const node = out[i * 3 + c];
                const d = off[(out_start + i) * 3 + c];
                const y = node - @divTrunc(d, 2); // <-- TRUNC, the wrong primitive
                out[(2 * i) * 3 + c] = y + d;
                out[(2 * i + 1) * 3 + c] = y;
            }
        }
        cur *= 2;
    }
    return out;
}

test "DIVFLOOR: negative-odd-detail round-trips exactly with floor; a trunc-port inverse PROVABLY diverges" {
    const alloc = std.testing.allocator;
    // Witness on signed a/b channels, every level produces odd-negative details.
    // a-channel min/max extremes: x=-32768, y=+32767 → d=-65535 (odd, negative).
    const leaves = [_]i32{
        -32768, 0,    1, // leaf0
        32767,  -128, -1, // leaf1
        -3,     127,  -5, // leaf2
        0,      -64,  33, // leaf3
    };
    const n: i32 = 4;
    // floor (real kernel) round-trips byte-exact:
    try std.testing.expect(try realRoundTrips(alloc, &leaves, n));

    // analyze, then run the trunc-port inverse and assert it DIVERGES.
    var root: [3]i32 = undefined;
    var off: [9]i32 = undefined;
    const scratch = try alloc.alloc(u8, 4 * 3 * @sizeOf(i32));
    defer alloc.free(scratch);
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_haar_analyze(&leaves, n, &root, &off, scratch.ptr, scratch.len));
    const trunc_leaves = try reconstructTrunc(alloc, &root, &off, n);
    defer alloc.free(trunc_leaves);
    // Non-vacuity: floor != trunc on these details, so the trunc port BREAKS id.
    try std.testing.expect(!std.mem.eql(i32, &leaves, trunc_leaves));

    // Pin the canonical fork numerically: d=-1 → floor=-1, trunc=0.
    try std.testing.expectEqual(@as(i32, -1), @divFloor(@as(i32, -1), 2));
    try std.testing.expectEqual(@as(i32, 0), @divTrunc(@as(i32, -1), 2));
    // Even control: d=-4 → floor==trunc==-2 (test only fires on odd-negative).
    try std.testing.expectEqual(@divFloor(@as(i32, -4), 2), @divTrunc(@as(i32, -4), 2));
}

// ════════════════════════════════════════════════════════════════════════════
//  (c) IN-PLACE reconstruct expansion is order-dependent (naive parallel port).
//      Vectors: inplace-reconstruct-parallel-write-read-hazard,
//               inplace-reconstruct-parallel-aliasing, inplace-expansion-parallel-race,
//               metal-inplace-reconstruct-race.
// ════════════════════════════════════════════════════════════════════════════

/// ASCENDING in-place expansion — the data-flow a naive one-thread-per-i Metal
/// dispatch realizes (writes slot 2i before a later i reads slot i).
fn reconstructAscending(alloc: std.mem.Allocator, root: *const [3]i32, off: []const i32, n: i32) ![]i32 {
    const nn: usize = @intCast(n);
    const out = try alloc.alloc(i32, nn * 3);
    out[0] = root[0];
    out[1] = root[1];
    out[2] = root[2];
    var cur: usize = 1;
    while (cur < nn) {
        const out_start = cur - 1;
        var i: usize = 0;
        while (i < cur) : (i += 1) { // <-- ASCENDING (the hazard)
            for (0..3) |c| {
                const node = out[i * 3 + c];
                const d = off[(out_start + i) * 3 + c];
                const y = node - @divFloor(d, 2);
                out[(2 * i) * 3 + c] = y + d;
                out[(2 * i + 1) * 3 + c] = y;
            }
        }
        cur *= 2;
    }
    return out;
}

test "IN-PLACE RACE: descending reconstruct round-trips; ascending (naive parallel) PROVABLY corrupts" {
    const alloc = std.testing.allocator;
    // n=8, large mixed-sign details at every level so a clobbered slot can never
    // coincidentally equal the correct value.
    const leaves = [_]i32{
        1 << 27,    1,        -1,
        -(1 << 27), 2,        -2,
        0,          1 << 26,  7,
        123457,     -(1 << 26), -3,
        -1,         3,        5,
        1 << 25,    -4,       11,
        -3,         6,        -9,
        5,          -7,       13,
    };
    const n: i32 = 8;
    // descending (real kernel) round-trips:
    try std.testing.expect(try realRoundTrips(alloc, &leaves, n));

    var root: [3]i32 = undefined;
    var off: [21]i32 = undefined;
    const scratch = try alloc.alloc(u8, 8 * 3 * @sizeOf(i32));
    defer alloc.free(scratch);
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_haar_analyze(&leaves, n, &root, &off, scratch.ptr, scratch.len));
    const asc = try reconstructAscending(alloc, &root, &off, n);
    defer alloc.free(asc);
    // ASSERTION: ascending order does NOT round-trip → ordering is load-bearing.
    try std.testing.expect(!std.mem.eql(i32, &leaves, asc));
}

// ════════════════════════════════════════════════════════════════════════════
//  (d/barrier) level-sequential dependency — already covered by sibling tests
//      (haar_barrier_race_test, haar_barrier_hazard_test). One compact restatement
//      here for completeness: stale (pre-level) read of a parent breaks id.
//      Vectors: metal-level-sequential-barrier, level-sequential-missing-barrier,
//               metal-level-sequential-missing-barrier, untracked-hazard-mode-inplace-no-barrier.
// ════════════════════════════════════════════════════════════════════════════

test "BARRIER: stale level-ℓ parent read breaks reconstruct; sequential kernel holds" {
    const alloc = std.testing.allocator;
    // n=4, parents move at every level (odd detail +7, large magnitude).
    const leaves = [_]i32{
        1 << 20,     0,  -3,
        0,           11, 5,
        (1 << 20) + 7, -9, 2,
        0,           0,  0,
    };
    const n: usize = 4;
    try std.testing.expect(try realRoundTrips(alloc, &leaves, @intCast(n)));

    // Model the missing global barrier: level ≥1 reads the ORIGINAL leaves (stale,
    // un-flushed low half) instead of level-0's lifted parents.
    var work: [n * 3]i32 = undefined;
    var snap: [n * 3]i32 = undefined;
    for (0..n * 3) |i| work[i] = leaves[i];
    var off: [(n - 1) * 3]i32 = undefined;
    var cur: usize = n;
    var level: usize = 0;
    while (cur > 1) : (level += 1) {
        if (level == 0) {
            for (0..n * 3) |i| snap[i] = work[i];
        } else {
            for (0..n * 3) |i| snap[i] = leaves[i]; // STALE
        }
        const half = cur / 2;
        const out_start = half - 1;
        for (0..half) |i| {
            for (0..3) |c| {
                const x = snap[(2 * i) * 3 + c];
                const y = snap[(2 * i + 1) * 3 + c];
                const d = x - y;
                work[i * 3 + c] = y + @divFloor(d, 2);
                off[(out_start + i) * 3 + c] = d;
            }
        }
        cur = half;
    }
    const raced_root = [_]i32{ work[0], work[1], work[2] };
    var raced_leaves: [n * 3]i32 = undefined;
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_haar_reconstruct(&raced_root, &off, @intCast(n), &raced_leaves));
    // ASSERTION: the raced cascade does NOT round-trip.
    try std.testing.expect(!std.mem.eql(i32, &leaves, &raced_leaves));
}

// ════════════════════════════════════════════════════════════════════════════
//  (e) Metal-4 SIMT/tensor cores are FLOAT (fp16/bf16) → non-exact for the lift.
//      Vectors: metal4-simt-tensor-float-contamination, metal-tensor-simt-is-float-or-low-int,
//               metal4-tensor-no-int32, metal4-simt-tensor-float-cores.
// ════════════════════════════════════════════════════════════════════════════

/// Coerce an i32 through f16 (the cooperative-matrix element type) and back.
fn thruF16(v: i32) i32 {
    const f: f16 = @floatFromInt(v); // may round / saturate
    if (!std.math.isFinite(@as(f32, f))) return v; // (witness keeps finite)
    return @intFromFloat(@round(@as(f32, f)));
}

test "TENSOR-FLOAT: integer lift exact, fp16 cooperative-matrix lift PROVABLY loses low Q16 bits" {
    const alloc = std.testing.allocator;
    // Detail 2049 = smallest int above fp16's 2048 exact-integer ceiling.
    const leaves = [_]i32{
        2049, 4097, -2049, // leaf0 — all three details just past 2^11
        0,    0,    0, // leaf1
    };
    const n: i32 = 2;
    // (1) INTEGER PATH EXACT:
    try std.testing.expect(try realRoundTrips(alloc, &leaves, n));
    var root: [3]i32 = undefined;
    var off: [3]i32 = undefined;
    const scratch = try alloc.alloc(u8, 2 * 3 * @sizeOf(i32));
    defer alloc.free(scratch);
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_haar_analyze(&leaves, n, &root, &off, scratch.ptr, scratch.len));
    try std.testing.expectEqual(@as(i32, 2049), off[0]); // L detail exact in i32

    // (2) FLOAT PATH LOSSY: route the detail through f16 → collapses 2049 → 2048.
    const rt = thruF16(off[0]);
    try std.testing.expectEqual(@as(i32, 2048), rt);
    try std.testing.expect(rt != off[0]);

    // Confirm a full fp16-lift round trip breaks id on a higher-magnitude witness.
    // Pair (65537, 1): d=65536, parent=1+32768=32769 → f16 parent 32769→32768.
    const x: i32 = 65537;
    const y: i32 = 1;
    const d_i = x - y;
    const parent_i = y + @divFloor(d_i, 2);
    const parent_f16 = thruF16(parent_i);
    const d_f16 = thruF16(d_i);
    const y_back = parent_f16 - @divFloor(d_f16, 2);
    const x_back = y_back + d_f16;
    try std.testing.expect(x_back != x); // float butterfly already broken
    std.debug.print(
        "\n  [FINDING e] fp16 tensor lift: detail 2049→{d}; parent {d}→{d}, x {d}→{d} (low Q16 bit lost)\n",
        .{ rt, parent_i, parent_f16, x, x_back },
    );
}

// ════════════════════════════════════════════════════════════════════════════
//  (f) Unified-memory coherency / stale-read — output-buffer-contents independence.
//      Vectors: unified-memory-coherency-hazard, unified-memory-read-before-completion,
//               unified-memory-coherency-premature-read.
// ════════════════════════════════════════════════════════════════════════════

test "UNIFIED-MEMORY: reconstruct is independent of pre-existing (poisoned) output bytes" {
    const alloc = std.testing.allocator;
    // n=8, alternating ±extreme so leftover sentinel bytes are maximally distinct.
    // Use ±B = ±(2^29-1) — the MAX in-domain magnitude (so the first-level detail
    // d = B-(-B) = 2B = 2^30-2 is the largest legal detail, exactly fitting i32).
    const B: i32 = 536_870_911; // 2^29 - 1
    const leaves = [_]i32{
        B,    1, -1,
        -B,   2, -2,
        1,    3, -3,
        -1,   4, -4,
        7,    5, -5,
        -7,   6, -6,
        123,  7, -7,
        -123, 8, -8,
    };
    const n: i32 = 8;
    var root: [3]i32 = undefined;
    var off: [21]i32 = undefined;
    const scratch = try alloc.alloc(u8, 8 * 3 * @sizeOf(i32));
    defer alloc.free(scratch);
    // The pairs are (B, -B) → d = 2B = 2^30-2 < 2^31-1, in-domain ⇒ RC_OK.
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_haar_analyze(&leaves, n, &root, &off, scratch.ptr, scratch.len));

    // Reconstruct into a ZEROED buffer:
    var clean: [24]i32 = [_]i32{0} ** 24;
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_haar_reconstruct(&root, &off, n, &clean));
    try std.testing.expectEqualSlices(i32, &leaves, &clean);

    // Reconstruct into a POISONED buffer (0xDEADBEEF sentinel = -559038737):
    var poison: [24]i32 = [_]i32{-559038737} ** 24;
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_haar_reconstruct(&root, &off, n, &poison));
    // Byte-identical to the clean run → no hidden output-buffer read dependency.
    try std.testing.expectEqualSlices(i32, &clean, &poison);
    try std.testing.expectEqualSlices(i32, &leaves, &poison);

    // analyze: poison out_offsets first; assert root+offsets identical to clean.
    var off2: [21]i32 = [_]i32{-559038737} ** 21;
    var root2: [3]i32 = .{ -559038737, -559038737, -559038737 };
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_haar_analyze(&leaves, n, &root2, &off2, scratch.ptr, scratch.len));
    try std.testing.expectEqualSlices(i32, &root, &root2);
    try std.testing.expectEqualSlices(i32, &off, &off2);
}

// ════════════════════════════════════════════════════════════════════════════
//  (g) Core AI float NOT quarantined behind reenterQ16 — ULP/grid-straddle.
//      Vectors: coreai-float-bypassing-reenterq16, metal-int-round-float-requantize,
//               coreai-float-bypasses-q16-floor, fastmath-irrelevant-but-half-widen-port.
// ════════════════════════════════════════════════════════════════════════════

test "COREAI: two ULP-divergent floats produce DIFFERENT analyze bytes; a Q16-floor snap collapses them" {
    const alloc = std.testing.allocator;
    // Two devices' frozen-L net emit v and nextafter(v) straddling a Q16 cell.
    // Choose v so v*65536 sits just below K+0.5 (rounds to K) and v' just above
    // (rounds to K+1). Use a concrete pair around K=63570.
    const K: i32 = 63570;
    // device A float: K + 0.5 - tiny ; device B: K + 0.5 + tiny
    const vA: f64 = (@as(f64, @floatFromInt(K)) + 0.4999) / 65536.0;
    const vB: f64 = (@as(f64, @floatFromInt(K)) + 0.5001) / 65536.0;

    // BYPASS path: naive @round(v*65536) per device, fed straight into analyze.
    const leafA: i32 = @intFromFloat(@round(vA * 65536.0)); // K
    const leafB: i32 = @intFromFloat(@round(vB * 65536.0)); // K+1
    try std.testing.expect(leafA != leafB); // one ULP flipped the Q16 leaf

    const buildLeaves = struct {
        fn f(perturbed: i32) [24]i32 {
            // n=8, the perturbed L leaf adjacent to a sibling so analyze sees a
            // differing detail; a,b channels constant.
            return .{
                perturbed, 100, -100,
                63569,     100, -100,
                63571,     100, -100,
                63568,     100, -100,
                63572,     100, -100,
                63567,     100, -100,
                63573,     100, -100,
                63566,     100, -100,
            };
        }
    }.f;
    const la = buildLeaves(leafA);
    const lb = buildLeaves(leafB);

    var rootA: [3]i32 = undefined;
    var rootB: [3]i32 = undefined;
    var offA: [21]i32 = undefined;
    var offB: [21]i32 = undefined;
    const scratch = try alloc.alloc(u8, 8 * 3 * @sizeOf(i32));
    defer alloc.free(scratch);
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_haar_analyze(&la, 8, &rootA, &offA, scratch.ptr, scratch.len));
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_haar_analyze(&lb, 8, &rootB, &offB, scratch.ptr, scratch.len));
    // ASSERTION (1): the two devices' analyze output DIFFERS — the ABI alone does
    // NOT protect cross-device identity.
    const same_root = std.mem.eql(i32, &rootA, &rootB);
    const same_off = std.mem.eql(i32, &offA, &offB);
    try std.testing.expect(!(same_root and same_off));

    // GUARD path: route BOTH floats through a snap-to-Q16-grid floor (reenterQ16
    // modeled as floor(v*65536) — collapses both ULP-neighbours to ONE cell).
    const snapA: i32 = @intFromFloat(@floor(vA * 65536.0));
    const snapB: i32 = @intFromFloat(@floor(vB * 65536.0));
    try std.testing.expectEqual(snapA, snapB); // both land on K
    const sa = buildLeaves(snapA);
    const sb = buildLeaves(snapB);
    var rootSA: [3]i32 = undefined;
    var rootSB: [3]i32 = undefined;
    var offSA: [21]i32 = undefined;
    var offSB: [21]i32 = undefined;
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_haar_analyze(&sa, 8, &rootSA, &offSA, scratch.ptr, scratch.len));
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_haar_analyze(&sb, 8, &rootSB, &offSB, scratch.ptr, scratch.len));
    // ASSERTION (2): after the floor snap, the two devices are BYTE-IDENTICAL.
    try std.testing.expectEqualSlices(i32, &rootSA, &rootSB);
    try std.testing.expectEqualSlices(i32, &offSA, &offSB);
    // and the snapped leaves round-trip exactly:
    try std.testing.expect(try realRoundTrips(alloc, &sa, 8));
}

test "WIDEN: s4_widen_half_to_q16 golden table (exact f16→f32→×2^16, clamp ±2^30, no fp16 intermediate)" {
    // Pin the only float step feeding the lift. A fp16-intermediate/fast-math port
    // would diverge (0x7BFF=65504 → overflow-to-inf → 0 instead of 2^30).
    const cases = [_]struct { bits: u16, q16: i32 }{
        .{ .bits = 0x0001, .q16 = 0 }, // 2^-24 subnormal → 0
        .{ .bits = 0x03FF, .q16 = 4 }, // largest subnormal → 3.996→4
        .{ .bits = 0x0400, .q16 = 4 }, // smallest normal
        .{ .bits = 0x3801, .q16 = 32800 },
        .{ .bits = 0x3555, .q16 = 21840 },
        .{ .bits = 0xB801, .q16 = -32800 },
        .{ .bits = 0x7BFF, .q16 = 1073741824 }, // max finite half → clamp to 2^30
    };
    for (cases) |c| {
        var out: i32 = undefined;
        const bits = c.bits;
        try std.testing.expectEqual(kernels.RC_OK, kernels.s4_widen_half_to_q16(&bits, 1, &out));
        std.testing.expectEqual(c.q16, out) catch |e| {
            std.debug.print("\n  [WIDEN] bits=0x{X:0>4} expected q16={d} got {d}\n", .{ c.bits, c.q16, out });
            return e;
        };
    }
}
