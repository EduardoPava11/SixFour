//! Cross-language RGBT-4D golden fixture test — the Metal/Zig alignment gate.
//!
//! `spec-fixtures` (Haskell, SixFour.Spec.RGBTLift + CubeLadder) writes
//! rgbt4d_golden.json. This test runs the Zig kernels (`s4_rgbt_lift_quad`,
//! `s4_cube_lift_level`) on the SAME inputs and asserts BIT-EXACT agreement, then
//! the inverses and asserts an exact round-trip (the lifting is losslessly
//! invertible — no tolerance). The Metal kernel must verify against the SAME spec
//! golden; that — not a Zig↔Metal comparison — is what keeps the two ports aligned.
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

fn readInts(alloc: std.mem.Allocator, arr: std.json.Value) ![]i32 {
    const out = try alloc.alloc(i32, arr.array.items.len);
    for (arr.array.items, 0..) |v, i| out[i] = @intCast(v.integer);
    return out;
}

fn flattenTriples(alloc: std.mem.Allocator, arr: std.json.Value) ![]i32 {
    const n = arr.array.items.len;
    const out = try alloc.alloc(i32, n * 3);
    for (arr.array.items, 0..) |t, i| {
        out[i * 3 + 0] = @intCast(t.array.items[0].integer);
        out[i * 3 + 1] = @intCast(t.array.items[1].integer);
        out[i * 3 + 2] = @intCast(t.array.items[2].integer);
    }
    return out;
}

test "cross-language: s4_rgbt_lift_quad / s4_cube_lift_level match the Haskell RGBT-4D golden" {
    const alloc = std.testing.allocator;
    const dir = build_options.fixture_dir;

    const raw = readFileAlloc(alloc, dir, "rgbt4d_golden.json") catch |e| {
        if (e == error.SkipZigTest) {
            std.debug.print(
                "\n  [skip] rgbt4d_golden.json not in '{s}'; run `cd spec && cabal run spec-fixtures`\n",
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
    const grid = try readInts(alloc, root.get("grid").?);
    defer alloc.free(grid);
    const lift_in = try readInts(alloc, root.get("lift_in").?);
    defer alloc.free(lift_in);
    const lift_out = try readInts(alloc, root.get("lift_out").?);
    defer alloc.free(lift_out);
    const level_coarse = try readInts(alloc, root.get("level_coarse").?);
    defer alloc.free(level_coarse);
    const level_details = try flattenTriples(alloc, root.get("level_details").?);
    defer alloc.free(level_details);

    // quad lift byte-exact + exact round-trip.
    var q4: [4]i32 = undefined;
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_rgbt_lift_quad(lift_in.ptr, &q4));
    try std.testing.expectEqualSlices(i32, lift_out, &q4);
    var back: [4]i32 = undefined;
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_rgbt_unlift_quad(&q4, &back));
    try std.testing.expectEqualSlices(i32, lift_in, &back);

    // level lift: coarse plane + detail planes byte-exact (pins the tiling layout).
    const h: usize = @intCast(@divFloor(side, 2));
    const coarse = try alloc.alloc(i32, h * h);
    defer alloc.free(coarse);
    const details = try alloc.alloc(i32, h * h * 3);
    defer alloc.free(details);
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_cube_lift_level(side, grid.ptr, coarse.ptr, details.ptr));
    try std.testing.expectEqualSlices(i32, level_coarse, coarse);
    try std.testing.expectEqualSlices(i32, level_details, details);

    // level reconstruct: the grid comes back EXACTLY (lossless within capture).
    const got_grid = try alloc.alloc(i32, grid.len);
    defer alloc.free(got_grid);
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_cube_unlift_level(@intCast(h), coarse.ptr, details.ptr, got_grid.ptr));
    try std.testing.expectEqualSlices(i32, grid, got_grid);
}
