//! Cross-language V2.1 mode-relative ENCODER-INPUT golden fixture test.
//!
//! `spec-fixtures` (Haskell, SixFour.Spec.V21Field.centeredEnergy / modeRelative / anchorAt) writes
//! v21_mode_relative_golden.json: p*3 energy curves of n_levels each, plus their centered energies,
//! mode-relative presentations, GIF modes (collapseQ16), and the anchored reconstruction. This test
//! runs `s4_v21_centered_energy`, `s4_v21_mode_relative`, and `s4_v21_anchor_at` on the SAME curves
//! and asserts BIT-EXACT agreement, AND that the anchor reproduces the centered curve (field + GIF
//! reconstruct the field). Proves the Zig encoder-input kernels == the Haskell V2.1 spec on one fixture.
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

// Flatten a JSON array-of-arrays of ints into [total*nl], row-major.
fn flatten(alloc: std.mem.Allocator, rows: std.json.Array, total: usize, nl: usize) ![]i32 {
    const out = try alloc.alloc(i32, total * nl);
    for (rows.items, 0..) |row, r| {
        for (row.array.items, 0..) |e, l| {
            out[r * nl + l] = @intCast(e.integer);
        }
    }
    return out;
}

test "cross-language: s4_v21_centered_energy / mode_relative / anchor_at match the Haskell golden" {
    const alloc = std.testing.allocator;
    const dir = build_options.fixture_dir;

    const raw = readFileAlloc(alloc, dir, "v21_mode_relative_golden.json") catch |e| {
        if (e == error.SkipZigTest) {
            std.debug.print(
                "\n  [skip] v21_mode_relative_golden.json not in '{s}'; run `cd spec && cabal run spec-fixtures`\n",
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
    const total: usize = @intCast(p * 3);
    const nl: usize = @intCast(n_levels);

    const curves = try flatten(alloc, root.get("curves").?.array, total, nl);
    defer alloc.free(curves);
    const want_centered = try flatten(alloc, root.get("centered").?.array, total, nl);
    defer alloc.free(want_centered);
    const want_rel = try flatten(alloc, root.get("mode_relative").?.array, total, nl);
    defer alloc.free(want_rel);
    const want_anchored = try flatten(alloc, root.get("anchored").?.array, total, nl);
    defer alloc.free(want_anchored);

    const modes = try alloc.alloc(i32, total);
    defer alloc.free(modes);
    for (root.get("modes").?.array.items, 0..) |m, i| modes[i] = @intCast(m.integer);

    // 1) centered energy == spec.
    const centered = try alloc.alloc(i32, total * nl);
    defer alloc.free(centered);
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_v21_centered_energy(curves.ptr, p, n_levels, centered.ptr));
    try std.testing.expectEqualSlices(i32, want_centered, centered);

    // 2) mode-relative == spec.
    const rel = try alloc.alloc(i32, total * nl);
    defer alloc.free(rel);
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_v21_mode_relative(curves.ptr, p, n_levels, rel.ptr));
    try std.testing.expectEqualSlices(i32, want_rel, rel);

    // 3) anchor(mode_relative, modes) == the golden anchored == the centered curve (reconstruction).
    const anchored = try alloc.alloc(i32, total * nl);
    defer alloc.free(anchored);
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_v21_anchor_at(rel.ptr, modes.ptr, p, n_levels, anchored.ptr));
    try std.testing.expectEqualSlices(i32, want_anchored, anchored);
    try std.testing.expectEqualSlices(i32, want_centered, anchored); // field + GIF reconstruct the field
}
