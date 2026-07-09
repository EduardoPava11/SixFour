import Foundation

/// THE POUR's integer schedule — the Swift twin of `Spec.ColorTimeDisplay` (source of
/// truth: `spec/src/SixFour/Spec/ColorTimeDisplay.hs`, proven by `cabal test`).
///
/// Every cadence the live surface beats at is a THEOREM of the ladder, never a free
/// animation constant: ONE 20 Hz `SurfaceClock.tick` (1 tick = 1 weave unit = 5 cs)
/// derives the 4:2:1 rung refresh (64@20 Hz / 32@10 Hz / 16@5 Hz), the intake-tally
/// slots (2 over the 32², 4 over the 16²), the per-realize accumulator divisors
/// (1 : 8 : 64 per-voxel samples), the banked capture ledger (frame n owns raster
/// cells 4(n−1)…4n−1; 64 × 4 = 256 partitions the 16²), and the "160/320cs" banked
/// window. `InvertedPyramidField` consumes these; `ColorTimeDisplayMathTests` pins
/// them against the Haskell `goldenSchedule16` vector and the generated
/// `SixFourCellMechanics.goldenBeat` (one clock: the BEAT is the 16-rung realize).
enum ColorTimeDisplayMath {

    // MARK: the one clock — display cadence

    /// Display refresh periods in ticks for the rungs [64², 32², 16²]:
    /// `Spec.ColorTimeDisplay.displayPeriodTicks` = `unitsOf` = the pool depth.
    static let displayPeriodTicks: [Int] = [1, 2, 4]

    /// True iff a rung with refresh `period` realizes (whole-tile swap) at `tick`
    /// (`realizesAt`: t ≡ 0 mod period; total over negative ticks like the Haskell mod).
    @inline(__always)
    static func realizesAt(period: Int, tick: Int) -> Bool {
        ((tick % period) + period) % period == 0
    }

    // MARK: the temporal integral

    /// Fine frames one realize integrates per rung [64², 32², 16²] (= `unitsOf`):
    /// Daniel's equivalence made exact — FOUR 64² frames pour into ONE 16² update.
    static let framesPerRealize: [Int] = [1, 2, 4]

    /// The u64-accumulator divisor at a realize per rung: spatial pool area × frames
    /// = (2^k)³ — the 1 : 8 : 64 per-voxel-samples ladder (`lawRealizeSamplesLadder`).
    static let realizeSamples: [Int] = [1, 8, 64]

    // MARK: the gathering beat — intake tallies

    /// Which tally slot `tick` fills on a rail of `slots` slots (`tallySlot`).
    @inline(__always)
    static func tallySlot(slots: Int, tick: Int) -> Int {
        ((tick % slots) + slots) % slots
    }

    // MARK: the banked capture ledger

    /// The burst length in frames (= ticks = weave units): `Spec.WeaveOrder.windowUnits`.
    static let burstFrames = 64

    /// Raster cells of the 16² ledger each landed frame owns permanently: 4 — BOTH
    /// 16²/64 AND `unitsOf W16` (`lawLedgerConserves` proves the derivations agree).
    static let ledgerCellsPerFrame = 4

    /// The 16² raster cells landed frame `n` (1-based) takes, permanently:
    /// `[4(n−1) ..< 4n]` — each 4-cell strip is a time-woven sample, 5 cs apart.
    @inline(__always)
    static func ledgerCells(_ n: Int) -> Range<Int> {
        (ledgerCellsPerFrame * (n - 1)) ..< (ledgerCellsPerFrame * n)
    }

    /// Filled ledger cells after `landed` frames — the shutter fill as an EXACT
    /// function of banked frames (never float progress), clamped (`lawLedgerStepExact`).
    @inline(__always)
    static func ledgerFillCount(_ landed: Int) -> Int {
        ledgerCellsPerFrame * min(burstFrames, max(0, landed))
    }

    /// The banked window in centiseconds after `landed` frames: 5·landed, to 320 at
    /// the full burst (`lawBankedWindowExact` — the "160/320cs" overlay is a readout
    /// of this function, never an animation).
    @inline(__always)
    static func bankedWindowCs(_ landed: Int) -> Int {
        5 * min(burstFrames, max(0, landed))
    }

    /// The full burst's banked window: 320 cs (`Spec.WeaveOrder.windowCs`).
    static let fullWindowCs = 320

    // MARK: the flux-bar quantizer (E6 — the display math, pinned ahead of its wiring)

    /// Lit flux-bar cells for a per-cadence palette-W1 impulse `w`: integer bit-length
    /// (log₂ scaling), clamped to 16 (`lawFluxMonotoneBounded`).
    static func fluxFillCount(_ w: Int) -> Int {
        var n = max(0, w), bits = 0
        while n > 0 { bits += 1; n >>= 1 }
        return min(16, bits)
    }

    // MARK: the golden cross-language schedule (D6)

    /// The 16-tick golden schedule mirrored VERBATIM from Haskell `goldenSchedule16`:
    /// per tick t — (t, realizesAt W32, realizesAt W16, tallySlot W32, tallySlot W16).
    /// `ColorTimeDisplayMathTests` re-derives every row from the functions above.
    static let goldenSchedule16: [(t: Int, r32: Bool, r16: Bool, s32: Int, s16: Int)] = [
        (0,  true,  true,  0, 0), (1,  false, false, 1, 1),
        (2,  true,  false, 0, 2), (3,  false, false, 1, 3),
        (4,  true,  true,  0, 0), (5,  false, false, 1, 1),
        (6,  true,  false, 0, 2), (7,  false, false, 1, 3),
        (8,  true,  true,  0, 0), (9,  false, false, 1, 1),
        (10, true,  false, 0, 2), (11, false, false, 1, 3),
        (12, true,  true,  0, 0), (13, false, false, 1, 1),
        (14, true,  false, 0, 2), (15, false, false, 1, 3),
    ]
}
