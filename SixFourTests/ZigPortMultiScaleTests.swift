//  ZigPortMultiScaleTests.swift
//  Swift ports (2026-07-06) of the Zig host tests gating the multiscale slice:
//    * Native/src/multiscale_test.zig          → MultiScaleCaptureTests
//    * Native/src/multiscale_integrate_test.zig → MultiScaleIntegrateTests
//    * Native/src/render_select_test.zig       → RenderSelectTests
//    * Native/src/synth.zig inline tests       → SynthBurstTests (the
//      self-contained ones; the two end-to-end tests that drive
//      s4_quantize_frame/s4_palette_oklab_to_srgb8/s4_gif_assemble/s4_gif_decode
//      belong to the kernels.zig slice and stay gated there).
//
//  NOT ported here: Native/src/temporal_fixture_test.zig — it gates
//  s4_haar_split_level / s4_haar_join_level (kernels.zig Haar kernels), which
//  are OUTSIDE the multiscale/integrate/render_select/synth slice.
//
//  Every assertion is integer-EXACT (no tolerance), mirroring the Zig tests
//  byte for byte.

import Testing
@testable import SixFour

// ── shared deterministic worlds (the Zig tests' LCG helpers) ─────────────────

/// multiscale_test.zig `lcgWorld` / multiscale_integrate_test.zig `lcg`: each
/// sample a raw u16 in 0..2047 (exercises the 10-bit clamp).
private func lcgU16(_ buf: inout [UInt16], _ seed0: UInt64) {
    var s = seed0
    for i in buf.indices {
        s = s &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        buf[i] = UInt16((s >> 40) & 0x7ff)
    }
}

/// render_select_test.zig `lcg`: i32 samples in 0..0xffff.
private func lcgI32(_ buf: inout [Int32], _ seed0: UInt64) {
    var s = seed0
    for i in buf.indices {
        s = s &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        buf[i] = Int32((s >> 40) & 0xffff)
    }
}

// ═════════════════════════════════════════════════════════════════════════════
//  multiscale_test.zig — byte-exact twin of Spec.MultiScaleCapture.
// ═════════════════════════════════════════════════════════════════════════════

struct MultiScaleCaptureTests {

    /// CHANS * SUBSLICES == 48 world samples.
    private static let N = Int(S4_MS_CHANS * S4_MS_SUBSLICES)

    @Test func keystoneSlowMinusPoolIsDeadTimeAndNonNegative() {
        var seed: UInt64 = 0x5158_464F_5552_3634
        for _ in 0..<64 {
            var world = [UInt16](repeating: 0, count: Self.N)
            lcgU16(&world, seed)
            seed &+= 0x9E37_79B9_7F4A_7C15
            for ch in 0..<S4_MS_CHANS {
                for j in 0..<S4_MS_SLOW_FRAMES {
                    let slow = s4_ms_read_slow(world, ch, j)
                    let pool = s4_ms_pool_fast_to_slow(world, ch, j)
                    let dead = s4_ms_dead_time(world, ch, j)
                    #expect(slow - pool == dead)
                    #expect(dead >= 0)
                }
            }
        }
    }

    @Test func notDerivablePhotonInAReadoutGapMakesSlowDifferFromPool() {
        // World is all zero except one photon in sub-slice 1 (a gap:
        // 1 % SUB_PER_FAST != 0), channel 0.
        var world = [UInt16](repeating: 0, count: Self.N)
        world[1] = 500
        #expect(s4_ms_read_slow(world, 0, 0) == 500)
        #expect(s4_ms_pool_fast_to_slow(world, 0, 0) == 0)
        #expect(s4_ms_read_slow(world, 0, 0) != s4_ms_pool_fast_to_slow(world, 0, 0))
    }

