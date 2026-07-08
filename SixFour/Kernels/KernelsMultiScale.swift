//  KernelsMultiScale.swift
//  Zig→Swift port of Native/src/multiscale.zig + multiscale_integrate.zig +
//  render_select.zig — (2026-07-06) byte-exact twin, golden-gated.
//
//  MULTI-SCALE CAPTURE — the independence contract's Zig floor. DEPENDENCY-FREE:
//  imports NOTHING (not even std); pure integer arithmetic, caller owns all
//  memory, C ABI, i64 accumulators. Host-testable via multiscale_test.zig
//  (ported: SixFourTests/ZigPortMultiScaleTests.swift).
//
//  THE CONTRACT (byte-exact twin of Spec.MultiScaleCapture): the 16³/32³/64³
//  scales are INDEPENDENT measurements of the outside world, NEVER a pool of one
//  source — a derived pyramid carries zero new world-information. They share ONE
//  clock (64 @ 20fps / 32 @ 10 / 16 @ 5 — the GIF89a cadence, see
//  s4_ladder_delay_cs in palette16.zig) with nested windows; the independence
//  lives in the EXPOSURE. The fast (64³) read is SHORT — it integrates only the
//  exposed sub-slice of each frame and misses the readout DEAD-TIME. The slow
//  (16³) read is a LONG continuous exposure over the whole window, so it exceeds
//  the pooled fast reads by EXACTLY the dead-time photons:
//      s4_ms_read_slow(j) - s4_ms_pool_fast_to_slow(j) == s4_ms_dead_time(j) >= 0
//  and this is > 0 whenever the world emits during a gap — the coarse read is
//  not reconstructable from the fine one (Spec.lawSlowMinusPoolIsDeadTime,
//  lawScalesAreNotDerivable). This is what the derived ColorHead cannot satisfy.
//
//  10-BIT × 3, ABSORBED: samples are u16 in 0..1023 (three channels R,G,B kept
//  independent); every read accumulates in i64, whose headroom the width
//  contract guarantees (Spec.lawCarrierWidthSuffices: the coarsest 4×4 bin over
//  64 frames at the 10-bit ceiling is ~1.05M << 2^63). No precision is ever
//  truncated to 8-bit on the carrier path.
//
//  The cadence model mirrors the spec's testable mini-sizes so the reads are
//  byte-for-byte the Haskell laws; the SAME index arithmetic scales to the real
//  64-frame burst by the caller supplying the device counts (a later parametric
//  pass — this file pins the contract at the golden sizes).

// ── multiscale.zig pub constants (Zig `pub const`, not in sixfour_native.h;
//    prefixed S4_MS_ to keep the module namespace collision-free) ─────────────

/// Colour channels R,G,B (the "×3" of 10-bit × 3).
public let S4_MS_CHANS: Int32 = 3
/// The 10-bit ceiling — every sample is clamped into 0..1023.
public let S4_MS_TEN_BIT_MAX: UInt16 = 1023
/// Sub-slices per fast frame: index 0 is the EXPOSED slice the short read sees;
/// the rest are readout DEAD-TIME the long exposure still collects.
public let S4_MS_SUB_PER_FAST: Int32 = 2
/// Cadence 64:16 — a slow (16³) frame spans this many fast (64³) frames.
public let S4_MS_FAST_PER_SLOW: Int32 = 4
/// Cadence 32:16 — a slow frame spans this many mid (32³) frames.
public let S4_MS_MID_PER_SLOW: Int32 = 2
/// Frames in the coarse 16³ stream (5 fps) in the golden mini-model.
public let S4_MS_SLOW_FRAMES: Int32 = 2
/// Frames in the fine 64³ stream (20 fps).
public let S4_MS_FAST_FRAMES: Int32 = S4_MS_SLOW_FRAMES * S4_MS_FAST_PER_SLOW // 8
/// Frames in the mid 32³ stream (10 fps).
public let S4_MS_MID_FRAMES: Int32 = S4_MS_SLOW_FRAMES * S4_MS_MID_PER_SLOW // 4
/// Total sub-slices on the finest temporal grid.
public let S4_MS_SUBSLICES: Int32 = S4_MS_FAST_FRAMES * S4_MS_SUB_PER_FAST // 16

