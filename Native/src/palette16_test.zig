//! Host tests for palette16.zig (the GIF89a-camera color head). Self-contained:
//! no fixtures, no allocator in the kernels under test; std only here for
//! std.testing. The two load-bearing tests mirror the Haskell spec:
//!   * SUMS ARE THE PYRAMID CARRIER: pooling composes exactly on block-sums
//!     (Spec.V21Pyramid lawPyramidTransitive, here byte-for-byte in Zig).
//!   * MEANS ARE NOT: a witness where round-half-up means pooled 64->32->16
//!     differ from 64->16 — why the GCT is a final realization, never a rung.

const std = @import("std");
const p16 = @import("palette16.zig");

fn fillLcg(buf: []u8, seed0: u64) void {
    var s: u64 = seed0;
    for (buf) |*b| {
        s = s *% 6364136223846793005 +% 1442695040888963407;
        b.* = @intCast((s >> 33) & 0xff);
    }
}

test "constant frame: every palette slot is that color (16x16 = 256 slots)" {
    var frame: [64 * 64 * 3]u8 = undefined;
    var i: usize = 0;
    while (i < frame.len) : (i += 3) {
        frame[i] = 10;
        frame[i + 1] = 20;
        frame[i + 2] = 30;
    }
    var gct: [768]u8 = undefined;
    try std.testing.expectEqual(p16.S4_RC_OK, p16.s4_palette16_gct(&frame, 64, &gct));
    i = 0;
    while (i < 768) : (i += 3) {
        try std.testing.expectEqual(@as(u8, 10), gct[i]);
        try std.testing.expectEqual(@as(u8, 20), gct[i + 1]);
        try std.testing.expectEqual(@as(u8, 30), gct[i + 2]);
    }
}

test "bin-constant frame: the GCT is exactly the scene's own 16x16 view" {
    // 32x32 frame, q=2: paint each 2x2 bin with the byte (by*16+bx) mod 256 on
    // all channels — the palette must reproduce the bin values verbatim.
    var frame: [32 * 32 * 3]u8 = undefined;
    var y: usize = 0;
    while (y < 32) : (y += 1) {
        var x: usize = 0;
        while (x < 32) : (x += 1) {
            const v: u8 = @intCast(((y / 2) * 16 + (x / 2)) & 0xff);
            const px = (y * 32 + x) * 3;
            frame[px] = v;
            frame[px + 1] = v;
            frame[px + 2] = v;
        }
    }
    var gct: [768]u8 = undefined;
    try std.testing.expectEqual(p16.S4_RC_OK, p16.s4_palette16_gct(&frame, 32, &gct));
    var slot: usize = 0;
    while (slot < 256) : (slot += 1) {
        const v: u8 = @intCast(slot & 0xff);
        try std.testing.expectEqual(v, gct[slot * 3]);
        try std.testing.expectEqual(v, gct[slot * 3 + 1]);
        try std.testing.expectEqual(v, gct[slot * 3 + 2]);
    }
}

test "rounding realization is round-half-up, deterministic" {
    // One 2x2 bin (side=2, out_side=1): {0,1,1,1} -> 0.75 -> 1; {0,0,0,1} ->
    // 0.25 -> 0; {0,0,1,1} -> 0.5 -> 1 (half rounds UP, documented).
    const cases = [_]struct { px: [4]u8, want: u8 }{
        .{ .px = .{ 0, 1, 1, 1 }, .want = 1 },
        .{ .px = .{ 0, 0, 0, 1 }, .want = 0 },
        .{ .px = .{ 0, 0, 1, 1 }, .want = 1 },
    };
    for (cases) |c| {
        var frame: [2 * 2 * 3]u8 = undefined;
        for (0..4) |i| {
            frame[i * 3] = c.px[i];
            frame[i * 3 + 1] = c.px[i];
            frame[i * 3 + 2] = c.px[i];
        }
        var sums: [3]u64 = undefined;
        try std.testing.expectEqual(p16.S4_RC_OK, p16.s4_pool_sums_srgb8(&frame, 2, 1, &sums));
        var out: [3]u8 = undefined;
        try std.testing.expectEqual(p16.S4_RC_OK, p16.s4_sums_to_srgb8(&sums, 1, 4, &out));
        try std.testing.expectEqual(c.want, out[0]);
    }
}

