//! Cross-language global-collapse golden fixture test (GIFA → GIFB).
//!
//! `spec-fixtures` (Haskell, SixFour.Spec.Collapse) writes collapse_golden.json:
//! the pooled per-frame Q16 palettes, with the k_out maximin global leaves +
//! the flattened per-frame nearest-leaf assignment the fixed-point spec produces.
//! This test runs `s4_global_collapse` on the SAME pooled cloud and asserts
//! BIT-EXACT agreement on both the leaves and the re-index — proving the Zig
//! collapse kernel ≡ the Haskell spec ≡ CollapseGolden.swift on one fixture.
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

test "cross-language: s4_global_collapse matches the Haskell collapse golden" {
    const alloc = std.testing.allocator;
    const dir = build_options.fixture_dir;

    const raw = readFileAlloc(alloc, dir, "collapse_golden.json") catch |e| {
        if (e == error.SkipZigTest) {
            std.debug.print(
                "\n  [skip] collapse_golden.json not in '{s}'; run `cd spec && cabal run spec-fixtures`\n",
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

    const t: i32 = @intCast(root.get("t").?.integer);
    const k_in: i32 = @intCast(root.get("k_in").?.integer);
    const k_out: i32 = @intCast(root.get("k_out").?.integer);
    const p: usize = @intCast(t * k_in);
    const ko: usize = @intCast(k_out);

    const palettes = try flattenTriples(alloc, root.get("palettes").?);
    defer alloc.free(palettes);

    const out_leaves = try alloc.alloc(i32, ko * 3);
    defer alloc.free(out_leaves);
    const out_indices = try alloc.alloc(u8, p);
    defer alloc.free(out_indices);

    const scratch_bytes = p * @sizeOf(i64) + 3 * ko * @sizeOf(i64) + ko * @sizeOf(i32);
    const scratch = try alloc.alloc(u8, scratch_bytes);
    defer alloc.free(scratch);

    const rc = kernels.s4_global_collapse(
        palettes.ptr,
        t,
        k_in,
        k_out,
        out_leaves.ptr,
        out_indices.ptr,
        scratch.ptr,
        scratch.len,
    );
    try std.testing.expectEqual(kernels.RC_OK, rc);

    // Global leaves (k_out × 3 Q16) byte-exact.
    const exp_leaves = root.get("leaves").?.array;
    try std.testing.expectEqual(ko, exp_leaves.items.len);
    for (exp_leaves.items, 0..) |c, j| {
        try std.testing.expectEqual(@as(i32, @intCast(c.array.items[0].integer)), out_leaves[j * 3 + 0]);
        try std.testing.expectEqual(@as(i32, @intCast(c.array.items[1].integer)), out_leaves[j * 3 + 1]);
        try std.testing.expectEqual(@as(i32, @intCast(c.array.items[2].integer)), out_leaves[j * 3 + 2]);
    }
    // Flattened per-frame re-index (t·k_in indices) byte-exact.
    const exp_indices = root.get("indices").?.array;
    try std.testing.expectEqual(p, exp_indices.items.len);
    for (exp_indices.items, 0..) |v, i| {
        try std.testing.expectEqual(@as(u8, @intCast(v.integer)), out_indices[i]);
    }
}
