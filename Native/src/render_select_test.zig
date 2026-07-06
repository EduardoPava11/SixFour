//! Host tests for render_select.zig — the byte-exact Zig twin of
//! Spec.RenderSelect (side = 8, the spec's miniature 64³). Mirrors the spec laws:
//!   * depth 2 everywhere = the fine identity (out == V64).
//!   * depth 0 everywhere = V16 block-replicated, INDEPENDENT of V64.
//!   * keystone: an all-coarse region's output is invariant to V64.

const std = @import("std");
const rs = @import("render_select.zig");

const SIDE: i32 = 8;
const N: usize = 8;
const NREG: usize = 2 * 2 * 2; // (side/4)^3 regions

fn lcg(buf: []i32, seed0: u64) void {
    var s: u64 = seed0;
    for (buf) |*b| {
        s = s *% 6364136223846793005 +% 1442695040888963407;
        b.* = @intCast(@as(i64, @intCast((s >> 40) & 0xffff)));
    }
}

test "depth 2 everywhere = fine identity (out == V64)" {
    var v16: [2 * 2 * 2]i32 = undefined;
    var v32: [4 * 4 * 4]i32 = undefined;
    var v64: [N * N * N]i32 = undefined;
    lcg(&v16, 1);
    lcg(&v32, 2);
    lcg(&v64, 3);
    var depth: [NREG]i32 = [_]i32{2} ** NREG;
    var out: [N * N * N]i32 = undefined;

    try std.testing.expectEqual(@as(i32, 0), rs.s4_render_select(&out, &v16, &v32, &v64, &depth, SIDE));
    for (out, 0..) |v, i| try std.testing.expectEqual(v64[i], v);
}

test "depth 0 everywhere = V16 replicated, independent of V64" {
    // V16 distinct per coarse cell; V64 all a different constant → proves not a pool.
    var v16: [2 * 2 * 2]i32 = undefined;
    for (&v16, 0..) |*b, i| b.* = @intCast(@as(i64, @intCast(i)) + 100);
    var v32: [4 * 4 * 4]i32 = [_]i32{0} ** (4 * 4 * 4);
    var v64: [N * N * N]i32 = [_]i32{-7} ** (N * N * N); // pool(V64) = -7 ≠ any V16
    var depth: [NREG]i32 = [_]i32{0} ** NREG;
    var out: [N * N * N]i32 = undefined;

    try std.testing.expectEqual(@as(i32, 0), rs.s4_render_select(&out, &v16, &v32, &v64, &depth, SIDE));
    var t: usize = 0;
    while (t < N) : (t += 1) {
        var y: usize = 0;
        while (y < N) : (y += 1) {
            var x: usize = 0;
            while (x < N) : (x += 1) {
                const si = ((t / 4) * 2 + (y / 4)) * 2 + (x / 4);
                try std.testing.expectEqual(v16[si], out[(t * N + y) * N + x]);
            }
        }
    }
}

test "KEYSTONE: all-coarse output is invariant to V64 (independence preserved)" {
    var v16: [2 * 2 * 2]i32 = undefined;
    var v32: [4 * 4 * 4]i32 = undefined;
    lcg(&v16, 11);
    lcg(&v32, 12);
    var v64a: [N * N * N]i32 = undefined;
    var v64b: [N * N * N]i32 = undefined;
    lcg(&v64a, 13);
    for (&v64b, 0..) |*b, i| b.* = v64a[i] + 1; // a genuinely different V64
    var depth: [NREG]i32 = [_]i32{0} ** NREG;
    var outA: [N * N * N]i32 = undefined;
    var outB: [N * N * N]i32 = undefined;

    _ = rs.s4_render_select(&outA, &v16, &v32, &v64a, &depth, SIDE);
    _ = rs.s4_render_select(&outB, &v16, &v32, &v64b, &depth, SIDE);
    for (outA, 0..) |v, i| try std.testing.expectEqual(v, outB[i]);
}

test "bad side (not a multiple of 4) is refused" {
    var one: [1]i32 = .{0};
    var out: [1]i32 = undefined;
    try std.testing.expectEqual(@as(i32, 1), rs.s4_render_select(&out, &one, &one, &one, &one, 6));
}
