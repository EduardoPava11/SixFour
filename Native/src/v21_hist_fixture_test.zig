//! Cross-language V2.1 histogram-accumulation golden fixture test (make_bins half 1).
//!
//! `spec-fixtures` (Haskell, SixFour.Spec.V21Field.accumulateHist) writes v21_hist_golden.json:
//! a fine grid (fx,fy,ft,3) of small values, the decimation factors, and the per-coarse-voxel
//! per-channel value counts. This test runs `s4_v21_accumulate_hist` on the SAME fine grid and
//! asserts BIT-EXACT agreement, proving the Zig box-decimation histogram == the Haskell V2.1 spec.
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

test "cross-language: s4_v21_accumulate_hist matches the Haskell make_bins histogram golden" {
    const alloc = std.testing.allocator;
    const dir = build_options.fixture_dir;

    const raw = readFileAlloc(alloc, dir, "v21_hist_golden.json") catch |e| {
        if (e == error.SkipZigTest) {
            std.debug.print(
                "\n  [skip] v21_hist_golden.json not in '{s}'; run `cd spec && cabal run spec-fixtures`\n",
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
    const fine_json = root.get("fine").?.array;
    const counts_json = root.get("counts").?.array;

    // Fine grid as u8.
    const fine = try alloc.alloc(u8, fine_json.items.len);
    defer alloc.free(fine);
    for (fine_json.items, 0..) |v, i| fine[i] = @intCast(v.integer);

    const out_counts = try alloc.alloc(i32, counts_json.items.len);
    defer alloc.free(out_counts);

    const rc = kernels.s4_v21_accumulate_hist(fine.ptr, fx, fy, ft, dx, dy, dt, n_levels, out_counts.ptr);
    try std.testing.expectEqual(kernels.RC_OK, rc);

    for (counts_json.items, 0..) |want, i| {
        try std.testing.expectEqual(@as(i32, @intCast(want.integer)), out_counts[i]);
    }
}
