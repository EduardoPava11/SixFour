//! Cross-language temporal one-level Haar golden fixture test.
//!
//! `spec-fixtures` (Haskell, SixFour.Spec.TemporalLoop.haarSplitTime) writes
//! temporal_golden.json: a fixed NEGATIVE-heavy 8-frame OKLab sequence with its
//! (low, high) bands. This test runs `s4_haar_split_level` on the SAME frames and
//! asserts BIT-EXACT agreement, then `s4_haar_join_level` and asserts the frames
//! come back EXACTLY (lossless integer Haar — no tolerance). It also exercises an
//! ODD-length negative round-trip with no golden (invertibility is self-evident).
//!
//! This is the temporal half of SixFour.Spec.VoxelReduce; the spatial half is gated
//! by rgbt4d_fixture_test (s4_cube_lift_level). Skip-if-absent.

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

test "cross-language: s4_haar_split_level/join_level match the Haskell temporal-Haar golden" {
    const alloc = std.testing.allocator;
    const dir = build_options.fixture_dir;

    const raw = readFileAlloc(alloc, dir, "temporal_golden.json") catch |e| {
        if (e == error.SkipZigTest) {
            std.debug.print(
                "\n  [skip] temporal_golden.json not in '{s}'; run `cd spec && cabal run spec-fixtures`\n",
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
    const low_n = nn / 2 + nn % 2;
    const high_n = nn / 2;

    const frames = try flattenTriples(alloc, root.get("frames").?);
    defer alloc.free(frames);
    const exp_low = try flattenTriples(alloc, root.get("low").?);
    defer alloc.free(exp_low);
    const exp_high = try flattenTriples(alloc, root.get("high").?);
    defer alloc.free(exp_high);

    // split: low + high byte-exact vs the Haskell haarSplitTime golden.
    const got_low = try alloc.alloc(i32, low_n * 3);
    defer alloc.free(got_low);
    const got_high = try alloc.alloc(i32, high_n * 3);
    defer alloc.free(got_high);
    const rc_s = kernels.s4_haar_split_level(n, frames.ptr, got_low.ptr, got_high.ptr);
    try std.testing.expectEqual(kernels.RC_OK, rc_s);
    try std.testing.expectEqualSlices(i32, exp_low, got_low);
    try std.testing.expectEqualSlices(i32, exp_high, got_high);

    // join: the frames come back EXACTLY (lossless).
    const got_frames = try alloc.alloc(i32, nn * 3);
    defer alloc.free(got_frames);
    const rc_j = kernels.s4_haar_join_level(@intCast(low_n), @intCast(high_n), got_low.ptr, got_high.ptr, got_frames.ptr);
    try std.testing.expectEqual(kernels.RC_OK, rc_j);
    try std.testing.expectEqualSlices(i32, frames, got_frames);
}

test "s4_haar_split_level/join_level: odd-length negative round-trip (floor-div sign trap)" {
    // 5 frames (odd), negative-heavy: the carried-tail path + the @divFloor-on-negatives case.
    const m: usize = 5;
    const frames = [_]i32{
        -7,  3,    -128, 65,  -1, -2,
        -128, 127, 0,    -64, 33, -99,
        -5,  -5,   -5, // the odd tail
    };
    const low_n = m / 2 + m % 2; // 3
    const high_n = m / 2; // 2

    var got_low: [3 * 3]i32 = undefined;
    var got_high: [2 * 3]i32 = undefined;
    const rc_s = kernels.s4_haar_split_level(@intCast(m), &frames, &got_low, &got_high);
    try std.testing.expectEqual(kernels.RC_OK, rc_s);

    var got: [m * 3]i32 = undefined;
    const rc_j = kernels.s4_haar_join_level(@intCast(low_n), @intCast(high_n), &got_low, &got_high, &got);
    try std.testing.expectEqual(kernels.RC_OK, rc_j);
    try std.testing.expectEqualSlices(i32, &frames, &got);
}
