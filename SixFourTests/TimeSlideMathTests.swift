//  TimeSlideMathTests.swift
//  Golden-parity gate for THE TIME SLIDE's hand-written display math.
//
//  The authority is the Haskell spec: `Spec.TimeSlide` (11 laws, proven by
//  `cabal test`). The cross-language goldens (`goldenPlayhead16`,
//  `goldenVolumeQ16`, `goldenIntegralQ16`) and the negative-operand
//  round-half-up vectors are mirrored here VERBATIM from the spec's property
//  battery (spec/test/Properties/TimeSlide.hs, 2026-07-10). The convention
//  pin re-derives the group-change ticks from
//  `ColorTimeDisplayMath.goldenSchedule16` — the poured window ENDS at the
//  realize tick (`lawGroupWindowIsPouredWindow`), so a drifted port shifts
//  the 32/16 detents one frame and fails here.

import XCTest
@testable import SixFour

final class TimeSlideMathTests: XCTestCase {

    // MARK: The cross-language goldens

    /// `goldenPlayhead16` re-derived row by row: 48 rows (k ∈ 0…2 × t ∈ 0…15,
    /// anchor 0/0), frame = t, group = t div 2^k, realizes ⇔ t ≡ 0 mod 2^k —
    /// the exact closed form the Haskell battery pins.
    func testGoldenPlayhead16() {
        var i = 0
        for k in 0 ... 2 {
            for t in 0 ... 15 {
                let row = TimeSlideMath.goldenPlayhead16[i]
                XCTAssertEqual(row.k, k)
                XCTAssertEqual(row.t, t)
                XCTAssertEqual(row.frame, t, "playhead frame at k=\(k) t=\(t)")
                XCTAssertEqual(row.group, t / (1 << k), "display group at k=\(k) t=\(t)")
                XCTAssertEqual(row.realizes, t % (1 << k) == 0, "realize at k=\(k) t=\(t)")
                i += 1
            }
        }
        XCTAssertEqual(TimeSlideMath.goldenPlayhead16.count, 48)
    }

    /// `goldenIntegralQ16` == the hand-derived literals from the Haskell
    /// battery: identity at k=0, the pair-integrals at k=1, the whole-window
    /// integral at k=2 — all over NEGATIVE Q16 a/b channels (the rounding
    /// vectors a truncating port trips on).
    func testGoldenIntegralQ16() {
        let expected: [[[Int64]]] = [
            TimeSlideMath.goldenVolumeQ16,
            [[5, -3, 2, -5, 1, 8, 2, -1, 6, -6, 4, -2],
             [6, -5, 4, -5, 3, 10, 4, -3, 4, -8, 6, -4]],
            [[6, -4, 3, -5, 2, 9, 3, -2, 5, -7, 5, -3]],
        ]
        XCTAssertEqual(TimeSlideMath.goldenIntegralQ16.count, 3)
        for (k, groups) in TimeSlideMath.goldenIntegralQ16 {
            XCTAssertEqual(groups, expected[k], "integral groups at k=\(k)")
        }
        // The a/b channels are genuinely signed (the golden-volume witness).
        XCTAssertTrue(TimeSlideMath.goldenVolumeQ16.allSatisfy { $0.contains { $0 < 0 } })
    }

    // MARK: Round-half-up over negatives (`lawDivRoundHalfUpNegatives`)

