//! Cross-language V2.1 SOFT-SPLAT histogram golden fixture test (the sub-LSB construction).
//!
//! `spec-fixtures` (Haskell, SixFour.Spec.V21Field.accumulateHistSoft) writes v21_soft_hist_golden.json:
//! a high-precision fine grid (positions hi in 0 .. (n_levels-1)*w), the decimation factors, the
//! sub-level budget w, and the per-coarse-voxel per-channel SOFT counts (each sample's mass w split
//! across two adjacent levels). This test runs `s4_v21_accumulate_hist_soft` on the SAME fine grid and
//! asserts BIT-EXACT agreement, then cross-checks two structural theorems on the golden:
//!   1. MASS: the total of the soft histogram == (fine-sample count) * w (lawSoftHistTotalPreserved).
//!   2. CENTROID: per (voxel,channel), sum(level * count) == sum of the cell's hi values (the
//!      mass-weighted mean reconstructs the high-precision positions exactly, lawSoftSplatCentroidExact),
//!      the proof that the discarded 10-bit bits are recoverable from the constructed field.
//!
//! Skip-if-absent (build with `cd spec && cabal run spec-fixtures`).

const std = @import("std");
const kernels = @import("kernels.zig");
const build_options = @import("build_options");

fn readFileAlloc(alloc: std.mem.Allocator, dir: []const u8, name: []const u8) ![]u8 {
    const io = std.testing.io;
    const path = try std.fs.path.join(alloc, &.{ dir, name });
    defer alloc.free(path);
    return std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .unlimited) catch
        return error.SkipZigTest;
}

test "cross-language: s4_v21_accumulate_hist_soft matches the Haskell golden + mass + exact centroid" {
    const alloc = std.testing.allocator;
    const dir = build_options.fixture_dir;

    const raw = readFileAlloc(alloc, dir, "v21_soft_hist_golden.json") catch |e| {
        if (e == error.SkipZigTest) {
            std.debug.print(
                "\n  [skip] v21_soft_hist_golden.json not in '{s}'; run `cd spec && cabal run spec-fixtures`\n",
                .{dir},
            );
            return error.SkipZigTest;
        }
        return e;
    };
    defer alloc.free(raw);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, raw, .{});
    defer parsed.deinit();
    const root = parsed.value.object;

    const fx: i32 = @intCast(root.get("fx").?.integer);
    const fy: i32 = @intCast(root.get("fy").?.integer);
    const ft: i32 = @intCast(root.get("ft").?.integer);
    const dx: i32 = @intCast(root.get("dx").?.integer);
    const dy: i32 = @intCast(root.get("dy").?.integer);
    const dt: i32 = @intCast(root.get("dt").?.integer);
    const n_levels: i32 = @intCast(root.get("n_levels").?.integer);
    const w: i32 = @intCast(root.get("w").?.integer);
    const fine_json = root.get("fine").?.array;
    const counts_json = root.get("counts").?.array;

    // High-precision fine grid as i32 (positions hi, may exceed 255).
    const fine = try alloc.alloc(i32, fine_json.items.len);
    defer alloc.free(fine);
    for (fine_json.items, 0..) |v, i| fine[i] = @intCast(v.integer);

    const out_counts = try alloc.alloc(i32, counts_json.items.len);
    defer alloc.free(out_counts);

    const rc = kernels.s4_v21_accumulate_hist_soft(fine.ptr, fx, fy, ft, dx, dy, dt, n_levels, w, out_counts.ptr);
    try std.testing.expectEqual(kernels.RC_OK, rc);

    // (1) bit-exact vs the Haskell golden.
    for (counts_json.items, 0..) |want, i| {
        try std.testing.expectEqual(@as(i32, @intCast(want.integer)), out_counts[i]);
    }

    // (2) MASS: total == (fine-sample count) * w.
    var total: i64 = 0;
    for (out_counts) |c| total += @as(i64, c);
    try std.testing.expectEqual(@as(i64, @intCast(fine.len)) * @as(i64, w), total);

    // (3) EXACT CENTROID per (voxel, channel): sum(level*count) == sum of that cell's hi values.
    // The kernel groups fine samples into coarse voxels by floor-division; recompute the cell each
    // fine sample lands in, accumulate its hi into an expected first-moment per cell, and compare to
    // the count-weighted level sum. Equality is lawSoftSplatCentroidExact aggregated over the cell.
    const nl: usize = @intCast(n_levels);
    const ncells: usize = counts_json.items.len / nl; // (ct*cy*cx*3) cells
    const moment_from_hi = try alloc.alloc(i64, ncells);
    defer alloc.free(moment_from_hi);
    for (moment_from_hi) |*m| m.* = 0;

    const ufx: usize = @intCast(fx);
    const ufy: usize = @intCast(fy);
    const uft: usize = @intCast(ft);
    const udx: usize = @intCast(dx);
    const udy: usize = @intCast(dy);
    const udt: usize = @intCast(dt);
    const cx: usize = ufx / udx;
    const cy: usize = ufy / udy;
    var fti: usize = 0;
    while (fti < uft) : (fti += 1) {
        var fyi: usize = 0;
        while (fyi < ufy) : (fyi += 1) {
            var fxi: usize = 0;
            while (fxi < ufx) : (fxi += 1) {
                const cvi = ((fti / udt) * cy + (fyi / udy)) * cx + (fxi / udx);
                var ch: usize = 0;
                while (ch < 3) : (ch += 1) {
                    const fine_idx = ((fti * ufy + fyi) * ufx + fxi) * 3 + ch;
                    moment_from_hi[cvi * 3 + ch] += @as(i64, fine[fine_idx]);
                }
            }
        }
    }

    var cell: usize = 0;
    while (cell < ncells) : (cell += 1) {
        var moment_from_counts: i64 = 0;
        var lvl: usize = 0;
        while (lvl < nl) : (lvl += 1) {
            moment_from_counts += @as(i64, @intCast(lvl)) * @as(i64, out_counts[cell * nl + lvl]);
        }
        try std.testing.expectEqual(moment_from_hi[cell], moment_from_counts);
    }
}
