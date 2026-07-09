import Testing
import Foundation
import simd
@testable import SixFour

/// The Swift half of the D6 cross-language pin: `ColorTimeDisplayMath` (what the live
/// pyramid's cadence gating, intake tallies, and banked ledger actually consume) is
/// re-derived here and compared against the Haskell `Spec.ColorTimeDisplay` goldens —
/// the 16-tick `goldenSchedule16` vector (mirrored verbatim) and the generated
/// `SixFourCellMechanics.goldenBeat` (ONE clock: the control-face BEAT *is* the 16-rung
/// realize, `lawBeatDerivedFromOneClock`).
struct ColorTimeDisplayMathTests {

    /// The cadence ladder is the pool-depth ladder: 64@20 Hz / 32@10 Hz / 16@5 Hz,
    /// and per-realize divisors 1 : 8 : 64 (`lawDisplayCadenceIsPoolDepth` /
    /// `lawRealizeSamplesLadder`).
    @Test func cadenceIsPoolDepth() {
        #expect(ColorTimeDisplayMath.displayPeriodTicks == [1, 2, 4])
        #expect(ColorTimeDisplayMath.framesPerRealize == [1, 2, 4])
        #expect(ColorTimeDisplayMath.realizeSamples == [1, 8, 64])
        for (p, s) in zip(ColorTimeDisplayMath.displayPeriodTicks,
                          ColorTimeDisplayMath.realizeSamples) {
            #expect(p * p * p == s)   // samples = (unitsOf)³
        }
    }

    /// Every row of the mirrored `goldenSchedule16` re-derives from the live functions —
    /// the exact vector `cabal test` pins on the Haskell side.
    @Test func goldenSchedule16Rederives() {
        #expect(ColorTimeDisplayMath.goldenSchedule16.count == 16)
        for row in ColorTimeDisplayMath.goldenSchedule16 {
            #expect(ColorTimeDisplayMath.realizesAt(period: 2, tick: row.t) == row.r32)
            #expect(ColorTimeDisplayMath.realizesAt(period: 4, tick: row.t) == row.r16)
            #expect(ColorTimeDisplayMath.tallySlot(slots: 2, tick: row.t) == row.s32)
            #expect(ColorTimeDisplayMath.tallySlot(slots: 4, tick: row.t) == row.s16)
        }
    }

    /// ONE CLOCK: the generated control-face BEAT (`SixFourCellMechanics.goldenBeat`,
    /// lit on tick ≡ 0 mod 4) is EXACTLY the 16² realize predicate — the shutter
    /// heartbeats at the cadence its own frames land at (`lawBeatDerivedFromOneClock`).
    @Test func beatIsThe16RungRealize() {
        #expect(SixFourCellMechanics.beatPeriodTicks == 4)
        #expect(SixFourCellMechanics.goldenBeat.count == 16)
        for (t, beat) in SixFourCellMechanics.goldenBeat.enumerated() {
            #expect(ColorTimeDisplayMath.realizesAt(period: 4, tick: t) == beat)
        }
    }

