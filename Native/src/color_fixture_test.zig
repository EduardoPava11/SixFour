//! Cross-language color golden fixture test.
//!
//! `spec-fixtures` (Haskell, SixFour.Spec.ColorFixed) writes color_golden.json:
//! a set of Q16 linear-sRGB inputs with the Q16 OKLab the fixed-point spec
//! computes. This test runs `s4_linear_to_oklab_q16` on the SAME inputs and
//! asserts every output triple is BIT-EXACTLY the spec's — proving the Zig
//! integer port and the Haskell source of truth agree, which is what makes the
//! color stage deterministic across devices.
//!
//! Skip-if-absent (build the golden with `cd spec && cabal run spec-fixtures`).

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

fn i32at(arr: std.json.Value, idx: usize) i32 {
    return @intCast(arr.array.items[idx].integer);
}

test "cross-language: Q16 linear→OKLab matches the Haskell color golden byte-exactly" {
    const alloc = std.testing.allocator;
    const dir = build_options.fixture_dir;

    const raw = readFileAlloc(alloc, dir, "color_golden.json") catch |e| {
        if (e == error.SkipZigTest) {
            std.debug.print(
                "\n  [skip] color_golden.json not in '{s}'; run `cd spec && cabal run spec-fixtures`\n",
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

    // The fixture must agree on the Q16 unit, else the two sides scale differently.
    try std.testing.expectEqual(@as(i64, kernels.Q16_ONE), root.get("q16_one").?.integer);

    // Forward: linear Q16 → OKLab Q16.
    const fwd = root.get("linear_to_oklab").?.array;
    try std.testing.expect(fwd.items.len > 0);
    for (fwd.items) |case| {
        const obj = case.object;
        const lin = obj.get("lin").?;
        const expect = obj.get("oklab").?;

        var in = [3]i32{ i32at(lin, 0), i32at(lin, 1), i32at(lin, 2) };
        var out = [3]i32{ 0, 0, 0 };
        try std.testing.expectEqual(kernels.RC_OK, kernels.s4_linear_to_oklab_q16(&in, 1, &out));

        try std.testing.expectEqual(i32at(expect, 0), out[0]);
        try std.testing.expectEqual(i32at(expect, 1), out[1]);
        try std.testing.expectEqual(i32at(expect, 2), out[2]);
    }

    // Inverse: OKLab Q16 → sRGB8 (exercises the embedded gamma LUT).
    const inv = root.get("oklab_to_srgb8").?.array;
    try std.testing.expect(inv.items.len > 0);
    for (inv.items) |case| {
        const obj = case.object;
        const oklab = obj.get("oklab").?;
        const expect = obj.get("rgb").?;

        var in = [3]i32{ i32at(oklab, 0), i32at(oklab, 1), i32at(oklab, 2) };
        var rgb = [3]u8{ 0, 0, 0 };
        try std.testing.expectEqual(kernels.RC_OK, kernels.s4_palette_oklab_to_srgb8(&in, 1, &rgb, null, 0));

        try std.testing.expectEqual(@as(u8, @intCast(i32at(expect, 0))), rgb[0]);
        try std.testing.expectEqual(@as(u8, @intCast(i32at(expect, 1))), rgb[1]);
        try std.testing.expectEqual(@as(u8, @intCast(i32at(expect, 2))), rgb[2]);
    }
}
