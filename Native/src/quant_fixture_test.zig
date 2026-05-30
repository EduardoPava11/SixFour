//! Cross-language quantizer golden fixture test.
//!
//! `spec-fixtures` (Haskell, SixFour.Spec.QuantFixed) writes quant_golden.json:
//! a small frame of Q16 pixels, with the k maximin centroids + assignment the
//! fixed-point spec produces for each `lloyd_iters` case. This test runs
//! `s4_quantize_frame` on the SAME pixels and asserts BIT-EXACT agreement on
//! both the centroids and the assignment — the highest-risk kernel, pinned.
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

test "cross-language: s4_quantize_frame matches the Haskell maximin+Lloyd golden" {
    const alloc = std.testing.allocator;
    const dir = build_options.fixture_dir;

    const raw = readFileAlloc(alloc, dir, "quant_golden.json") catch |e| {
        if (e == error.SkipZigTest) {
            std.debug.print(
                "\n  [skip] quant_golden.json not in '{s}'; run `cd spec && cabal run spec-fixtures`\n",
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
    const kk: usize = @intCast(k);

    const pixels = try flattenTriples(alloc, root.get("pixels").?);
    defer alloc.free(pixels);

    const centroids = try alloc.alloc(i32, kk * 3);
    defer alloc.free(centroids);
    const indices = try alloc.alloc(u8, pp);
    defer alloc.free(indices);

    const scratch_bytes = pp * @sizeOf(i64) + 3 * kk * @sizeOf(i64) + kk * @sizeOf(i32);
    const scratch = try alloc.alloc(u8, scratch_bytes);
    defer alloc.free(scratch);

    const cases = root.get("cases").?.array;
    try std.testing.expect(cases.items.len > 0);
    for (cases.items) |case| {
        const obj = case.object;
        const lloyd_iters: i32 = @intCast(obj.get("lloyd_iters").?.integer);
        const exp_centroids = obj.get("centroids").?.array;
        const exp_indices = obj.get("indices").?.array;

        const rc = kernels.s4_quantize_frame(
            pixels.ptr,
            p,
            k,
            lloyd_iters,
            centroids.ptr,
            indices.ptr,
            scratch.ptr,
            scratch.len,
        );
        try std.testing.expectEqual(kernels.RC_OK, rc);

        // Centroids (k × 3 Q16) byte-exact.
        for (exp_centroids.items, 0..) |c, j| {
            try std.testing.expectEqual(@as(i32, @intCast(c.array.items[0].integer)), centroids[j * 3 + 0]);
            try std.testing.expectEqual(@as(i32, @intCast(c.array.items[1].integer)), centroids[j * 3 + 1]);
            try std.testing.expectEqual(@as(i32, @intCast(c.array.items[2].integer)), centroids[j * 3 + 2]);
        }
        // Assignment (P indices) byte-exact.
        for (exp_indices.items, 0..) |v, i| {
            try std.testing.expectEqual(@as(u8, @intCast(v.integer)), indices[i]);
        }
    }
}
