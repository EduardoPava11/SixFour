//! Cross-language significance split-fill golden fixture test.
//!
//! `spec-fixtures` (Haskell, SixFour.Spec.SignificanceFixed) writes
//! significance_golden.json: Q16 centroids + pixels + an imbalanced initial
//! index assignment, with the rebalanced indices and per-slot Q16 cell stats the
//! fixed-point spec computes. This test runs `s4_significance_fill` on the SAME
//! inputs and asserts the rebalanced indices AND the cell stats are BIT-EXACTLY
//! the spec's — pinning the Zig rescue + cell math to the source of truth.
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

// Flatten a JSON array of [x,y,z] triples into a contiguous i32 buffer.
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

test "cross-language: s4_significance_fill matches the Haskell rescue + cells golden" {
    const alloc = std.testing.allocator;
    const dir = build_options.fixture_dir;

    const raw = readFileAlloc(alloc, dir, "significance_golden.json") catch |e| {
        if (e == error.SkipZigTest) {
            std.debug.print(
                "\n  [skip] significance_golden.json not in '{s}'; run `cd spec && cabal run spec-fixtures`\n",
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
    const p: i32 = @intCast(root.get("p").?.integer);
    const min_pop: i32 = @intCast(root.get("min_population").?.integer);

    const centroids = try flattenTriples(alloc, root.get("centroids").?);
    defer alloc.free(centroids);
    const pixels = try flattenTriples(alloc, root.get("pixels").?);
    defer alloc.free(pixels);

    const in_arr = root.get("indices_in").?.array;
    const out_arr = root.get("indices_out").?.array;
    const pp: usize = @intCast(p);
    const kk: usize = @intCast(k);

    const indices = try alloc.alloc(u8, pp);
    defer alloc.free(indices);
    for (in_arr.items, 0..) |v, i| indices[i] = @intCast(v.integer);

    const cells = try alloc.alloc(i32, kk * 7);
    defer alloc.free(cells);

    const rc = kernels.s4_significance_fill(
        pixels.ptr,
        centroids.ptr,
        p,
        k,
        min_pop,
        indices.ptr,
        cells.ptr,
        null,
        0,
    );
    try std.testing.expectEqual(kernels.RC_OK, rc);

    // Rebalanced indices must match the golden exactly.
    for (out_arr.items, 0..) |v, i| {
        try std.testing.expectEqual(@as(u8, @intCast(v.integer)), indices[i]);
    }

    // Cell stats (mean3, std3, count) per slot must match the golden exactly.
    const cells_arr = root.get("cells").?.array;
    try std.testing.expectEqual(kk, cells_arr.items.len);
    for (cells_arr.items, 0..) |cell, s| {
        var f: usize = 0;
        while (f < 7) : (f += 1) {
            try std.testing.expectEqual(
                @as(i32, @intCast(cell.array.items[f].integer)),
                cells[s * 7 + f],
            );
        }
    }
}
