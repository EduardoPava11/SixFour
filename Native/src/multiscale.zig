//! MULTI-SCALE CAPTURE — the independence contract's Zig floor. DEPENDENCY-FREE:
//! imports NOTHING (not even std); pure integer arithmetic, caller owns all
//! memory, C ABI, i64 accumulators. Host-testable via multiscale_test.zig.
//!
//! THE CONTRACT (byte-exact twin of Spec.MultiScaleCapture): the 16³/32³/64³
//! scales are INDEPENDENT measurements of the outside world, NEVER a pool of one
//! source — a derived pyramid carries zero new world-information. They share ONE
//! clock (64 @ 20fps / 32 @ 10 / 16 @ 5 — the GIF89a cadence, see
//! s4_ladder_delay_cs in palette16.zig) with nested windows; the independence
//! lives in the EXPOSURE. The fast (64³) read is SHORT — it integrates only the
//! exposed sub-slice of each frame and misses the readout DEAD-TIME. The slow
//! (16³) read is a LONG continuous exposure over the whole window, so it exceeds
//! the pooled fast reads by EXACTLY the dead-time photons:
//!     s4_ms_read_slow(j) - s4_ms_pool_fast_to_slow(j) == s4_ms_dead_time(j) >= 0
//! and this is > 0 whenever the world emits during a gap — the coarse read is
//! not reconstructable from the fine one (Spec.lawSlowMinusPoolIsDeadTime,
//! lawScalesAreNotDerivable). This is what the derived ColorHead cannot satisfy.
//!
//! 10-BIT × 3, ABSORBED: samples are u16 in 0..1023 (three channels R,G,B kept
//! independent); every read accumulates in i64, whose headroom the width
//! contract guarantees (Spec.lawCarrierWidthSuffices: the coarsest 4×4 bin over
//! 64 frames at the 10-bit ceiling is ~1.05M << 2^63). No precision is ever
//! truncated to 8-bit on the carrier path.
//!
//! The cadence model mirrors the spec's testable mini-sizes so the reads are
//! byte-for-byte the Haskell laws; the SAME index arithmetic scales to the real
//! 64-frame burst by the caller supplying the device counts (a later parametric
//! pass — this file pins the contract at the golden sizes).

/// Colour channels R,G,B (the "×3" of 10-bit × 3).
pub const CHANS: i32 = 3;
/// The 10-bit ceiling — every sample is clamped into 0..1023.
pub const TEN_BIT_MAX: u16 = 1023;
/// Sub-slices per fast frame: index 0 is the EXPOSED slice the short read sees;
/// the rest are readout DEAD-TIME the long exposure still collects.
pub const SUB_PER_FAST: i32 = 2;
/// Cadence 64:16 — a slow (16³) frame spans this many fast (64³) frames.
pub const FAST_PER_SLOW: i32 = 4;
/// Cadence 32:16 — a slow frame spans this many mid (32³) frames.
pub const MID_PER_SLOW: i32 = 2;
/// Frames in the coarse 16³ stream (5 fps) in the golden mini-model.
pub const SLOW_FRAMES: i32 = 2;
/// Frames in the fine 64³ stream (20 fps).
pub const FAST_FRAMES: i32 = SLOW_FRAMES * FAST_PER_SLOW; // 8
/// Frames in the mid 32³ stream (10 fps).
pub const MID_FRAMES: i32 = SLOW_FRAMES * MID_PER_SLOW; // 4
/// Total sub-slices on the finest temporal grid.
pub const SUBSLICES: i32 = FAST_FRAMES * SUB_PER_FAST; // 16

/// Clamp a raw sample to the 10-bit ceiling (mirrors the spec's worldFromList).
inline fn clamp10(v: u16) u16 {
    return if (v > TEN_BIT_MAX) TEN_BIT_MAX else v;
}

/// One world sample: channel-major layout, `world[ch*SUBSLICES + s]`, clamped.
/// Returned as i64 so every read accumulates without truncation.
inline fn sample(world: [*]const u16, ch: i32, s: i32) i64 {
    const idx: usize = @intCast(ch * SUBSLICES + s);
    return @intCast(clamp10(world[idx]));
}

/// THE SHORT read (64³, fast): each fast frame integrates only its ON sub-slice.
pub export fn s4_ms_read_fast(world: [*]const u16, ch: i32, f: i32) i64 {
    return sample(world, ch, SUB_PER_FAST * f);
}

/// THE MEDIUM read (32³): continuous integration over the mid frame's window.
pub export fn s4_ms_read_mid(world: [*]const u16, ch: i32, k: i32) i64 {
    const w0 = SUB_PER_FAST * MID_PER_SLOW * k;
    const hi = w0 + SUB_PER_FAST * MID_PER_SLOW;
    var acc: i64 = 0;
    var s = w0;
    while (s < hi) : (s += 1) acc += sample(world, ch, s);
    return acc;
}

/// THE LONG read (16³, slow): continuous integration over the whole slow window
/// — the ON slices AND the dead-time gaps the fast read misses.
pub export fn s4_ms_read_slow(world: [*]const u16, ch: i32, j: i32) i64 {
    const w0 = SUB_PER_FAST * FAST_PER_SLOW * j;
    const hi = w0 + SUB_PER_FAST * FAST_PER_SLOW;
    var acc: i64 = 0;
    var s = w0;
    while (s < hi) : (s += 1) acc += sample(world, ch, s);
    return acc;
}

/// The DERIVED estimate of the slow read: pool the fast read over its window.
/// This is what the old derived pyramid computes — and it is NOT the slow read.
pub export fn s4_ms_pool_fast_to_slow(world: [*]const u16, ch: i32, j: i32) i64 {
    const lo = FAST_PER_SLOW * j;
    const hi = lo + FAST_PER_SLOW;
    var acc: i64 = 0;
    var f = lo;
    while (f < hi) : (f += 1) acc += s4_ms_read_fast(world, ch, f);
    return acc;
}

/// The dead-time photons in a slow window = long read − pooled short reads.
/// Always >= 0; strictly positive whenever the world emits during a readout gap
/// — the exact, structural measure of how much world-information the coarse read
/// carries that the fine read cannot (Spec.lawSlowMinusPoolIsDeadTime).
pub export fn s4_ms_dead_time(world: [*]const u16, ch: i32, j: i32) i64 {
    return s4_ms_read_slow(world, ch, j) - s4_ms_pool_fast_to_slow(world, ch, j);
}
