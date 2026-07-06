//! Host tests for multiscale.zig — the byte-exact Zig twin of
//! Spec.MultiScaleCapture. Self-contained (std only here for std.testing; the
//! kernels import nothing). Each test mirrors one spec law:
//!   * the keystone: slow − pooled-fast == dead-time, always >= 0.
//!   * not derivable: a gap-emitting world makes slow ≠ pool(fast).
//!   * information add: same fast read, different slow read.
//!   * 10-bit × 3 absorbed: a ceiling world round-trips as exact integer sums.

const std = @import("std");
const ms = @import("multiscale.zig");

const N: usize = @intCast(ms.CHANS * ms.SUBSLICES); // 48

// A deterministic LCG world, each sample a raw u16 (clamp10 handles >1023).
fn lcgWorld(buf: []u16, seed0: u64) void {
    var s: u64 = seed0;
    for (buf) |*b| {
        s = s *% 6364136223846793005 +% 1442695040888963407;
        b.* = @intCast((s >> 40) & 0x7ff); // 0..2047 → exercises the 10-bit clamp
    }
}

test "keystone: slow - pool == dead-time, and dead-time >= 0 (byte-for-byte the spec)" {
    var seed: u64 = 0x5158_464F_5552_3634;
    var trial: usize = 0;
    while (trial < 64) : (trial += 1) {
        var world: [N]u16 = undefined;
        lcgWorld(&world, seed);
        seed +%= 0x9E37_79B9_7F4A_7C15;
        var ch: i32 = 0;
        while (ch < ms.CHANS) : (ch += 1) {
            var j: i32 = 0;
            while (j < ms.SLOW_FRAMES) : (j += 1) {
                const slow = ms.s4_ms_read_slow(&world, ch, j);
                const pool = ms.s4_ms_pool_fast_to_slow(&world, ch, j);
                const dead = ms.s4_ms_dead_time(&world, ch, j);
                try std.testing.expectEqual(slow - pool, dead);
                try std.testing.expect(dead >= 0);
            }
        }
    }
}

test "not derivable: a photon in a readout gap makes slow != pool(fast)" {
    // World is all zero except one photon in sub-slice 1 (a gap: 1 % SUB_PER_FAST != 0), channel 0.
    var world: [N]u16 = [_]u16{0} ** N;
    world[1] = 500;
    try std.testing.expectEqual(@as(i64, 500), ms.s4_ms_read_slow(&world, 0, 0));
    try std.testing.expectEqual(@as(i64, 0), ms.s4_ms_pool_fast_to_slow(&world, 0, 0));
    try std.testing.expect(ms.s4_ms_read_slow(&world, 0, 0) != ms.s4_ms_pool_fast_to_slow(&world, 0, 0));
}

test "information add: same fast read, different slow read (H(coarse|fine) > 0)" {
    var w1: [N]u16 = [_]u16{0} ** N;
    var w2: [N]u16 = [_]u16{0} ** N;
    w2[1] = 500; // differ ONLY on a gap sub-slice the fast read never integrates

    // Fast reads identical across every channel/frame.
    var ch: i32 = 0;
    while (ch < ms.CHANS) : (ch += 1) {
        var f: i32 = 0;
        while (f < ms.FAST_FRAMES) : (f += 1) {
            try std.testing.expectEqual(ms.s4_ms_read_fast(&w1, ch, f), ms.s4_ms_read_fast(&w2, ch, f));
        }
    }
    // Slow reads differ — the coarse scale carries info the fine scale lacks.
    try std.testing.expect(ms.s4_ms_read_slow(&w1, 0, 0) != ms.s4_ms_read_slow(&w2, 0, 0));
}

test "10-bit x 3 absorbed: ceiling world → exact integer sums, 3 channels independent" {
    var world: [N]u16 = [_]u16{ms.TEN_BIT_MAX} ** N;
    const max: i64 = @intCast(ms.TEN_BIT_MAX);
    var ch: i32 = 0;
    while (ch < ms.CHANS) : (ch += 1) {
        // fast = 1 slice at the ceiling
        var f: i32 = 0;
        while (f < ms.FAST_FRAMES) : (f += 1)
            try std.testing.expectEqual(max, ms.s4_ms_read_fast(&world, ch, f));
        // mid = (SUB_PER_FAST * MID_PER_SLOW) slices
        const mid_expect: i64 = @as(i64, ms.SUB_PER_FAST * ms.MID_PER_SLOW) * max;
        var k: i32 = 0;
        while (k < ms.MID_FRAMES) : (k += 1)
            try std.testing.expectEqual(mid_expect, ms.s4_ms_read_mid(&world, ch, k));
        // slow = (SUB_PER_FAST * FAST_PER_SLOW) slices
        const slow_expect: i64 = @as(i64, ms.SUB_PER_FAST * ms.FAST_PER_SLOW) * max;
        var j: i32 = 0;
        while (j < ms.SLOW_FRAMES) : (j += 1)
            try std.testing.expectEqual(slow_expect, ms.s4_ms_read_slow(&world, ch, j));
    }
}