/// Clamp a raw sample to the 10-bit ceiling (mirrors the spec's worldFromList).
/// Private helper — the Zig `inline fn clamp10` of BOTH multiscale.zig and
/// multiscale_integrate.zig (identical bodies; deduplicated here, one file).
@inline(__always)
private func clamp10(_ v: UInt16) -> UInt16 {
    return v > S4_MS_TEN_BIT_MAX ? S4_MS_TEN_BIT_MAX : v
}

/// One world sample: channel-major layout, `world[ch*SUBSLICES + s]`, clamped.
/// Returned as i64 so every read accumulates without truncation.
/// Private helper — the Zig `inline fn sample`. The `Int(UInt32(...))` index
/// conversion mirrors Zig's `@intCast(usize)` (traps on a negative index).
@inline(__always)
private func msSample(_ world: UnsafePointer<UInt16>, _ ch: Int32, _ s: Int32) -> Int64 {
    let idx = Int(UInt32(ch * S4_MS_SUBSLICES + s))
    return Int64(clamp10(world[idx]))
}

/// THE SHORT read (64³, fast): each fast frame integrates only its ON sub-slice.
@_cdecl("s4_ms_read_fast")
public func s4_ms_read_fast(_ world: UnsafePointer<UInt16>?, _ ch: Int32, _ f: Int32) -> Int64 {
    return msSample(world!, ch, S4_MS_SUB_PER_FAST * f)
}

/// THE MEDIUM read (32³): continuous integration over the mid frame's window.
@_cdecl("s4_ms_read_mid")
public func s4_ms_read_mid(_ world: UnsafePointer<UInt16>?, _ ch: Int32, _ k: Int32) -> Int64 {
    let w = world!
    let w0 = S4_MS_SUB_PER_FAST * S4_MS_MID_PER_SLOW * k
    let hi = w0 + S4_MS_SUB_PER_FAST * S4_MS_MID_PER_SLOW
    var acc: Int64 = 0
    var s = w0
    while s < hi {
        acc += msSample(w, ch, s)
        s += 1
    }
    return acc
}

/// THE LONG read (16³, slow): continuous integration over the whole slow window
/// — the ON slices AND the dead-time gaps the fast read misses.
@_cdecl("s4_ms_read_slow")
public func s4_ms_read_slow(_ world: UnsafePointer<UInt16>?, _ ch: Int32, _ j: Int32) -> Int64 {
    let w = world!
    let w0 = S4_MS_SUB_PER_FAST * S4_MS_FAST_PER_SLOW * j
    let hi = w0 + S4_MS_SUB_PER_FAST * S4_MS_FAST_PER_SLOW
    var acc: Int64 = 0
    var s = w0
    while s < hi {
        acc += msSample(w, ch, s)
        s += 1
    }
    return acc
}

/// The DERIVED estimate of the slow read: pool the fast read over its window.
/// This is what the old derived pyramid computes — and it is NOT the slow read.
@_cdecl("s4_ms_pool_fast_to_slow")
public func s4_ms_pool_fast_to_slow(_ world: UnsafePointer<UInt16>?, _ ch: Int32, _ j: Int32) -> Int64 {
    let lo = S4_MS_FAST_PER_SLOW * j
    let hi = lo + S4_MS_FAST_PER_SLOW
    var acc: Int64 = 0
    var f = lo
    while f < hi {
        acc += s4_ms_read_fast(world, ch, f)
        f += 1
    }
    return acc
}