test "LAW (pyramid carrier): block-sums compose exactly, 64->16 == 64->32->16" {
    var frame: [64 * 64 * 3]u8 = undefined;
    fillLcg(&frame, 20260703);

    var direct: [16 * 16 * 3]u64 = undefined;
    try std.testing.expectEqual(p16.S4_RC_OK, p16.s4_pool_sums_srgb8(&frame, 64, 16, &direct));

    // Two-step: sums to 32, re-expressed as a synthetic image is impossible
    // without loss — so compose on SUMS directly: pool the 32x32 sums by 2x2
    // block-sum addition (what pooling means on the carrier).
    var mid: [32 * 32 * 3]u64 = undefined;
    try std.testing.expectEqual(p16.S4_RC_OK, p16.s4_pool_sums_srgb8(&frame, 64, 32, &mid));
    var twostep: [16 * 16 * 3]u64 = undefined;
    var by: usize = 0;
    while (by < 16) : (by += 1) {
        var bx: usize = 0;
        while (bx < 16) : (bx += 1) {
            for (0..3) |c| {
                var acc: u64 = 0;
                for (0..2) |dy| {
                    for (0..2) |dx| {
                        acc += mid[(((by * 2 + dy) * 32) + (bx * 2 + dx)) * 3 + c];
                    }
                }
                twostep[(by * 16 + bx) * 3 + c] = acc;
            }
        }
    }
    try std.testing.expectEqualSlices(u64, &direct, &twostep);
}

test "TEETH: rounded means do NOT compose across rungs (why sums are the carrier)" {
    // Construct a 4x4 frame (one output bin at out=1, mid rung out=2) where
    // rounding at the mid rung shifts the final byte. Bins (q=2) with sums
    // chosen so half-up rounding at 2x2 disagrees with the global mean:
    // quadrant means 0.5,0,0,0 -> mid bytes 1,0,0,0 -> re-mean 0.25 -> 0? and
    // direct mean = 2/16 = 0.125 -> 0. Need a real witness — search small
    // frames deterministically instead of hand-picking.
    var found = false;
    var seed: u64 = 1;
    while (seed < 200 and !found) : (seed += 1) {
        var frame: [4 * 4 * 3]u8 = undefined;
        fillLcg(&frame, seed);

        // direct: 4x4 -> 1x1 mean
        var s1: [3]u64 = undefined;
        _ = p16.s4_pool_sums_srgb8(&frame, 4, 1, &s1);
        var direct: [3]u8 = undefined;
        _ = p16.s4_sums_to_srgb8(&s1, 1, 16, &direct);

        // staged: 4x4 -> 2x2 bytes -> 1x1 bytes (rounding TWICE)
        var s2: [2 * 2 * 3]u64 = undefined;
        _ = p16.s4_pool_sums_srgb8(&frame, 4, 2, &s2);
        var mid: [2 * 2 * 3]u8 = undefined;
        _ = p16.s4_sums_to_srgb8(&s2, 2, 4, &mid);
        var s3: [3]u64 = undefined;
        _ = p16.s4_pool_sums_srgb8(&mid, 2, 1, &s3);
        var staged: [3]u8 = undefined;
        _ = p16.s4_sums_to_srgb8(&s3, 1, 4, &staged);

        if (!std.mem.eql(u8, &direct, &staged)) found = true;
    }
    try std.testing.expect(found);
}

test "bad args are refused, not absorbed" {
    var frame: [48 * 48 * 3]u8 = undefined;
    fillLcg(&frame, 7);
    var gct: [768]u8 = undefined;
    // 48 is a multiple of 16 -> OK; 40 is not.
    try std.testing.expectEqual(p16.S4_RC_OK, p16.s4_palette16_gct(&frame, 48, &gct));
    try std.testing.expectEqual(p16.S4_RC_BAD_ARGS, p16.s4_palette16_gct(&frame, 40, &gct));
    var sums: [3]u64 = undefined;
    try std.testing.expectEqual(p16.S4_RC_BAD_ARGS, p16.s4_pool_sums_srgb8(&frame, 48, 0, &sums));
    try std.testing.expectEqual(p16.S4_RC_BAD_ARGS, p16.s4_pool_sums_srgb8(&frame, 16, 48, &sums));
    try std.testing.expectEqual(p16.S4_RC_BAD_ARGS, p16.s4_pool_sums_srgb8(null, 16, 16, &sums));
}