    /// The pinned negative-operand vectors: halves round toward +∞ on BOTH
    /// signs; `(−5)/4 → −1` separates floor (`div`) from truncation (`quot` —
    /// a truncating port answers 0); plain floor division is NOT
    /// round-half-up (−3 div 2 = −2 ≠ −1).
    func testDivRoundHalfUpNegatives() {
        XCTAssertEqual([-3, -1, 1, 3].map { TimeSlideMath.divRoundHalfUp($0, 2) },
                       [-1, 0, 1, 2])
        XCTAssertEqual([-7, -6, -5, -2, 2, 5, 6, 7].map { TimeSlideMath.divRoundHalfUp($0, 4) },
                       [-2, -1, -1, 0, 1, 1, 2, 2])
        XCTAssertEqual(TimeSlideMath.divRoundHalfUp(-5, 4), -1)
        XCTAssertEqual(TimeSlideMath.floorDiv(-3, 2), -2)   // floor ≠ round-half-up
        XCTAssertEqual(TimeSlideMath.divRoundHalfUp(-3, 2), -1)
        // Totality: non-positive divisors answer 0.
        XCTAssertEqual(TimeSlideMath.divRoundHalfUp(7, 0), 0)
        XCTAssertEqual(TimeSlideMath.divRoundHalfUp(7, -2), 0)
    }

    /// Quantified round-half-up correctness on a vector sweep:
    /// 2nq − n ≤ 2s < 2nq + n (the exact characterisation the spec's
    /// QuickCheck battery proves over all s, n ≥ 1).
    func testDivRoundHalfUpCharacterisation() {
        for s in stride(from: Int64(-1000), through: 1000, by: 7) {
            for n in [Int64(1), 2, 3, 4, 5, 8, 64] {
                let q = TimeSlideMath.divRoundHalfUp(s, n)
                XCTAssertTrue(2 * n * q - n <= 2 * s && 2 * s < 2 * n * q + n,
                              "s=\(s) n=\(n) q=\(q)")
            }
        }
    }

    // MARK: The convention pin (`lawGroupWindowIsPouredWindow` on device)

    /// Group-change ticks re-derived from `goldenSchedule16`'s r32/r16
    /// columns: with the anchor at (0,0), the display group at detent 1/2
    /// steps between t−1 and t EXACTLY when the golden schedule realizes W32/
    /// W16 at t. A port that read the window as STARTING at the realize tick
    /// would ship the coarse detents one frame off and fail here.
    func testGroupChangeTicksMatchGoldenSchedule16() {
        for row in ColorTimeDisplayMath.goldenSchedule16 {
            let t = row.t
            for (k, realizes) in [(1, row.r32), (2, row.r16)] {
                let now = TimeSlideMath.displayGroup(k: k, anchorTick: 0,
                                                     anchorFrame: 0, tick: t)
                let before = TimeSlideMath.displayGroup(k: k, anchorTick: 0,
                                                        anchorFrame: 0, tick: t - 1)
                XCTAssertEqual(now != before, realizes,
                               "group step at k=\(k) t=\(t)")
            }
        }
    }

    /// The realized frame is the group's END frame (the poured window ENDS at
    /// the realize tick): at detent k, group j ends on frame j·2^k + 2^k − 1.
    func testGroupEndFrameIsThePouredWindowEnd() {
        XCTAssertEqual(TimeSlideMath.groupEndFrame(group: 0, k: 2), 3)
        XCTAssertEqual(TimeSlideMath.groupEndFrame(group: 3, k: 2), 15)
        XCTAssertEqual(TimeSlideMath.groupEndFrame(group: 5, k: 1), 11)
        XCTAssertEqual(TimeSlideMath.groupEndFrame(group: 63, k: 0), 63)
    }

    // MARK: Detents are rungs (`lawDetentsAreRungs` / `lawLoopWallTimeInvariant`)