/// The dead-time photons in a slow window = long read − pooled short reads.
/// Always >= 0; strictly positive whenever the world emits during a readout gap
/// — the exact, structural measure of how much world-information the coarse read
/// carries that the fine read cannot (Spec.lawSlowMinusPoolIsDeadTime).
@_cdecl("s4_ms_dead_time")
public func s4_ms_dead_time(_ world: UnsafePointer<UInt16>?, _ ch: Int32, _ j: Int32) -> Int64 {
    return s4_ms_read_slow(world, ch, j) - s4_ms_pool_fast_to_slow(world, ch, j)
}

// ═════════════════════════════════════════════════════════════════════════════
//  multiscale_integrate.zig — THE INTEGRATOR: assemble the three INDEPENDENT
//  volumes from the raw laddered capture. DEPENDENCY-FREE: imports nothing,
//  pure integer, C ABI, i64 carrier, i32 rc (0 == ok). Byte-exact twin of
//  Spec.MultiScaleIntegrate.
//
//  INDEPENDENCE IS PHYSICAL, BY CONSERVATION: a photon is absorbed once, so the
//  interleaved exposure ladder ALLOCATES each raw sub-exposure to exactly one
//  scale (the `owner` array — the device's real interleaving pattern; any total
//  assignment is a valid disjoint cover). Each scale's volume is the exact i64
//  sum of the sub-exposures it OWNS — disjoint photons, so no scale's volume is
//  a function of another's, and the three volumes sum back to the raw stream
//  (every photon counted once: Spec.lawConservesPhotons).
//
//  10-BIT × 3, ABSORBED: `photons` are u16 in 0..1023; accumulation is i64,
//  whose headroom the width contract guarantees
//  (Spec.lawIntegrateCarrierWidthSuffices). `n_scales` volumes come out;
//  `photons` is laid out cell-major (`photons[cell*n_subslices + s]`),
//  `owner[s]` names the scale of sub-slice s, `out[scale*n_cells + cell]`
//  receives the integrated volume.
// ═════════════════════════════════════════════════════════════════════════════

// Per-file RC constants of BOTH multiscale_integrate.zig and render_select.zig
// (each Zig file declares its own identical pair; deduplicated here because both
// files land in this one Swift file). multiscale_integrate.zig also re-declares
// its own private `TEN_BIT_MAX: u16 = 1023` — served here by S4_MS_TEN_BIT_MAX
// (same value) through the shared `clamp10` above.
private let RC_OK: Int32 = 0
private let RC_BAD_ARGS: Int32 = 1

/// Integrate the raw sub-exposure stream into `n_scales` per-cell volumes by the
/// `owner` disjoint schedule. `out` must have `n_scales * n_cells` i64 slots.
/// Returns RC_BAD_ARGS on non-positive sizes or an out-of-range owner.
@_cdecl("s4_multiscale_integrate")
public func s4_multiscale_integrate(
    _ out: UnsafeMutablePointer<Int64>?,
    _ photons: UnsafePointer<UInt16>?,
    _ owner: UnsafePointer<Int32>?,
    _ n_scales: Int32,
    _ n_cells: Int32,
    _ n_subslices: Int32
) -> Int32 {
    if n_scales <= 0 || n_cells <= 0 || n_subslices <= 0 { return RC_BAD_ARGS }
    let o = out!
    let ph = photons!
    let ow = owner!
    let ns = Int(n_scales)
    let nc = Int(n_cells)
    let nsub = Int(n_subslices)

    // every owner must name a valid scale (else the partition is malformed).
    var s = 0
    while s < nsub {
        if ow[s] < 0 || ow[s] >= n_scales { return RC_BAD_ARGS }
        s += 1
    }

    // zero the output volumes.
    var i = 0
    while i < ns * nc {
        o[i] = 0
        i += 1
    }

    // accumulate: each sub-slice adds into its OWNED scale's volume, per cell.
    var cell = 0
    while cell < nc {
        s = 0
        while s < nsub {
            let scale = Int(ow[s]) // validated above; Zig @intCast(usize)
            let v = Int64(clamp10(ph[cell * nsub + s]))
            o[scale * nc + cell] += v
            s += 1
        }
        cell += 1
    }
    return RC_OK
}

