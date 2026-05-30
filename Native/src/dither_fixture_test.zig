//! Cross-language spatial-dither golden fixture test.
//!
//! `spec-fixtures` (Haskell, SixFour.Spec.SpatialDither) writes dither_golden.json:
//! a small frame (Q16 centroids + pixels + a threshold slice) with the per-pixel
//! indices the fixed-point spec produces for each dither mode (FS raster, FS
//! serpentine, Atkinson, blue-noise). This test runs `s4_dither_frame` on the
//! SAME inputs for each case and asserts BIT-EXACT index agreement.
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

test "cross-language: s4_dither_frame matches the Haskell spatial-dither golden" {
    const alloc = std.testing.allocator;
    const dir = build_options.fixture_dir;

    const raw = readFileAlloc(alloc, dir, "dither_golden.json") catch |e| {
        if (e == error.SkipZigTest) {
            std.debug.print(
                "\n  [skip] dither_golden.json not in '{s}'; run `cd spec && cabal run spec-fixtures`\n",
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
    const k: i32 = @intCast(root.get("k").?.integer);
    const p: i32 = side * side;
    const pp: usize = @intCast(p);

    const centroids = try flattenTriples(alloc, root.get("centroids").?);
    defer alloc.free(centroids);
    const pixels = try flattenTriples(alloc, root.get("pixels").?);
    defer alloc.free(pixels);

    const thr_arr = root.get("thresholds").?.array;
    const thresholds = try alloc.alloc(u8, pp);
    defer alloc.free(thresholds);
    for (thr_arr.items, 0..) |v, i| thresholds[i] = @intCast(v.integer);

    const out = try alloc.alloc(u8, pp);
    defer alloc.free(out);
    const scratch_bytes = pp * 3 * @sizeOf(i32);
    const scratch = try alloc.alloc(u8, scratch_bytes);
    defer alloc.free(scratch);

    const cases = root.get("cases").?.array;
    try std.testing.expect(cases.items.len > 0);
    for (cases.items) |case| {
        const obj = case.object;
        const mode: i32 = @intCast(obj.get("mode").?.integer);
        const serp: i32 = @intCast(obj.get("serpentine").?.integer);
        const expect = obj.get("indices").?.array;

        const rc = kernels.s4_dither_frame(
            pixels.ptr,
            centroids.ptr,
            p,
            k,
            mode,
            serp,
            thresholds.ptr,
            out.ptr,
            scratch.ptr,
            scratch.len,
        );
        try std.testing.expectEqual(kernels.RC_OK, rc);
        for (expect.items, 0..) |v, i| {
            try std.testing.expectEqual(@as(u8, @intCast(v.integer)), out[i]);
        }
    }
}