    /// The detent periods ARE `ColorTimeDisplayMath.displayPeriodTicks` (one
    /// integer, delegated — never a second cadence truth), and the detent
    /// delays ARE the kernel's time law: `s4_ladder_delay_cs(64/32/16)` =
    /// 5/10/20 cs. Wall time is invariant: frames × delay = 320 cs at every
    /// detent.
    func testDetentConstantsAreTheLadder() {
        XCTAssertEqual((0 ... 2).map(TimeSlideMath.periodOf),
                       ColorTimeDisplayMath.displayPeriodTicks)
        for k in 0 ... 2 {
            let side = Int32(TimeSlideMath.coarseSide(k))
            XCTAssertEqual(Int32(TimeSlideMath.delayCsOf(k)), s4_ladder_delay_cs(side))
            XCTAssertEqual((TimeSlideMath.windowUnits / TimeSlideMath.periodOf(k))
                            * TimeSlideMath.delayCsOf(k),
                           TimeSlideMath.windowCs)
        }
        XCTAssertEqual(s4_ladder_delay_cs(64), 5)
        XCTAssertEqual(s4_ladder_delay_cs(32), 10)
        XCTAssertEqual(s4_ladder_delay_cs(16), 20)
        XCTAssertEqual(TimeSlideMath.windowCs, 320)
        // The two-sided readout vocabulary (side − exact GCE delay).
        XCTAssertEqual((0 ... 2).map(TimeSlideMath.readoutLabel),
                       ["64 - 5cs", "32 - 10cs", "16 - 20cs"])
    }

    /// The seductive 3-tick delay is REFUSED: 64 mod 3 ≠ 0 (a uniform 3-tick
    /// cadence cannot tile the window — off-ladder dilation is a different,
    /// honestly-labelled mechanic, never a detent), while every lawful period
    /// tiles it exactly.
    func testThreeTickDelayIsRefused() {
        XCTAssertNotEqual(TimeSlideMath.windowUnits % 3, 0)
        for k in 0 ... 2 {
            XCTAssertEqual(TimeSlideMath.windowUnits % TimeSlideMath.periodOf(k), 0)
        }
        XCTAssertEqual(Set((0 ... 2).map(TimeSlideMath.periodOf)), Set([1, 2, 4]))
    }

    // MARK: The detent quantizer (`lawDetentTotal/Monotone/Endpoints`)

    /// Endpoints + FLOOR semantics: zero travel holds the latch; one
    /// `cellsPerDetent` steps one rung; far travel clamps; and the negative
    /// (upward) branch crosses its first detent ONE CELL IN (Haskell `div`
    /// floors — a truncating port waits a full 16 cells and fails here).
    func testDetentQuantizer() {
        XCTAssertEqual(TimeSlideMath.cellsPerDetent, 16)
        for k in 0 ... 2 {
            XCTAssertEqual(TimeSlideMath.detentOf(kAtLatch: k, dyCells: 0), k)
        }
        XCTAssertEqual(TimeSlideMath.detentOf(kAtLatch: 1, dyCells: 16), 2)
        XCTAssertEqual(TimeSlideMath.detentOf(kAtLatch: 1, dyCells: -16), 0)
        XCTAssertEqual(TimeSlideMath.detentOf(kAtLatch: 0, dyCells: 160), 2)
        XCTAssertEqual(TimeSlideMath.detentOf(kAtLatch: 2, dyCells: -160), 0)
        // The pinned floor-division asymmetry (spec doc: "the negative branch
        // crosses its first detent one cell in").
        XCTAssertEqual(TimeSlideMath.detentOf(kAtLatch: 1, dyCells: -1), 0)
        XCTAssertEqual(TimeSlideMath.detentOf(kAtLatch: 1, dyCells: 15), 1)
        // Totality over hostile input.
        for k in [-9, -1, 0, 1, 2, 3, 99] {
            for dy in [-1000, -17, -1, 0, 1, 17, 1000] {
                let d = TimeSlideMath.detentOf(kAtLatch: k, dyCells: dy)
                XCTAssertTrue((0 ... 2).contains(d))
            }
        }
    }

    // MARK: The device-volume integral

    /// `lawIntegralFineIsIdentity` on the interleaved 64³-shaped volume: at
    /// k=0 the integral frame IS the reconstruction slice, byte-for-byte —
    /// the 64-rung playback shows the frames untouched (the k=0 short-circuit
    /// in the hero bake is provably a no-op).
    func testIntegralFrameFineIsIdentity() {
        let frameLen = 64 * 64 * 3
        let frames = 8
        // Deterministic signed pattern (Q16 OKLab a/b run negative).
        let volume = (0 ..< frames * frameLen).map { i in
            Int32((i &* 2654435761) % 120000 - 60000)
        }
        for j in [0, 3, 7] {
            let out = TimeSlideMath.integralFrame64(volume: volume, group: j, k: 0)
            XCTAssertEqual(out, Array(volume[j * frameLen ..< (j + 1) * frameLen]),
                           "k=0 identity at group \(j)")
        }
    }