// ═════════════════════════════════════════════════════════════════════════════
//  render_select.zig — THE SELECT RENDER (rung 1 of The Loom): the byte-exact
//  Zig twin of Spec.RenderSelect. DEPENDENCY-FREE: imports nothing, pure
//  integer, C ABI, i32 rc (0 == ok), caller owns all memory.
//
//  Given THREE INDEPENDENT volumes — V16 (side/4), V32 (side/2), V64 (side) —
//  and a per-region depth field (one depth 0/1/2 per 4×4×4 region = the 16³
//  paint grid), fill the `side`³ output so each region shows its CHOSEN scale's
//  OWN measurement, block-replicated on the shared 4:2:1 clock (a depth-0 voxel
//  is a 4×4×4 spacetime block of the coarse read; depth-1 a 2×2×2 of the mid;
//  depth-2 a single fine voxel).
//
//  SELECT, NOT POOL (the independence-preserving distinction): this reads V_d
//  DIRECTLY — a coarse region is the long-exposure measurement itself, untouched
//  by V64 (Spec.lawSelectReadsChosenSourceOnly). It never pools the fine volume,
//  so the coarse pixels stay what the outside world gave them. `side` is the
//  device output (64 in the app; the golden uses 8 to match the spec exactly);
//  it must be a positive multiple of 4.
// ═════════════════════════════════════════════════════════════════════════════

/// Private helper — the Zig `inline fn clampDepth`.
@inline(__always)
private func clampDepth(_ d: Int32) -> Int32 {
    return d < 0 ? 0 : (d > 2 ? 2 : d)
}

/// The spacetime block a depth-d region replicates: 4 (V16), 2 (V32), 1 (V64).
/// Private helper — the Zig `inline fn blockSide`.
@inline(__always)
private func blockSide(_ d: Int32) -> Int {
    switch d {
    case 0: return 4
    case 1: return 2
    default: return 1
    }
}

/// Fill `out[side^3]` by per-region select from the three independent volumes.
/// `v16` is (side/4)³, `v32` is (side/2)³, `v64` is side³; `depth` is one value
/// per 4×4×4 region, region-major over the (side/4)³ region grid.
/// (Zig `@mod(side, 4)` is reached only for side >= 4, where it equals `%`.)
@_cdecl("s4_render_select")
public func s4_render_select(
    _ out: UnsafeMutablePointer<Int32>?,
    _ v16: UnsafePointer<Int32>?,
    _ v32: UnsafePointer<Int32>?,
    _ v64: UnsafePointer<Int32>?,
    _ depth: UnsafePointer<Int32>?,
    _ side: Int32
) -> Int32 {
    if side < 4 || side % 4 != 0 { return RC_BAD_ARGS }
    let o = out!
    let p16 = v16!
    let p32 = v32!
    let p64 = v64!
    let dp = depth!
    let n = Int(side)
    let rgs = n / 4 // region grid side (= the 16³ paint grid at device scale)

    var t = 0
    while t < n {
        var y = 0
        while y < n {
            var x = 0
            while x < n {
                let region = ((t / 4) * rgs + (y / 4)) * rgs + (x / 4)
                let d = clampDepth(dp[region])
                let b = blockSide(d)
                let srcSide = n / b
                let si = ((t / b) * srcSide + (y / b)) * srcSide + (x / b)
                switch d {
                case 0: o[(t * n + y) * n + x] = p16[si]
                case 1: o[(t * n + y) * n + x] = p32[si]
                default: o[(t * n + y) * n + x] = p64[si]
                }
                x += 1
            }
            y += 1
        }
        t += 1
    }
    return RC_OK
}
