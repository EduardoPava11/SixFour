//! Cross-language V2.1 palette-delta golden fixture test (the temporal metric weight axisWeight T = pd).
//!
//! `spec-fixtures` (Haskell, SixFour.Spec.V21Field.paletteDelta) writes v21_palette_delta_golden.json:
//! two k-slot palettes (flat slot-major, slot*3 + channel), the value alphabet n_levels, and their
//! palette delta (the L1 between the two palettes' per-channel value histograms). This test:
//!   1. runs `s4_v21_palette_delta` and asserts BIT-EXACT agreement on the scalar delta;
//!   2. asserts SYMMETRY (delta(a,b) == delta(b,a)) on the same kernel;
//!   3. asserts GAUGE INVARIANCE at the kernel level: reversing pal1's slot order leaves the delta
//!      unchanged (the histogram counts values, not slots), the property the temporal weight relies on.
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

// Read a flat JSON int array into a freshly-allocated []u8 (the palette values are 0..n_levels-1).
fn readU8Array(alloc: std.mem.Allocator, arr: std.json.Array) ![]u8 {
    const out = try alloc.alloc(u8, arr.items.len);
    for (arr.items, 0..) |v, i| out[i] = @intCast(v.integer);
    return out;
}

// Reverse the SLOT order of a flat slot-major palette (keep each RGB triple intact).
fn reverseSlots(alloc: std.mem.Allocator, pal: []const u8) ![]u8 {
    const out = try alloc.alloc(u8, pal.len);
    const k = pal.len / 3;
    var s: usize = 0;
    while (s < k) : (s += 1) {
        const src = (k - 1 - s) * 3;
        out[s * 3 + 0] = pal[src + 0];
        out[s * 3 + 1] = pal[src + 1];
        out[s * 3 + 2] = pal[src + 2];
    }
    return out;
}

test "cross-language: s4_v21_palette_delta matches the Haskell golden + symmetry + gauge invariance" {
    const alloc = std.testing.allocator;
    const dir = build_options.fixture_dir;

    const raw = readFileAlloc(alloc, dir, "v21_palette_delta_golden.json") catch |e| {
        if (e == error.SkipZigTest) {
            std.debug.print(
                "\n  [skip] v21_palette_delta_golden.json not in '{s}'; run `cd spec && cabal run spec-fixtures`\n",
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
    const want: i32 = @intCast(root.get("palette_delta").?.integer);

    const pal1 = try readU8Array(alloc, root.get("pal1").?.array);
    defer alloc.free(pal1);
    const pal2 = try readU8Array(alloc, root.get("pal2").?.array);
    defer alloc.free(pal2);

    // (1) the scalar delta is bit-exact.
    var pd: i32 = -1;
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_v21_palette_delta(pal1.ptr, pal2.ptr, k, n_levels, &pd));
    try std.testing.expectEqual(want, pd);

    // (2) symmetry: delta(pal2, pal1) == delta(pal1, pal2).
    var pd_swapped: i32 = -1;
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_v21_palette_delta(pal2.ptr, pal1.ptr, k, n_levels, &pd_swapped));
    try std.testing.expectEqual(want, pd_swapped);

    // (3) gauge invariance: reversing pal1's slot order (the index gauge) does not change the delta.
    const pal1_rev = try reverseSlots(alloc, pal1);
    defer alloc.free(pal1_rev);
    var pd_gauge: i32 = -1;
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_v21_palette_delta(pal1_rev.ptr, pal2.ptr, k, n_levels, &pd_gauge));
    try std.testing.expectEqual(want, pd_gauge);
}
