//! Host tests for multiscale_integrate.zig — the byte-exact twin of
//! Spec.MultiScaleIntegrate. Mirrors the laws (nScales=3, nCells=3,
//! nSubslices=12, round-robin owner s%3):
//!   * KEYSTONE conservation: the 3 volumes sum to the raw photons per cell.
//!   * independence: a scale's volume uses only the photons it owns.
//!   * 10-bit×3 absorbed: ceiling stream → ownedCount·1023 exact.

const std = @import("std");
const mi = @import("multiscale_integrate.zig");

const NSC: i32 = 3;
const NC: i32 = 3;
const NSUB: i32 = 12;
const NCu: usize = 3;
const NSUBu: usize = 12;

fn rrOwner(buf: []i32) void {
    for (buf, 0..) |*b, i| b.* = @intCast(@as(i64, @intCast(i % 3)));
}

fn lcg(buf: []u16, seed0: u64) void {
    var s: u64 = seed0;
    for (buf) |*b| {
        s = s *% 6364136223846793005 +% 1442695040888963407;
        b.* = @intCast((s >> 40) & 0x7ff); // 0..2047 exercises the clamp
    }
}

test "KEYSTONE: the 3 volumes conserve the raw photons (each counted once)" {
    var photons: [NCu * NSUBu]u16 = undefined;
    lcg(&photons, 42);
    var owner: [NSUBu]i32 = undefined;
    rrOwner(&owner);
    var out: [3 * 3]i64 = undefined;

    try std.testing.expectEqual(@as(i32, 0), mi.s4_multiscale_integrate(&out, &photons, &owner, NSC, NC, NSUB));

    var cell: usize = 0;
    while (cell < NCu) : (cell += 1) {
        // sum over scales
        var volSum: i64 = 0;
        var sc: usize = 0;
        while (sc < 3) : (sc += 1) volSum += out[sc * NCu + cell];
        // sum of raw photons (clamped) for this cell
        var raw: i64 = 0;
        var s: usize = 0;
        while (s < NSUBu) : (s += 1) {
            const v = photons[cell * NSUBu + s];
            raw += @intCast(@as(i64, @intCast(if (v > 1023) @as(u16, 1023) else v)));
        }
        try std.testing.expectEqual(raw, volSum);
    }
}

test "independence: a scale's volume uses only the photons it owns" {
    var photons: [NCu * NSUBu]u16 = undefined;
    lcg(&photons, 7);
    var owner: [NSUBu]i32 = undefined;
    rrOwner(&owner);

    var a: [3 * 3]i64 = undefined;
    var b: [3 * 3]i64 = undefined;
    _ = mi.s4_multiscale_integrate(&a, &photons, &owner, NSC, NC, NSUB);

    // bump sub-slice 1 (owned by scale 1) in every cell; scales 0 and 2 unchanged.
    var photons2 = photons;
    var cell: usize = 0;
    while (cell < NCu) : (cell += 1) {
        const idx = cell * NSUBu + 1;
        photons2[idx] = if (photons2[idx] < 900) photons2[idx] + 100 else photons2[idx];
    }
    _ = mi.s4_multiscale_integrate(&b, &photons2, &owner, NSC, NC, NSUB);

    cell = 0;
    while (cell < NCu) : (cell += 1) {
        try std.testing.expectEqual(a[0 * NCu + cell], b[0 * NCu + cell]); // scale 0 untouched
        try std.testing.expectEqual(a[2 * NCu + cell], b[2 * NCu + cell]); // scale 2 untouched
    }
}

test "10-bit x 3 absorbed: ceiling stream → ownedCount·1023 exact" {
    var photons: [NCu * NSUBu]u16 = [_]u16{1023} ** (NCu * NSUBu);
    var owner: [NSUBu]i32 = undefined;
    rrOwner(&owner);
    var out: [3 * 3]i64 = undefined;
    _ = mi.s4_multiscale_integrate(&out, &photons, &owner, NSC, NC, NSUB);

    // round-robin over 12 sub-slices ⇒ each scale owns exactly 4.
    var sc: usize = 0;
    while (sc < 3) : (sc += 1) {
        var cell: usize = 0;
        while (cell < NCu) : (cell += 1)
            try std.testing.expectEqual(@as(i64, 4 * 1023), out[sc * NCu + cell]);
    }
}

test "malformed owner (out of range) is refused" {
    var photons: [NCu * NSUBu]u16 = [_]u16{0} ** (NCu * NSUBu);
    var owner: [NSUBu]i32 = [_]i32{0} ** NSUBu;
    owner[3] = 9; // no such scale
    var out: [3 * 3]i64 = undefined;
    try std.testing.expectEqual(@as(i32, 1), mi.s4_multiscale_integrate(&out, &photons, &owner, NSC, NC, NSUB));
}