    /// `lawIntegralIsSumsDividedOnce` on the device volume: a constant window
    /// realizes to its constant (temporal divisor 2^k, applied ONCE), and the
    /// spatial ride-along divisor 8^k is provably the WRONG one (it does not
    /// return the constant). Temporal and spatial divisors never double-divide.
    func testIntegralDividesOnceByTheFrameCount() {
        let frameLen = 64 * 64 * 3
        let volume = [Int32](repeating: 5, count: 4 * frameLen)
        let out = TimeSlideMath.integralFrame64(volume: volume, group: 0, k: 2)
        XCTAssertTrue(out.allSatisfy { $0 == 5 })
        // The 8^k foil: divRoundHalfUp(5·4, 64) ≠ 5.
        XCTAssertNotEqual(TimeSlideMath.divRoundHalfUp(5 * 4, 64), 5)
        // Missing frames read 0 (totality — short volumes never trap):
        // group 1 of a 4-frame volume at k=2 sums nothing.
        let short = TimeSlideMath.integralFrame64(volume: volume, group: 1, k: 2)
        XCTAssertTrue(short.allSatisfy { $0 == 0 })
    }

    /// The generic Haskell-mirror integral agrees with the device path on the
    /// golden volume reshaped to frames × voxels.
    func testGenericAndDeviceIntegralsAgreeOnTheGolden() {
        for k in 0 ... 2 {
            let p = TimeSlideMath.periodOf(k)
            for j in 0 ..< TimeSlideMath.goldenVolumeQ16.count / p {
                let generic = TimeSlideMath.integralQ16(k: k, group: j,
                                                        volume: TimeSlideMath.goldenVolumeQ16)
                // Re-derive per voxel with divRoundHalfUp directly.
                let nVox = TimeSlideMath.goldenVolumeQ16[0].count
                let manual = (0 ..< nVox).map { v -> Int64 in
                    var s: Int64 = 0
                    for f in (j * p) ..< (j * p + p) {
                        s += TimeSlideMath.goldenVolumeQ16[f][v]
                    }
                    return TimeSlideMath.divRoundHalfUp(s, Int64(p))
                }
                XCTAssertEqual(generic, manual, "k=\(k) j=\(j)")
            }
        }
    }

    // MARK: The playhead is total

    /// `pos` is total over ticks before the anchor (the Haskell `mod` keeps
    /// it in 0…63) and wraps the 64-frame loop.
    func testPlayheadIsTotalAndWraps() {
        XCTAssertEqual(TimeSlideMath.pos(anchorTick: 0, anchorFrame: 0, tick: -1), 63)
        XCTAssertEqual(TimeSlideMath.pos(anchorTick: 10, anchorFrame: 60, tick: 20), 6)
        XCTAssertEqual(TimeSlideMath.pos(anchorTick: 0, anchorFrame: 0, tick: 64), 0)
        XCTAssertEqual(TimeSlideMath.pos(anchorTick: 5, anchorFrame: 8, tick: 5), 8)
        // The latch convention helper snaps DOWN to the group boundary.
        XCTAssertEqual(TimeSlideMath.snapToGroupStart(7, k: 2), 4)
        XCTAssertEqual(TimeSlideMath.snapToGroupStart(7, k: 1), 6)
        XCTAssertEqual(TimeSlideMath.snapToGroupStart(7, k: 0), 7)
        XCTAssertEqual(TimeSlideMath.snapToGroupStart(-3, k: 2), 0)
        XCTAssertEqual(TimeSlideMath.snapToGroupStart(99, k: 2), 60)
    }

}
