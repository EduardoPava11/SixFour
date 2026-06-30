//! Cross-language V2.1 collapse golden fixture test.
//!
//! `spec-fixtures` (Haskell, SixFour.Spec.V21Field.collapseQ16) writes
//! v21_collapse_golden.json: p*3 Q16 energy curves of n_levels each, plus the
//! collapsed level (argmin energy, lowest-index tie-break) of each. This test runs
//! `s4_v21_collapse` on the SAME curves and asserts BIT-EXACT agreement on the
//! collapsed bytes, proving the Zig collapse kernel == the Haskell V2.1 spec on one fixture.
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

test "cross-language: s4_v21_collapse matches the Haskell V2.1 collapse golden" {
    const alloc = std.testing.allocator;
    const dir = build_options.fixture_dir;

    const raw = readFileAlloc(alloc, dir, "v21_collapse_golden.json") catch |e| {
        if (e == error.SkipZigTest) {
            std.debug.print(
                "\n  [skip] v21_collapse_golden.json not in '{s}'; run `cd spec && cabal run spec-fixtures`\n",
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

    const p: i32 = @intCast(root.get("p").?.integer);
    const n_levels: i32 = @intCast(root.get("n_levels").?.integer);
    const curves_json = root.get("curves").?.array;
    const collapsed_json = root.get("collapsed").?.array;

    const total: usize = @intCast(p * 3);
    const nl: usize = @intCast(n_levels);

    // Flatten the p*3 curves into [total*nl] Q16 energies, pixel-major.
    const curves = try alloc.alloc(i32, total * nl);
    defer alloc.free(curves);
    for (curves_json.items, 0..) |curve, ch| {
        for (curve.array.items, 0..) |e, l| {
            curves[ch * nl + l] = @intCast(e.integer);
        }
    }

    const out = try alloc.alloc(u8, total);
    defer alloc.free(out);

    const rc = kernels.s4_v21_collapse(curves.ptr, p, n_levels, out.ptr);
    try std.testing.expectEqual(kernels.RC_OK, rc);

    // Bit-exact: every collapsed level the kernel produces equals the spec's.
    for (collapsed_json.items, 0..) |want, ch| {
        try std.testing.expectEqual(@as(u8, @intCast(want.integer)), out[ch]);
    }
}