    /// LEDGER CONSERVATION (`lawLedgerConserves` / `lawLedgerStepExact`): 64 frames ×
    /// 4 cells = 256 partitions the 16² in order; the fill is exact, monotone, clamped.
    @Test func ledgerConservesAndSteps() {
        #expect(ColorTimeDisplayMath.burstFrames * ColorTimeDisplayMath.ledgerCellsPerFrame == 256)
        var covered: [Int] = []
        for n in 1 ... 64 { covered.append(contentsOf: ColorTimeDisplayMath.ledgerCells(n)) }
        #expect(covered == Array(0 ..< 256))
        #expect(ColorTimeDisplayMath.ledgerFillCount(0) == 0)
        #expect(ColorTimeDisplayMath.ledgerFillCount(64) == 256)
        #expect(ColorTimeDisplayMath.ledgerFillCount(-3) == 0)
        #expect(ColorTimeDisplayMath.ledgerFillCount(99) == 256)
        for n in 1 ... 64 {
            #expect(ColorTimeDisplayMath.ledgerFillCount(n)
                    - ColorTimeDisplayMath.ledgerFillCount(n - 1) == 4)
        }
    }

    /// BANKED WINDOW (`lawBankedWindowExact`): 5 cs per landed frame, 160 at half,
    /// 320 at the full burst — the "160/320cs" overlay is a readout, never an animation.
    @Test func bankedWindowExact() {
        #expect(ColorTimeDisplayMath.bankedWindowCs(0) == 0)
        #expect(ColorTimeDisplayMath.bankedWindowCs(32) == 160)
        #expect(ColorTimeDisplayMath.bankedWindowCs(64) == 320)
        #expect(ColorTimeDisplayMath.bankedWindowCs(200) == ColorTimeDisplayMath.fullWindowCs)
    }

    /// FLUX QUANTIZER (`lawFluxMonotoneBounded`): bounded, zero-at-zero, monotone, log₂.
    @Test func fluxQuantizer() {
        #expect(ColorTimeDisplayMath.fluxFillCount(0) == 0)
        #expect(ColorTimeDisplayMath.fluxFillCount(1) == 1)
        #expect(ColorTimeDisplayMath.fluxFillCount(Int.max) == 16)
        var last = 0
        for w in 0 ..< 4096 {
            let f = ColorTimeDisplayMath.fluxFillCount(w)
            #expect(f >= last && f <= 16)
            last = f
        }
    }

    /// THE EQUIVALENCE, NUMERICALLY (E1): banking FOUR identical 64² frames into the 16²
    /// accumulator and dividing ONCE by 64 (16 px × 4 frames) equals the single-frame 16²
    /// pool divided by 16 — same total photons, coarser space, 4× the time. Sums compose;
    /// means never do.
    @MainActor
    @Test func fourFramePourEqualsOneFramePool() {
        // A deterministic synthetic tile through the REAL display pooling path.
        var tile = [UInt8](repeating: 0, count: 64 * 64)
        for i in 0 ..< tile.count { tile[i] = UInt8((i * 37) % 256) }
        var palette = [SIMD3<UInt8>]()
        for i in 0 ..< 256 {
            let r = UInt8(i)
            let g = UInt8(255 - i)
            let b = UInt8((i * 3) % 256)
            palette.append(SIMD3<UInt8>(r, g, b))
        }
        let s64 = InvertedPyramidField.sums64(from: tile, palette: palette)
        let s32 = ColorHead.poolSpatial2(s64, side: 64)
        let s16 = ColorHead.poolSpatial2(s32, side: 32)

        // One frame realized with count 16 (the idle pool).
        let one = InvertedPyramidField.pooledBase(sums: s16, side: 16, count: 16, gainStops: 0)
        // Four banked frames realized with count 64 (the pour).
        var acc = [UInt64](repeating: 0, count: 16 * 16 * 3)
        for _ in 0 ..< 4 { for i in 0 ..< acc.count { acc[i] &+= s16[i] } }
        let four = InvertedPyramidField.pooledBase(sums: acc, side: 16, count: 64, gainStops: 0)
        #expect(one == four)
    }

    /// THE PLACEMENT CONTRACT (the 2026-07-08 one-row-drift regression): the pyramid
    /// stack is TOP-PINNED at the `field64` contract row and its structural row
    /// offsets land EVERY band exactly on the spec-proven `liveScene` regions —
    /// field64/intake32/field32/intake16/field16. If the stack grows (a new gutter,
    /// a taller rail) without re-proving the regions, this fails loudly instead of
    /// the render silently drifting off the flanks / influence anchors by a row.
    @MainActor
    @Test func pyramidStackRowsMatchTheProvenRegions() {
        let scene = GridLayoutContract.liveScene
        func row(_ name: String) -> Int {
            GridLayoutContract.region(name, in: scene)?.row ?? .min
        }
        let top = InvertedPyramidField.contractTopRow
        typealias S = InvertedPyramidField.StackRows
        #expect(top == row("field64"))
        #expect(top + S.field64 == row("field64"))
        #expect(top + S.intake32 == row("intake32"))
        #expect(top + S.field32 == row("field32"))
        #expect(top + S.intake16 == row("intake16"))
        #expect(top + S.field16 == row("field16"))
        // The bracket ring below the 16² must clear the fluxBar row (1-row gutter).
        #expect(top + S.total <= row("fluxBar"))
        // The structural constants themselves: the proven 122-row stack.
        #expect(S.total == 122)
    }

    /// FLUX SAMPLING (E6): the palette-W1 impulse between two GCTs through the owned
    /// `s4_v21_wdist1d` kernel — identical palettes read zero flux; one slot drifting
    /// one level charges exactly 1 (ground distance); a far jump charges the span.
    @MainActor
    @Test func fluxPaletteW1SamplesTheKernel() {
        let still = [UInt8](repeating: 7, count: 768)
        #expect(FluxBar.paletteW1(still, still) == 0)
        // One slot's R channel drifts one level: W1 = 1.
        var drift = still
        drift[0] = 8
        #expect(FluxBar.paletteW1(still, drift) == 1)
        // The same slot jumps the far span: W1 charges the full ground distance.
        var jump = still
        jump[0] = 207
        #expect(FluxBar.paletteW1(still, jump) == 200)
        // Malformed inputs refuse (nil), never a fake reading.
        #expect(FluxBar.paletteW1([], still) == nil)
        // And the quantizer turns those impulses into lit cells: 0 → 0, 1 → 1, 200 → 8.
        #expect(ColorTimeDisplayMath.fluxFillCount(0) == 0)
        #expect(ColorTimeDisplayMath.fluxFillCount(1) == 1)
        #expect(ColorTimeDisplayMath.fluxFillCount(200) == 8)
    }
}
