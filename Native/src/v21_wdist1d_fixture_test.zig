//! Cross-language V2.1 1-D Wasserstein-1 palette-metric golden fixture test.
//!
//! `spec-fixtures` (Haskell, SixFour.Spec.V21Field.paletteW1) writes v21_wdist1d_golden.json: two
//! k-slot palettes, the value alphabet n_levels, their W1 (L1 of the per-channel value CDFs), and the
//! drift/jump discriminator scalars. This test runs `s4_v21_wdist1d` and asserts:
//!   1. bit-exact agreement on the palette W1 scalar;
//!   2. SYMMETRY (W1(a,b) == W1(b,a));
//!   3. the DISCRIMINATOR (W1 charges ground distance, unlike total variation): a 1-level drift costs
//!      strictly less than a far jump of equal mass, matching the spec's golden drift_w1 / jump_w1.
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

fn readU8Array(alloc: std.mem.Allocator, arr: std.json.Array) ![]u8 {
    const out = try alloc.alloc(u8, arr.items.len);
    for (arr.items, 0..) |v, i| out[i] = @intCast(v.integer);
    return out;
}

test "cross-language: s4_v21_wdist1d matches the Haskell W1 golden + symmetry + charges distance" {
    const alloc = std.testing.allocator;
    const dir = build_options.fixture_dir;

    const raw = readFileAlloc(alloc, dir, "v21_wdist1d_golden.json") catch |e| {
        if (e == error.SkipZigTest) {
            std.debug.print(
                "\n  [skip] v21_wdist1d_golden.json not in '{s}'; run `cd spec && cabal run spec-fixtures`\n",
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

    const k: i32 = @intCast(root.get("k").?.integer);
    const n_levels: i32 = @intCast(root.get("n_levels").?.integer);
    const want: i32 = @intCast(root.get("w1").?.integer);
    const want_drift: i32 = @intCast(root.get("drift_w1").?.integer);
    const want_jump: i32 = @intCast(root.get("jump_w1").?.integer);

    const pal1 = try readU8Array(alloc, root.get("pal1").?.array);
    defer alloc.free(pal1);
    const pal2 = try readU8Array(alloc, root.get("pal2").?.array);
    defer alloc.free(pal2);

    // (1) the scalar W1 is bit-exact.
    var wd: i32 = -1;
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_v21_wdist1d(pal1.ptr, pal2.ptr, k, n_levels, &wd));
    try std.testing.expectEqual(want, wd);

    // (2) symmetry.
    var wd_swapped: i32 = -1;
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_v21_wdist1d(pal2.ptr, pal1.ptr, k, n_levels, &wd_swapped));
    try std.testing.expectEqual(want, wd_swapped);

    // (3) the discriminator: single-slot palettes at level 0, level 1 (drift), and the top level (jump).
    const top: u8 = @intCast(n_levels - 1);
    const p0 = [_]u8{ 0, 0, 0 };
    const pNear = [_]u8{ 1, 0, 0 };
    const pFar = [_]u8{ top, 0, 0 };
    var wd_drift: i32 = -1;
    var wd_jump: i32 = -1;
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_v21_wdist1d(&p0, &pNear, 1, n_levels, &wd_drift));
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_v21_wdist1d(&p0, &pFar, 1, n_levels, &wd_jump));
    try std.testing.expectEqual(want_drift, wd_drift);
    try std.testing.expectEqual(want_jump, wd_jump);
    try std.testing.expect(wd_drift < wd_jump); // W1 charges the ground distance (TV would tie them)
}
