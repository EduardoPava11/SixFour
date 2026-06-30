//! Cross-language V2.1 octant-lift-driver golden fixture test.
//!
//! `spec-fixtures` (Haskell, SixFour.Spec.V21Field.liftOctList over the OctreeCell edge) writes
//! v21_octant_golden.json: 8 octant cells' Q16 curves of n_levels each, plus the coarse curve and
//! the 7 residual curves the per-level lift produces. This test runs `s4_v21_octant_lift_curve`
//! on the SAME cells and asserts BIT-EXACT agreement, proving the Zig per-level driver (over the
//! gated s4_octant_lift) == the Haskell V2.1 spec on one fixture.
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

test "cross-language: s4_v21_octant_lift_curve matches the Haskell V2.1 octant golden" {
    const alloc = std.testing.allocator;
    const dir = build_options.fixture_dir;

    const raw = readFileAlloc(alloc, dir, "v21_octant_golden.json") catch |e| {
        if (e == error.SkipZigTest) {
            std.debug.print(
                "\n  [skip] v21_octant_golden.json not in '{s}'; run `cd spec && cabal run spec-fixtures`\n",
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

    const n_levels: i32 = @intCast(root.get("n_levels").?.integer);
    const cells_json = root.get("cells").?.array;
    const coarse_json = root.get("coarse").?.array;
    const residuals_json = root.get("residuals").?.array;

    const nl: usize = @intCast(n_levels);

    // Flatten the 8 cell curves into [8*nl], cell-major (cell w, level l at w*nl + l).
    const cells = try alloc.alloc(i32, 8 * nl);
    defer alloc.free(cells);
    for (cells_json.items, 0..) |cell, w| {
        for (cell.array.items, 0..) |v, l| {
            cells[w * nl + l] = @intCast(v.integer);
        }
    }

    const out_coarse = try alloc.alloc(i32, nl);
    defer alloc.free(out_coarse);
    const out_residuals = try alloc.alloc(i32, 7 * nl);
    defer alloc.free(out_residuals);

    const rc = kernels.s4_v21_octant_lift_curve(cells.ptr, n_levels, out_coarse.ptr, out_residuals.ptr);
    try std.testing.expectEqual(kernels.RC_OK, rc);

    // Coarse curve bit-exact.
    for (coarse_json.items, 0..) |want, l| {
        try std.testing.expectEqual(@as(i32, @intCast(want.integer)), out_coarse[l]);
    }
    // All 7 residual curves bit-exact (residual-major: residual r, level l at r*nl + l).
    for (residuals_json.items, 0..) |res, r| {
        for (res.array.items, 0..) |want, l| {
            try std.testing.expectEqual(@as(i32, @intCast(want.integer)), out_residuals[r * nl + l]);
        }
    }
}