test "LAW (the time law): GIF89a centiseconds cap the isotropic ladder at 64" {
    try std.testing.expectEqual(@as(i32, 5), p16.s4_ladder_delay_cs(64)); // 20 fps
    try std.testing.expectEqual(@as(i32, 10), p16.s4_ladder_delay_cs(32)); // 10 fps
    try std.testing.expectEqual(@as(i32, 20), p16.s4_ladder_delay_cs(16)); //  5 fps
    try std.testing.expectEqual(@as(i32, 40), p16.s4_ladder_delay_cs(8)); //  2.5 fps
    // 128 @ 40 fps needs 2.5 cs — GIF89a cannot say it.
    try std.testing.expectEqual(p16.S4_RC_NOT_REPRESENTABLE, p16.s4_ladder_delay_cs(128));
    try std.testing.expectEqual(p16.S4_RC_NOT_REPRESENTABLE, p16.s4_ladder_delay_cs(256));
    try std.testing.expectEqual(p16.S4_RC_BAD_ARGS, p16.s4_ladder_delay_cs(0));
}

// ── The measurement path: inverse-EOTF LUTs + linear pooling ──

test "GOLDEN SPOTS: sRGB and HLG inverse-EOTF tables match the reference math" {
    // sRGB: lin = c/12.92 (c<=0.04045) else ((c+0.055)/1.055)^2.4, c=v/255.
    try std.testing.expectEqual(@as(u16, 0), p16.srgb_to_linear16[0]);
    try std.testing.expectEqual(@as(u16, 20), p16.srgb_to_linear16[1]);
    try std.testing.expectEqual(@as(u16, 199), p16.srgb_to_linear16[10]); // linear segment
    try std.testing.expectEqual(@as(u16, 219), p16.srgb_to_linear16[11]); // past threshold
    try std.testing.expectEqual(@as(u16, 14146), p16.srgb_to_linear16[128]); // mid-gray
    try std.testing.expectEqual(@as(u16, 65535), p16.srgb_to_linear16[255]);
    // HLG (BT.2100 inverse OETF, full-range 10-bit): e^2/3 below the knee.
    try std.testing.expectEqual(@as(u16, 0), p16.hlg_to_linear16[0]);
    try std.testing.expectEqual(@as(u16, 5451), p16.hlg_to_linear16[511]); // knee left
    try std.testing.expectEqual(@as(u16, 5472), p16.hlg_to_linear16[512]); // knee right
    try std.testing.expectEqual(@as(u16, 65186), p16.hlg_to_linear16[1022]);
    try std.testing.expectEqual(@as(u16, 65535), p16.hlg_to_linear16[1023]); // clamped top
}

test "LAW: both LUTs are monotone nondecreasing (a valid transfer inverse)" {
    for (0..255) |i| {
        try std.testing.expect(p16.srgb_to_linear16[i] <= p16.srgb_to_linear16[i + 1]);
    }
    for (0..1023) |i| {
        try std.testing.expect(p16.hlg_to_linear16[i] <= p16.hlg_to_linear16[i + 1]);
    }
}

test "linear pooling, constant frame: sums == area * LUT[v] exactly (both feeds)" {
    var frame8: [32 * 32 * 3]u8 = undefined;
    @memset(&frame8, 200);
    var sums: [16 * 16 * 3]u64 = undefined;
    try std.testing.expectEqual(p16.S4_RC_OK, p16.s4_pool_sums_linear_srgb8(&frame8, 32, 16, &sums));
    for (sums) |v| try std.testing.expectEqual(4 * @as(u64, p16.srgb_to_linear16[200]), v);

    var frame10: [32 * 32 * 3]u16 = undefined;
    @memset(&frame10, 700);
    try std.testing.expectEqual(p16.S4_RC_OK, p16.s4_pool_sums_linear_hlg10(&frame10, 32, 16, &sums));
    for (sums) |v| try std.testing.expectEqual(4 * @as(u64, p16.hlg_to_linear16[700]), v);
}

