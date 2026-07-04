//! Host tests for kinematic.zig — pinned to the Haskell laws
//! (Spec.KinematicLadder / Spec.KinematicHaltPrior): polynomial degree d
//! certifies at d; L_j == 0 iff j >= certified order; t^{k+1} escapes order k
//! with residual exactly (k+1)! at t = k+1; short windows REFUSE (no vacuous
//! certification, stricter than the Haskell harness).

const std = @import("std");
const kin = @import("kinematic.zig");

fn polyTrajectory(comptime deg: usize, coeffs: [deg + 1]i64, out: []i64) void {
    for (out, 0..) |*v, t| {
        var acc: i64 = 0;
        var p: i64 = 1;
        for (coeffs) |c| {
            acc += c * p;
            p *= @intCast(t);
        }
        v.* = acc;
    }
}

test "polynomial of exact degree d certifies at d (mirrors trajectory law)" {
    var f: [10]i64 = undefined;
    polyTrajectory(0, .{7}, &f);
    try std.testing.expectEqual(@as(i32, 0), kin.s4_certified_order(&f, 10, 4));
    polyTrajectory(1, .{ 3, 5 }, &f);
    try std.testing.expectEqual(@as(i32, 1), kin.s4_certified_order(&f, 10, 4));
    polyTrajectory(2, .{ 1, -2, 9 }, &f);
    try std.testing.expectEqual(@as(i32, 2), kin.s4_certified_order(&f, 10, 4));
    polyTrajectory(3, .{ 4, 0, -1, 11 }, &f);
    try std.testing.expectEqual(@as(i32, 3), kin.s4_certified_order(&f, 10, 4));
}

test "LAW (minimal sufficiency): L_j == 0 iff j >= certified order" {
    var f: [10]i64 = undefined;
    polyTrajectory(2, .{ 5, 3, 7 }, &f); // certified order 2
    try std.testing.expect(kin.s4_residual_loss(&f, 10, 0) > 0);
    try std.testing.expect(kin.s4_residual_loss(&f, 10, 1) > 0);
    try std.testing.expectEqual(@as(i64, 0), kin.s4_residual_loss(&f, 10, 2));
    try std.testing.expectEqual(@as(i64, 0), kin.s4_residual_loss(&f, 10, 3));
    try std.testing.expectEqual(@as(i64, 0), kin.s4_residual_loss(&f, 10, 4));
}

test "TEETH: t^{k+1} escapes order k with residual exactly (k+1)! at t=k+1" {
    inline for (0..4) |k| {
        var f: [10]i64 = undefined;
        for (&f, 0..) |*v, t| {
            var p: i64 = 1;
            for (0..k + 1) |_| p *= @intCast(t);
            v.* = p; // f(t) = t^{k+1}
        }
        var fact: i64 = 1;
        var i: i64 = 1;
        while (i <= k + 1) : (i += 1) fact *= i;
        const t: i32 = @intCast(k + 1);
        const res = f[@intCast(t)] - kin.s4_newton_predict(&f, 10, @intCast(k), t);
        try std.testing.expectEqual(fact, res);
    }
}

test "Newton full expansion reproduces the window (Mahler loses nothing)" {
    var s: u64 = 20260704;
    var f: [8]i64 = undefined;
    for (&f) |*v| {
        s = s *% 6364136223846793005 +% 1442695040888963407;
        v.* = @as(i64, @intCast((s >> 33) & 0x3ff)) - 512;
    }
    for (0..8) |t| {
        try std.testing.expectEqual(f[t], kin.s4_newton_predict(&f, 8, 7, @intCast(t)));
    }
}

test "TOTALITY: short windows REFUSE rather than vacuously certify" {
    var f = [_]i64{ 1, 2, 3, 4 };
    // n=4 can falsify up to Delta^2 (cap <= 2); cap=3 needs n >= 5 -> refuse.
    try std.testing.expect(kin.s4_certified_order(&f, 4, 2) >= 0);
    try std.testing.expectEqual(kin.S4K_RC_BAD_ARGS, kin.s4_certified_order(&f, 4, 3));
    try std.testing.expectEqual(kin.S4K_RC_BAD_ARGS, kin.s4_certified_order(null, 4, 1));
    try std.testing.expectEqual(kin.S4K_RC_BAD_ARGS, kin.s4_certified_order(&f, 1, 0));
    try std.testing.expectEqual(@as(i64, -1), kin.s4_residual_loss(null, 4, 1));
}
