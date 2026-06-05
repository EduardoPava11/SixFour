//! Cross-language integer-Haar golden fixture test.
//!
//! `spec-fixtures` (Haskell, SixFour.Spec.PairTreeFixed) writes haar_golden.json:
//! a fixed Q16 leaf set with its reversible-lifting root + detail offsets. This
//! test runs `s4_haar_analyze` on the SAME leaves and asserts BIT-EXACT agreement
//! on root + offsets, then `s4_haar_reconstruct` and asserts the leaves come back
//! EXACTLY (the integer Haar is losslessly invertible — no tolerance).
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

test "cross-language: s4_haar_analyze/reconstruct match the Haskell integer-Haar golden" {
    const alloc = std.testing.allocator;
    const dir = build_options.fixture_dir;

    const raw = readFileAlloc(alloc, dir, "haar_golden.json") catch |e| {
        if (e == error.SkipZigTest) {
            std.debug.print(
                "\n  [skip] haar_golden.json not in '{s}'; run `cd spec && cabal run spec-fixtures`\n",
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

    const n: i32 = @intCast(root.get("n").?.integer);
    const nn: usize = @intCast(n);

    const leaves = try flattenTriples(alloc, root.get("leaves").?);
    defer alloc.free(leaves);
    // "root" is a single triple [l,a,b] (not an array of triples).
    const root_arr = root.get("root").?.array;
    const exp_root = [_]i32{
        @intCast(root_arr.items[0].integer),
        @intCast(root_arr.items[1].integer),
        @intCast(root_arr.items[2].integer),
    };
    const exp_offsets = try flattenTriples(alloc, root.get("offsets").?); // (n-1) triples
    defer alloc.free(exp_offsets);

    const got_root = try alloc.alloc(i32, 3);
    defer alloc.free(got_root);
    const got_offsets = try alloc.alloc(i32, (nn - 1) * 3);
    defer alloc.free(got_offsets);
    const scratch = try alloc.alloc(u8, nn * 3 * @sizeOf(i32));
    defer alloc.free(scratch);

    // analyze: root + offsets byte-exact.
    const rc_a = kernels.s4_haar_analyze(leaves.ptr, n, got_root.ptr, got_offsets.ptr, scratch.ptr, scratch.len);
    try std.testing.expectEqual(kernels.RC_OK, rc_a);
    try std.testing.expectEqualSlices(i32, &exp_root, got_root);
    try std.testing.expectEqualSlices(i32, exp_offsets, got_offsets);

    // reconstruct: leaves come back EXACTLY (lossless integer Haar).
    const got_leaves = try alloc.alloc(i32, nn * 3);
    defer alloc.free(got_leaves);
    const rc_r = kernels.s4_haar_reconstruct(got_root.ptr, got_offsets.ptr, n, got_leaves.ptr);
    try std.testing.expectEqual(kernels.RC_OK, rc_r);
    try std.testing.expectEqualSlices(i32, leaves, got_leaves);

    // level_nodes: the abstraction cascade. For each level l (2^l nodes), the Zig
    // s4_haar_level_nodes must match the Haskell levelNodesFixed golden byte-exact.
    const level_nodes = root.get("level_nodes").?.array;
    for (level_nodes.items, 0..) |lvl_val, l| {
        const exp = try flattenTriples(alloc, lvl_val);
        defer alloc.free(exp);
        const count: usize = exp.len / 3; // = 2^l
        const got = try alloc.alloc(i32, count * 3);
        defer alloc.free(got);
        const rc_l = kernels.s4_haar_level_nodes(@intCast(l), got_root.ptr, got_offsets.ptr, n, got.ptr);
        try std.testing.expectEqual(kernels.RC_OK, rc_l);
        try std.testing.expectEqualSlices(i32, exp, got);
    }
    // Deepest level == the full reconstruction (the leaves).
    const depth: usize = level_nodes.items.len - 1;
    const got_full = try alloc.alloc(i32, nn * 3);
    defer alloc.free(got_full);
    _ = kernels.s4_haar_level_nodes(@intCast(depth), got_root.ptr, got_offsets.ptr, n, got_full.ptr);
    try std.testing.expectEqualSlices(i32, leaves, got_full);
}
