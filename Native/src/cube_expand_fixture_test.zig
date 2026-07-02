//! Cross-language DEVICE-layout volume-expand golden fixture test.
//!
//! `spec-fixtures` (Haskell, SixFour.Spec.SelfSimilarReconstruct.expandRungVolume — the
//! export rung's source of truth) writes cube_expand_golden.json: a side-4 cube plus
//! per-voxel committed detail bands, expanded one octant rung BOTH ways — the
//! zero-detail floor and the gene arm. This test runs `s4_cube_expand_rung` on the
//! SAME inputs and asserts BIT-EXACT agreement on both arms, proving the Zig volume
//! oracle (over the gated s4_octant_unlift) == the Haskell spec on one fixture.
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

fn intArray(alloc: std.mem.Allocator, node: std.json.Value) ![]i32 {
    const items = node.array.items;
    const out = try alloc.alloc(i32, items.len);
    for (items, 0..) |v, i| out[i] = @intCast(v.integer);
    return out;
}

test "cross-language: s4_cube_expand_rung matches the Haskell volume-expand golden (floor + gene arms)" {
    const alloc = std.testing.allocator;
    const dir = build_options.fixture_dir;

    const raw = readFileAlloc(alloc, dir, "cube_expand_golden.json") catch |e| {
        if (e == error.SkipZigTest) {
            std.debug.print(
                "\n  [skip] cube_expand_golden.json not in '{s}'; run `cd spec && cabal run spec-fixtures`\n",
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

    const side: i32 = @intCast(root.get("side").?.integer);
    const vol = try intArray(alloc, root.get("vol").?);
    defer alloc.free(vol);
    const details = try intArray(alloc, root.get("details").?);
    defer alloc.free(details);
    const expected_floor = try intArray(alloc, root.get("expected_floor").?);
    defer alloc.free(expected_floor);
    const expected_gene = try intArray(alloc, root.get("expected_gene").?);
    defer alloc.free(expected_gene);

    const s: usize = @intCast(side);
    try std.testing.expectEqual(s * s * s, vol.len);
    try std.testing.expectEqual(vol.len * 7, details.len);
    const fine_n = 8 * s * s * s;
    try std.testing.expectEqual(fine_n, expected_floor.len);
    try std.testing.expectEqual(fine_n, expected_gene.len);

    const out = try alloc.alloc(i32, fine_n);
    defer alloc.free(out);

    // Arm 1: the zero-detail deterministic floor (details == null).
    try std.testing.expectEqual(
        @as(i32, 0),
        kernels.s4_cube_expand_rung(vol.ptr, side, null, out.ptr),
    );
    try std.testing.expectEqualSlices(i32, expected_floor, out);

    // Arm 2: the gene arm (committed detail bands supplied).
    try std.testing.expectEqual(
        @as(i32, 0),
        kernels.s4_cube_expand_rung(vol.ptr, side, details.ptr, out.ptr),
    );
    try std.testing.expectEqualSlices(i32, expected_gene, out);

    // The two arms genuinely differ (the gene invents; the fixture's bands are nonzero).
    try std.testing.expect(!std.mem.eql(i32, expected_floor, expected_gene));
}