    @Test func informationAddSameFastReadDifferentSlowRead() {
        let w1 = [UInt16](repeating: 0, count: Self.N)
        var w2 = [UInt16](repeating: 0, count: Self.N)
        w2[1] = 500 // differ ONLY on a gap sub-slice the fast read never integrates

        // Fast reads identical across every channel/frame.
        for ch in 0..<S4_MS_CHANS {
            for f in 0..<S4_MS_FAST_FRAMES {
                #expect(s4_ms_read_fast(w1, ch, f) == s4_ms_read_fast(w2, ch, f))
            }
        }
        // Slow reads differ — the coarse scale carries info the fine scale lacks.
        #expect(s4_ms_read_slow(w1, 0, 0) != s4_ms_read_slow(w2, 0, 0))
    }

    @Test func tenBitTimesThreeAbsorbedCeilingWorldExactIntegerSums() {
        let world = [UInt16](repeating: S4_MS_TEN_BIT_MAX, count: Self.N)
        let maxV = Int64(S4_MS_TEN_BIT_MAX)
        for ch in 0..<S4_MS_CHANS {
            // fast = 1 slice at the ceiling
            for f in 0..<S4_MS_FAST_FRAMES {
                #expect(s4_ms_read_fast(world, ch, f) == maxV)
            }
            // mid = (SUB_PER_FAST * MID_PER_SLOW) slices
            let midExpect = Int64(S4_MS_SUB_PER_FAST * S4_MS_MID_PER_SLOW) * maxV
            for k in 0..<S4_MS_MID_FRAMES {
                #expect(s4_ms_read_mid(world, ch, k) == midExpect)
            }
            // slow = (SUB_PER_FAST * FAST_PER_SLOW) slices
            let slowExpect = Int64(S4_MS_SUB_PER_FAST * S4_MS_FAST_PER_SLOW) * maxV
            for j in 0..<S4_MS_SLOW_FRAMES {
                #expect(s4_ms_read_slow(world, ch, j) == slowExpect)
            }
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
//  multiscale_integrate_test.zig — byte-exact twin of Spec.MultiScaleIntegrate
//  (nScales=3, nCells=3, nSubslices=12, round-robin owner s%3).
// ═════════════════════════════════════════════════════════════════════════════

struct MultiScaleIntegrateTests {

    private static let nsc: Int32 = 3
    private static let nc: Int32 = 3
    private static let nsub: Int32 = 12

    /// Round-robin owner s % 3 (the Zig `rrOwner`).
    private func rrOwner() -> [Int32] {
        (0..<Int(Self.nsub)).map { Int32($0 % 3) }
    }

    @Test func keystoneThreeVolumesConserveTheRawPhotons() {
        var photons = [UInt16](repeating: 0, count: 3 * 12)
        lcgU16(&photons, 42)
        let owner = rrOwner()
        var out = [Int64](repeating: 0, count: 3 * 3)

        #expect(s4_multiscale_integrate(&out, photons, owner, Self.nsc, Self.nc, Self.nsub) == 0)

        for cell in 0..<3 {
            // sum over scales
            var volSum: Int64 = 0
            for sc in 0..<3 { volSum += out[sc * 3 + cell] }
            // sum of raw photons (clamped) for this cell
            var raw: Int64 = 0
            for s in 0..<12 {
                let v = photons[cell * 12 + s]
                raw += Int64(v > 1023 ? 1023 : v)
            }
            #expect(raw == volSum)
        }
    }

    @Test func independenceAScalesVolumeUsesOnlyThePhotonsItOwns() {
        var photons = [UInt16](repeating: 0, count: 3 * 12)
        lcgU16(&photons, 7)
        let owner = rrOwner()

        var a = [Int64](repeating: 0, count: 3 * 3)
        var b = [Int64](repeating: 0, count: 3 * 3)
        _ = s4_multiscale_integrate(&a, photons, owner, Self.nsc, Self.nc, Self.nsub)

        // bump sub-slice 1 (owned by scale 1) in every cell; scales 0 and 2 unchanged.
        var photons2 = photons
        for cell in 0..<3 {
            let idx = cell * 12 + 1
            photons2[idx] = photons2[idx] < 900 ? photons2[idx] + 100 : photons2[idx]
        }
        _ = s4_multiscale_integrate(&b, photons2, owner, Self.nsc, Self.nc, Self.nsub)

        for cell in 0..<3 {
            #expect(a[0 * 3 + cell] == b[0 * 3 + cell]) // scale 0 untouched
            #expect(a[2 * 3 + cell] == b[2 * 3 + cell]) // scale 2 untouched
        }
    }

    @Test func tenBitTimesThreeAbsorbedCeilingStreamIsOwnedCountTimes1023() {
        let photons = [UInt16](repeating: 1023, count: 3 * 12)
        let owner = rrOwner()
        var out = [Int64](repeating: 0, count: 3 * 3)
        _ = s4_multiscale_integrate(&out, photons, owner, Self.nsc, Self.nc, Self.nsub)

        // round-robin over 12 sub-slices ⇒ each scale owns exactly 4.
        for sc in 0..<3 {
            for cell in 0..<3 {
                #expect(out[sc * 3 + cell] == Int64(4 * 1023))
            }
        }
    }

    @Test func malformedOwnerOutOfRangeIsRefused() {
        let photons = [UInt16](repeating: 0, count: 3 * 12)
        var owner = [Int32](repeating: 0, count: 12)
        owner[3] = 9 // no such scale
        var out = [Int64](repeating: 0, count: 3 * 3)
        #expect(s4_multiscale_integrate(&out, photons, owner, Self.nsc, Self.nc, Self.nsub) == 1)
    }
}

// ═════════════════════════════════════════════════════════════════════════════
//  render_select_test.zig — byte-exact twin of Spec.RenderSelect (side = 8, the
//  spec's miniature 64³).
// ═════════════════════════════════════════════════════════════════════════════

struct RenderSelectTests {

    private static let side: Int32 = 8
    private static let n = 8
    private static let nreg = 2 * 2 * 2 // (side/4)^3 regions

    @Test func depth2EverywhereIsTheFineIdentity() {
        var v16 = [Int32](repeating: 0, count: 2 * 2 * 2)
        var v32 = [Int32](repeating: 0, count: 4 * 4 * 4)
        var v64 = [Int32](repeating: 0, count: Self.n * Self.n * Self.n)
        lcgI32(&v16, 1)
        lcgI32(&v32, 2)
        lcgI32(&v64, 3)
        let depth = [Int32](repeating: 2, count: Self.nreg)
        var out = [Int32](repeating: 0, count: Self.n * Self.n * Self.n)

        #expect(s4_render_select(&out, v16, v32, v64, depth, Self.side) == 0)
        #expect(out == v64)
    }

    @Test func depth0EverywhereIsV16ReplicatedIndependentOfV64() {
        // V16 distinct per coarse cell; V64 all a different constant → proves not a pool.
        var v16 = [Int32](repeating: 0, count: 2 * 2 * 2)
        for i in v16.indices { v16[i] = Int32(i) + 100 }
        let v32 = [Int32](repeating: 0, count: 4 * 4 * 4)
        let v64 = [Int32](repeating: -7, count: Self.n * Self.n * Self.n) // pool(V64) = -7 ≠ any V16
        let depth = [Int32](repeating: 0, count: Self.nreg)
        var out = [Int32](repeating: 0, count: Self.n * Self.n * Self.n)

        #expect(s4_render_select(&out, v16, v32, v64, depth, Self.side) == 0)
        for t in 0..<Self.n {
            for y in 0..<Self.n {
                for x in 0..<Self.n {
                    let si = ((t / 4) * 2 + (y / 4)) * 2 + (x / 4)
                    #expect(out[(t * Self.n + y) * Self.n + x] == v16[si])
                }
            }
        }
    }

    @Test func keystoneAllCoarseOutputIsInvariantToV64() {
        var v16 = [Int32](repeating: 0, count: 2 * 2 * 2)
        var v32 = [Int32](repeating: 0, count: 4 * 4 * 4)
        lcgI32(&v16, 11)
        lcgI32(&v32, 12)
        var v64a = [Int32](repeating: 0, count: Self.n * Self.n * Self.n)
        lcgI32(&v64a, 13)
        var v64b = [Int32](repeating: 0, count: Self.n * Self.n * Self.n)
        for i in v64b.indices { v64b[i] = v64a[i] + 1 } // a genuinely different V64
        let depth = [Int32](repeating: 0, count: Self.nreg)
        var outA = [Int32](repeating: 0, count: Self.n * Self.n * Self.n)
        var outB = [Int32](repeating: 0, count: Self.n * Self.n * Self.n)

        _ = s4_render_select(&outA, v16, v32, v64a, depth, Self.side)
        _ = s4_render_select(&outB, v16, v32, v64b, depth, Self.side)
        #expect(outA == outB)
    }

    @Test func badSideNotAMultipleOf4IsRefused() {
        let one: [Int32] = [0]
        var out: [Int32] = [0]
        #expect(s4_render_select(&out, one, one, one, one, 6) == 1)
    }
}

// ═════════════════════════════════════════════════════════════════════════════
//  synth.zig inline tests — the self-contained ones (seed determinism is the
//  whole point of the synth engine). The "synth → quantize → palette →
//  assemble" and "SOLID round-trip" tests exercise kernels.zig exports and stay
//  with that slice.
// ═════════════════════════════════════════════════════════════════════════════

struct SynthBurstTests {

    @Test func synthBurstIsDeterministicInTheSeed() {
        let fc: Int32 = 4
        let side: Int32 = 8
        let n = Int(fc * side * side * 3)
        var a = [Int32](repeating: 0, count: n)
        var b = [Int32](repeating: 0, count: n)
        #expect(s4_synth_burst(12345, S4_SYNTH_COLOR, fc, side, S4_SYNTH_L_MIN, S4_SYNTH_L_MAX, S4_SYNTH_CHROMA, &a) == 0)
        #expect(s4_synth_burst(12345, S4_SYNTH_COLOR, fc, side, S4_SYNTH_L_MIN, S4_SYNTH_L_MAX, S4_SYNTH_CHROMA, &b) == 0)
        #expect(a == b)
        // A different seed must change the output.
        var c = [Int32](repeating: 0, count: n)
        #expect(s4_synth_burst(12346, S4_SYNTH_COLOR, fc, side, S4_SYNTH_L_MIN, S4_SYNTH_L_MAX, S4_SYNTH_CHROMA, &c) == 0)
        #expect(a != c)
    }

    @Test func grayscaleModeEmitsExactZeroChromaAndLInRange() {
        let fc: Int32 = 4
        let side: Int32 = 8
        let p = Int(side * side)
        let n = Int(fc) * p * 3
        var out = [Int32](repeating: 0, count: n)
        #expect(s4_synth_burst(777, S4_SYNTH_GRAYSCALE, fc, side, S4_SYNTH_L_MIN, S4_SYNTH_L_MAX, S4_SYNTH_CHROMA, &out) == 0)
        for i in 0..<(Int(fc) * p) {
            let l = out[i * 3 + 0]
            #expect(l >= 0 && l <= S4_Q16_ONE)
            #expect(out[i * 3 + 1] == 0)
            #expect(out[i * 3 + 2] == 0)
        }
    }

    @Test func framesDifferAndChromaStaysInGamut() {
        let fc: Int32 = 8
        let side: Int32 = 16
        let p = Int(side * side)
        let n = Int(fc) * p * 3
        var out = [Int32](repeating: 0, count: n)
        #expect(s4_synth_burst(2024, S4_SYNTH_COLOR, fc, side, S4_SYNTH_L_MIN, S4_SYNTH_L_MAX, S4_SYNTH_CHROMA, &out) == 0)

        // Frame 0 and the midpoint frame must differ (the triangle wave moved A→B).
        let f0 = Array(out[0..<(p * 3)])
        let mid = Int(fc) / 2
        let fm = Array(out[(mid * p * 3)..<((mid + 1) * p * 3)])
        #expect(f0 != fm)

        // a,b within the declared Q16 chroma bound.
        let half = S4_Q16_ONE / 2
        for i in 0..<(Int(fc) * p) {
            #expect(out[i * 3 + 1] >= -half && out[i * 3 + 1] <= half)
            #expect(out[i * 3 + 2] >= -half && out[i * 3 + 2] <= half)
        }
    }

    @Test func z6NarrowLDynamicRangeStillYieldsAtLeastKDistinctLevels() {
        // A grey range of just [0.40, 0.45]. With the OLD fixed grain a span this
        // narrow could collapse below 256 distinct quantisable levels and break
        // significance; range-proportional grain keeps ≥ K=256 distinct L values
        // in a 64×64 frame.
        let side: Int32 = 64
        let p = Int(side * side)
        let lMin: Int32 = 26214 // ≈0.40
        let lMax: Int32 = 29491 // ≈0.45

        var burst = [Int32](repeating: 0, count: p * 3)
        #expect(s4_synth_burst(31337, S4_SYNTH_GRAYSCALE, 1, side, lMin, lMax, 0, &burst) == 0)

        var ls = [Int32](repeating: 0, count: p)
        for i in 0..<p { ls[i] = burst[i * 3] }
        ls.sort()
        // every L stays inside the requested dynamic range
        #expect(ls[0] >= lMin && ls[p - 1] <= lMax)
        var distinct = 1
        for i in 1..<p where ls[i] != ls[i - 1] { distinct += 1 }
        #expect(distinct >= 256)
    }

    @Test func synthBurstRejectsAnInvalidDynamicRange() {
        var out = [Int32](repeating: 0, count: 4 * 3) // side=2 ⇒ 4 px
        // rc 2 == kernels.RC_BAD_SHAPE
        // l_max ≤ l_min
        #expect(s4_synth_burst(1, S4_SYNTH_GRAYSCALE, 1, 2, 30000, 30000, 0, &out) == 2)
        // l_max > Q16
        #expect(s4_synth_burst(1, S4_SYNTH_COLOR, 1, 2, 0, 70000, 0, &out) == 2)
        // chroma_max out of range
        #expect(s4_synth_burst(1, S4_SYNTH_COLOR, 1, 2, 0, 65536, 40000, &out) == 2)
        // negative detail scale
        #expect(s4_synth_burst_detail(1, S4_SYNTH_COLOR, 1, 2, 0, 65536, 0, -1, &out) == 2)
    }

    @Test func synthBurstDetailSpansTheDetailAxis() {
        let side: Int32 = 64
        let sd = Int(side)
        let p = sd * sd
        var lo = [Int32](repeating: 0, count: p * 3)
        var hi = [Int32](repeating: 0, count: p * 3)
        // Same seed + same L range; ONLY detail differs.
        #expect(s4_synth_burst_detail(555, S4_SYNTH_GRAYSCALE, 1, side, S4_SYNTH_L_MIN, S4_SYNTH_L_MAX, 0, S4_SYNTH_DETAIL_Q16, &lo) == 0)
        #expect(s4_synth_burst_detail(555, S4_SYNTH_GRAYSCALE, 1, side, S4_SYNTH_L_MIN, S4_SYNTH_L_MAX, 0, 8 * S4_SYNTH_DETAIL_Q16, &hi) == 0)

        // High-frequency energy = Σ |L(x+1,y) − L(x,y)| (horizontal adjacent differences).
        var elo: Int64 = 0
        var ehi: Int64 = 0
        for y in 0..<sd {
            for x in 0..<(sd - 1) {
                let px0 = (y * sd + x) * 3
                let px1 = (y * sd + x + 1) * 3
                let dlo = Int64(lo[px1]) - Int64(lo[px0])
                let dhi = Int64(hi[px1]) - Int64(hi[px0])
                elo += dlo < 0 ? -dlo : dlo
                ehi += dhi < 0 ? -dhi : dhi
            }
        }
        #expect(ehi > elo)

        // detail == DETAIL_Q16 is byte-identical to the canonical (unchanged-ABI)
        // s4_synth_burst.
        var canon = [Int32](repeating: 0, count: p * 3)
        #expect(s4_synth_burst(555, S4_SYNTH_GRAYSCALE, 1, side, S4_SYNTH_L_MIN, S4_SYNTH_L_MAX, 0, &canon) == 0)
        #expect(lo == canon)
    }
}