test "TOTALITY: an out-of-range 10-bit code refuses the WHOLE frame, no partial sums" {
    var frame10: [16 * 16 * 3]u16 = undefined;
    @memset(&frame10, 100);
    frame10[frame10.len - 1] = 1024; // one poison code at the very end
    var sums: [16 * 16 * 3]u64 = undefined;
    @memset(&sums, 0xAAAAAAAAAAAAAAAA);
    try std.testing.expectEqual(p16.S4_RC_OUT_OF_RANGE, p16.s4_pool_sums_linear_hlg10(&frame10, 16, 16, &sums));
    for (sums) |v| try std.testing.expectEqual(@as(u64, 0xAAAAAAAAAAAAAAAA), v); // untouched
    try std.testing.expectEqual(p16.S4_RC_OUT_OF_RANGE, p16.s4_hlg10_to_linear16(1024));
    try std.testing.expectEqual(@as(i32, @intCast(p16.hlg_to_linear16[1023])), p16.s4_hlg10_to_linear16(1023));
}

test "TEETH (the mid-gray trap): gamma-pool-then-linearize != linearize-then-pool, 2.3x apart" {
    // One 2x2 bin: {0, 0, 255, 255} on all channels.
    var frame: [2 * 2 * 3]u8 = undefined;
    for (0..4) |i| {
        const v: u8 = if (i < 2) 0 else 255;
        frame[i * 3] = v;
        frame[i * 3 + 1] = v;
        frame[i * 3 + 2] = v;
    }
    // Gamma path: pool bytes -> byte 128 -> linearize -> 14146.
    var gsums: [3]u64 = undefined;
    _ = p16.s4_pool_sums_srgb8(&frame, 2, 1, &gsums);
    var gbyte: [3]u8 = undefined;
    _ = p16.s4_sums_to_srgb8(&gsums, 1, 4, &gbyte);
    try std.testing.expectEqual(@as(u8, 128), gbyte[0]);
    const gamma_then_lin: u64 = p16.srgb_to_linear16[gbyte[0]];
    // Linear path: linearize -> pool -> mean 32768 (round-half-up of 32767.5).
    var lsums: [3]u64 = undefined;
    _ = p16.s4_pool_sums_linear_srgb8(&frame, 2, 1, &lsums);
    const lin_mean: u64 = (lsums[0] + 2) / 4;
    try std.testing.expectEqual(@as(u64, 14146), gamma_then_lin);
    try std.testing.expectEqual(@as(u64, 32768), lin_mean);
    try std.testing.expect(2 * gamma_then_lin < lin_mean); // the trap is >2x, not a rounding nit
}

test "LAW: linear sums keep the transitive carrier property, 64->16 == 64->32->16" {
    var frame: [64 * 64 * 3]u8 = undefined;
    fillLcg(&frame, 99);
    var direct: [16 * 16 * 3]u64 = undefined;
    try std.testing.expectEqual(p16.S4_RC_OK, p16.s4_pool_sums_linear_srgb8(&frame, 64, 16, &direct));
    var mid: [32 * 32 * 3]u64 = undefined;
    try std.testing.expectEqual(p16.S4_RC_OK, p16.s4_pool_sums_linear_srgb8(&frame, 64, 32, &mid));
    var twostep: [16 * 16 * 3]u64 = undefined;
    var by: usize = 0;
    while (by < 16) : (by += 1) {
        var bx: usize = 0;
        while (bx < 16) : (bx += 1) {
            for (0..3) |c| {
                var acc: u64 = 0;
                for (0..2) |dy| {
                    for (0..2) |dx| {
                        acc += mid[(((by * 2 + dy) * 32) + (bx * 2 + dx)) * 3 + c];
                    }
                }
                twostep[(by * 16 + bx) * 3 + c] = acc;
            }
        }
    }
    try std.testing.expectEqualSlices(u64, &direct, &twostep);
}
