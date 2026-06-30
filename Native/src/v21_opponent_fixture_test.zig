//! Cross-language V2.1 opponent-delta golden fixture test.
//!
//! `spec-fixtures` (Haskell, SixFour.Spec.V21Field.labDeltaAt) writes v21_opponent_golden.json:
//! two bins (each 3 Q16 curves of n_levels), plus the (L,a,b) per-level delta the spec produces.
//! This test runs `s4_v21_opponent_delta` on the SAME bins and asserts BIT-EXACT agreement,
//! proving the Zig opponent-delta kernel == the Haskell V2.1 spec on one fixture (the encode target,
//! lawOpponentCommutesWithDelta).
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

// Flatten a 3-curve bin ([[R..],[G..],[B..]]) into [3*nl], channel-major (R, G, B).
fn flattenBin(alloc: std.mem.Allocator, arr: std.json.Value, nl: usize) ![]i32 {
    const out = try alloc.alloc(i32, 3 * nl);
    for (arr.array.items, 0..) |curve, c| {
        for (curve.array.items, 0..) |v, l| {
            out[c * nl + l] = @intCast(v.integer);
        }
    }
    return out;
}

test "cross-language: s4_v21_opponent_delta matches the Haskell V2.1 opponent golden" {
    const alloc = std.testing.allocator;
    const dir = build_options.fixture_dir;

    const raw = readFileAlloc(alloc, dir, "v21_opponent_golden.json") catch |e| {
        if (e == error.SkipZigTest) {
            std.debug.print(
                "\n  [skip] v21_opponent_golden.json not in '{s}'; run `cd spec && cabal run spec-fixtures`\n",
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

    const n_levels: i32 = @intCast(root.get("n_levels").?.integer);
    const nl: usize = @intCast(n_levels);

    const bin1 = try flattenBin(alloc, root.get("bin1").?, nl);
    defer alloc.free(bin1);
    const bin2 = try flattenBin(alloc, root.get("bin2").?, nl);
    defer alloc.free(bin2);
    const out_lab_json = root.get("out_lab").?.array;

    const out_lab = try alloc.alloc(i32, 3 * nl);
    defer alloc.free(out_lab);

    const rc = kernels.s4_v21_opponent_delta(bin1.ptr, bin2.ptr, n_levels, out_lab.ptr);
    try std.testing.expectEqual(kernels.RC_OK, rc);

    // Bit-exact on all three (L, a, b) delta curves (channel-major: channel c, level l at c*nl + l).
    for (out_lab_json.items, 0..) |curve, c| {
        for (curve.array.items, 0..) |want, l| {
            try std.testing.expectEqual(@as(i32, @intCast(want.integer)), out_lab[c * nl + l]);
        }
    }
}
