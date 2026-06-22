//! Adversarial invariant test — break-vector "metal4-simt-tensor-float-cores".
//!
//! The integer Haar/S-transform lift is a separable, fixed-matrix operation
//! (`rgbtLiftQuad` = four `sLift`s = a 2×2 / 4×4 matmul shape). That matmul shape
//! is exactly what tempts a future port onto Metal 4 SIMT cooperative-matrix /
//! tensor instructions for speed. The mission brief explicitly contemplates it:
//! "A reversible op may later be mapped onto Metal compute / SIMD-group / Metal 4
//! SIMT tensors."
//!
//! THE TRAP: Metal 4 tensor / cooperative-matrix cores are FLOAT math units
//! (fp16/bf16/fp8). Routing the Q16 integers through them coerces i32 → f16,
//! which has an 11-bit mantissa: integers are exact only up to 2^11 = 2048.
//! A real Q16 colour value (e.g. L* = 50 ⇒ 50<<16 = 3_276_800) is FAR above 2048,
//! so f16 silently rounds away its low ~12 bits. The lift's reversibility lives
//! ENTIRELY in those low bits: parent = y + floor((x−y)/2) and detail d = x−y
//! reconstruct x,y exactly ONLY because floor(d/2) keeps the dropped bit in d.
//! If x,y,d are rounded to f16 first, the dropped bit is gone for good.
//!
//! This test MODELS the tensor-core path in pure Zig (no Metal needed):
//! `analyzeViaTensorCore` runs the SAME lift arithmetic as `s4_haar_analyze` but
//! coerces every operand and result through `f16` (the cooperative-matrix element
//! type), then feeds the result through the EXACT integer inverse. The invariant
//! under attack:
//!
//!     reconstruct(analyzeViaTensorCore(x)) == x   -- MUST FAIL (fp16 is lossy here)
//!     reconstruct(analyze(x))              == x   -- holds (the correct i32 kernel)
//!
//! Severity LOW, guard "N/A — future port": today's Zig is pure i32 and correct.
//! The contract this test pins for any SIMT mapping: restrict it to INTEGER
//! SIMD-group ops (int32 lane math), NEVER the float tensor / cooperative-matrix
//! cores. An integer reversible lift has no business on a float matmul unit.

const std = @import("std");
const kernels = @import("kernels.zig");

/// Saturating f16 → i32. A non-finite f16 (the OTHER face of this break-vector:
/// a full-scale Q16 value like 50<<16 = 3_276_800 exceeds f16's max finite
/// 65_504 and becomes ±inf) clamps to the i32 extreme instead of panicking, so
/// the test asserts SILENT byte-loss rather than crashing. For finite values it
/// is an ordinary truncating cast.
fn satI32(v: f16) i32 {
    if (std.math.isNan(v)) return 0;
    if (v >= @as(f16, @floatFromInt(std.math.maxInt(i32)))) return std.math.maxInt(i32);
    if (v <= @as(f16, @floatFromInt(std.math.minInt(i32)))) return std.math.minInt(i32);
    return @intFromFloat(v);
}

/// S-transform forward, identical arithmetic to `s4_haar_analyze`'s inner cell,
/// but with every integer operand coerced through `f16` — the element type a
/// Metal 4 cooperative-matrix / tensor instruction would use. `@floatFromInt`
/// rounds to nearest representable f16; `@intFromFloat` truncates back. For any
/// |value| > 2048 this silently drops low bits, so the detail d and the parent
/// no longer carry the exact bit floor(d/2) discards — reversibility is lost.
fn analyzeViaTensorCore(
    leaves: []const i32,
    n: usize,
    out_root: *[3]i32,
    out_offsets: []i32, // (n-1)*3
    work: []i32, // n*3 scratch
) void {
    for (0..n * 3) |i| work[i] = leaves[i];

    var cur: usize = n;
    while (cur > 1) {
        const half = cur / 2;
        const out_start = half - 1;
        for (0..half) |i| {
            for (0..3) |c| {
                // Operands enter the "tensor core" as f16.
                const xf: f16 = @floatFromInt(work[(2 * i) * 3 + c]);
                const yf: f16 = @floatFromInt(work[(2 * i + 1) * 3 + c]);
                const df: f16 = xf - yf; // d = x - y, in f16
                // floor(d/2): emulate the integer lift on the float unit, result back to f16.
                const halfd: f16 = @floor(df / 2.0);
                const parentf: f16 = yf + halfd;
                // Results written back to the i32 buffer (what we read out of the
                // shared buffer after the tensor dispatch). Saturating conversion so a
                // non-finite f16 records as a clamped sentinel rather than panicking —
                // the SILENT low-bit loss, not a crash, is the danger we are exposing.
                work[i * 3 + c] = satI32(parentf);
                out_offsets[(out_start + i) * 3 + c] = satI32(df);
            }
        }
        cur = half;
    }
    out_root.* = .{ work[0], work[1], work[2] };
}

test "tensor-float: fp16 cooperative-matrix lift breaks reconstruct∘analyze (port must use int SIMD-group only)" {
    const alloc = std.testing.allocator;

    // n = 2 leaves (depth 1) — the SMALLEST case; one sLift, no cascade needed.
    // The break is in a single lift, so depth-1 is the cleanest witness.
    const n: usize = 2;

    // Adversarial witness: chosen to sit in the WORST silent-loss band — finite in
    // f16 (|v| < 65_504, so no inf/NaN, no panic) but above the exact-integer
    // ceiling 2^11 = 2048, where f16's step size is ≥ 4 and odd low bits vanish on
    // the round-trip through the tensor core. Each channel carries an odd low bit
    // (+1 / +3 / +5 / +7) that floor(d/2) round-trips on in i32 but f16 destroys.
    // (A full-scale Q16 value like 50<<16 = 3_276_800 also breaks this — it exceeds
    //  f16's max finite and becomes inf; that face is handled by satI32. We pick the
    //  finite band here so the assertion is SILENT loss, the dangerous case.)
    const leaves = [_]i32{
        9001, 4097, 3001, // leaf0  (all > 2048; f16 step ≥ 4 here)
        4099, 8195, 6005, // leaf1  (odd low bits +1/+3/+5 do not survive f16)
    };

    // --- correct i32 kernel: round-trips exactly (control) ---
    var good_root: [3]i32 = undefined;
    var good_off: [(n - 1) * 3]i32 = undefined;
    const scratch = try alloc.alloc(u8, n * 3 * @sizeOf(i32));
    defer alloc.free(scratch);
    const rc_a = kernels.s4_haar_analyze(&leaves, @intCast(n), &good_root, &good_off, scratch.ptr, scratch.len);
    try std.testing.expectEqual(kernels.RC_OK, rc_a);

    var good_leaves: [n * 3]i32 = undefined;
    const rc_r = kernels.s4_haar_reconstruct(&good_root, &good_off, @intCast(n), &good_leaves);
    try std.testing.expectEqual(kernels.RC_OK, rc_r);
    try std.testing.expectEqualSlices(i32, &leaves, &good_leaves); // INVARIANT holds for i32 kernel

    // --- "tensor core" port (fp16 cooperative-matrix): feed through the EXACT integer inverse ---
    var work: [n * 3]i32 = undefined;
    var bad_root: [3]i32 = undefined;
    var bad_off: [(n - 1) * 3]i32 = undefined;
    analyzeViaTensorCore(&leaves, n, &bad_root, &bad_off, &work);

    var bad_leaves: [n * 3]i32 = undefined;
    const rc_br = kernels.s4_haar_reconstruct(&bad_root, &bad_off, @intCast(n), &bad_leaves);
    try std.testing.expectEqual(kernels.RC_OK, rc_br);

    // THE ASSERTION: the fp16 tensor-core lift does NOT round-trip — reconstruct∘(fp16 analyze) ≠ id.
    // If a future port offloads this integer lift to Metal 4 tensor / cooperative-matrix
    // cores, this is the silent byte-loss it ships.
    const round_trips = std.mem.eql(i32, &leaves, &bad_leaves);
    try std.testing.expect(!round_trips);

    // Document the witnessed divergence for the failure report.
    if (!round_trips) {
        std.debug.print(
            "\n  [witness] fp16 tensor lift loses low bits: leaf0.L correct={d} fp16-reconstructed={d} (Δ={d})\n",
            .{ leaves[0], bad_leaves[0], leaves[0] - bad_leaves[0] },
        );
    }
}
