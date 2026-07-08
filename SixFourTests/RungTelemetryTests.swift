import Testing
@testable import SixFour

/// The Swift twin of `Spec.RungTelemetry`, pinned against the spec's own
/// numbers: the arrival cadence contract, the one-vocabulary exposure law, the
/// 1:8:64 significance lattice, and the independence-health statistic with the
/// spec's EXACT derived-pool foil and dead-time-photon witness.
struct RungTelemetryTests {

    // MARK: - Arrival (lawExpectedArrivalsPinned / lawCleanCadenceIsHealthy)

    @Test func expectedArrivalsPinned() {
        #expect([64, 32, 16].map { RungTelemetryMath.expectedArrivals(side: $0) } == [64, 32, 16])
        #expect([64, 32, 16].map { RungTelemetryMath.nativeIntervalCs(side: $0) } == [5, 10, 20])
        // pulses × native interval spans exactly the 320 cs window, per rung.
        for side in [64, 32, 16] {
            #expect(RungTelemetryMath.expectedArrivals(side: side)
                    * RungTelemetryMath.nativeIntervalCs(side: side)
                    == RungTelemetryMath.windowCs)
        }
    }

    @Test func cleanCadenceIsHealthy() {
        for side in [64, 32, 16] {
            let clean = [Int](repeating: RungTelemetryMath.nativeIntervalCs(side: side),
                             count: RungTelemetryMath.expectedArrivals(side: side))
            #expect(RungTelemetryMath.lateArrivals(side: side, intervalsCs: clean) == 0)
            #expect(RungTelemetryMath.missingArrivals(side: side, intervalsCs: clean) == 0)
            #expect(clean.reduce(0, +) == RungTelemetryMath.windowCs)
        }
    }

    /// lawDroppedPulseIsDetectable: merging one pulse's interval into the next
    /// yields EXACTLY one late interval + one missing arrival, span conserved.
    @Test func droppedPulseIsDetectable() {
        for side in [64, 32, 16] {
            let native = RungTelemetryMath.nativeIntervalCs(side: side)
            var broken = [Int](repeating: native,
                               count: RungTelemetryMath.expectedArrivals(side: side))
            broken.removeFirst()
            broken[3] += native   // the dropped pulse's interval merged into the next
            #expect(RungTelemetryMath.lateArrivals(side: side, intervalsCs: broken) == 1)
            #expect(RungTelemetryMath.missingArrivals(side: side, intervalsCs: broken) == 1)
            #expect(broken.reduce(0, +) == RungTelemetryMath.windowCs)
        }
    }

    // MARK: - Exposure (lawExposureVocabulariesAgreeOnLadder)

    @Test func exposureVocabulariesAgreeOnLadder() {
        // On the light-ladder schedule (rung k exposes 2^k·Δ₀ at reference
        // gain) the optical light ratio equals the pooling-equivalent 2^k.
        for k in 0..<3 {
            for (d0, iso) in [(Int64(2_500), Int64(100_000)), (Int64(7), Int64(3))] {
                let ratio = RungTelemetryMath.opticalLightRatio(
                    durationUs: (1 << Int64(k)) * d0, iso: iso,
                    refDurationUs: d0, refIso: iso)
                #expect(ratio.num == ratio.den << Int64(k))
                #expect(RungTelemetryMath.poolingEquivalentRatio(rung: k) == 1 << Int64(k))
            }
        }
        // Degenerate reference reads 0 (no anti-photons).
        let degenerate = RungTelemetryMath.opticalLightRatio(
            durationUs: 100, iso: 100, refDurationUs: 0, refIso: 100)
        #expect(degenerate.num == 0)
        #expect(RungTelemetryMath.exposureProduct(durationUs: -5, iso: 100) == 0)
    }

    // MARK: - Significance (lawDerivedSignificanceLattice / lawRungBuysThreeBits)

    @Test func derivedSignificanceLattice() {
        let n0: Int64 = 64
        #expect((0..<3).map { RungTelemetryMath.derivedSampleVolume(rung: $0, n0: n0) }
                == [n0, 8 * n0, 64 * n0])
        for k in 0..<6 {
            #expect(RungTelemetryMath.derivedSampleVolume(rung: k + 1, n0: n0)
                    == 8 * RungTelemetryMath.derivedSampleVolume(rung: k, n0: n0))
        }
        #expect(RungTelemetryMath.derivedSampleVolume(rung: 1, n0: -3) == 0)
    }

    /// lawSignificanceSqrtMonotone: the √N order IS the N order, read on squares.
    @Test func significanceSqrtMonotone() {
        for (x, y) in [(Int64(0), Int64(0)), (3, 5), (5, 3), (7, 7), (0, 100)] {
            #expect((x <= y) == (x * x <= y * y))
        }
    }

    @Test func independentCountsMonotoneAndClamped() {
        #expect(RungTelemetryMath.independentSampleVolume([3, -2, 5]) == 8)
        #expect(RungTelemetryMath.independentSampleVolume([]) == 0)
        // Adding evidence never decreases the meter.
        #expect(RungTelemetryMath.independentSampleVolume([4, 3, 5])
                >= RungTelemetryMath.independentSampleVolume([3, 5]))
    }

    // MARK: - Independence health (poolTo / comovement / isDerivedPool)

    @Test func poolToComposesAndDropsPartialBlocks() {
        // The trailing partial block is DROPPED (exactly the Haskell chunksOf).
        #expect(RungTelemetryMath.poolTo(2, [1, 2, 3, 4, 5]) == [3, 7])
        #expect(RungTelemetryMath.poolTo(0, [1, 2, 3]) == [])
        // lawPoolCompose: poolTo c ∘ poolTo b == poolTo (b·c).
        let xs: [Int64] = [5, -1, 2, 9, 0, 3, 7, 7, 1, 4, 2, 2, 8]
        for (b, c) in [(2, 2), (3, 2), (2, 3), (4, 1)] {
            #expect(RungTelemetryMath.poolTo(c, RungTelemetryMath.poolTo(b, xs))
                    == RungTelemetryMath.poolTo(b * c, xs))
        }
    }

    /// lawDerivedPoolingIsMaximal (THE FOIL) + lawDerivedStaysMaximalUnderSharedPool.
    @Test func derivedPoolingIsMaximal() {
        let fine: [Int64] = [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5, 8, 9, 7, 9, 3]
        let coarse = RungTelemetryMath.poolTo(4, fine)
        #expect(RungTelemetryMath.comovementPermille(coarse, coarse) == 1000)
        #expect(RungTelemetryMath.comovement(RungTelemetryMath.poolTo(4, fine), coarse).total >= 2)
        #expect(RungTelemetryMath.fullyDetermined(RungTelemetryMath.poolTo(4, fine), coarse))
        #expect(RungTelemetryMath.isDerivedPool(block: 4, fine: fine, coarse: coarse))
        // Scale-equivariance: any further SHARED pool keeps the pair maximal
        // and still an exact derived pool at the composed factor.
        let pooled2 = RungTelemetryMath.poolTo(2, coarse)
        #expect(RungTelemetryMath.comovementPermille(
            RungTelemetryMath.poolTo(2, RungTelemetryMath.poolTo(4, fine)), pooled2) == 1000)
        #expect(RungTelemetryMath.isDerivedPool(block: 8, fine: fine, coarse: pooled2))
    }

    /// lawIndependentNoiseBoundedAway — the spec's EXACT witness numbers: the
    /// long read caught a mid-window dimming the short reads slept through, so
    /// one delta counter-moves and the statistic drops strictly below maximal.
    @Test func independentNoiseBoundedAwaySpecWitness() {
        let fine: [Int64] = [10, 10, 10, 10, 20, 20, 20, 20, 30, 30, 30, 30]
        let coarse: [Int64] = [40, 100, 90]
        let pooled = RungTelemetryMath.poolTo(4, fine)
        #expect(pooled == [40, 80, 120])                      // rising everywhere
        let (agree, total) = RungTelemetryMath.comovement(pooled, coarse)
        #expect(agree < total)
        #expect((agree, total) == (1, 2))                     // deltas +60, −10 vs +40, +40
        #expect(RungTelemetryMath.comovementPermille(pooled, coarse) == 500)
        #expect(!RungTelemetryMath.fullyDetermined(pooled, coarse))
        #expect(!RungTelemetryMath.isDerivedPool(block: 4, fine: fine, coarse: coarse))
    }

    /// lawDisagreementIsDetected: one sign disagreement drops the ratio below 1.
    @Test func disagreementIsDetected() {
        let a: [Int64] = [1, 2, 3, 4]      // deltas +1 +1 +1
        let b: [Int64] = [1, 2, 1, 4]      // deltas +1 −1 +3
        #expect(!RungTelemetryMath.fullyDetermined(a, b))
        #expect(RungTelemetryMath.comovementPermille(a, b) < 1000)
        // Zero comparisons read 1000 — no evidence of independence is not
        // evidence of independence.
        #expect(RungTelemetryMath.comovementPermille([], []) == 1000)
    }

    // MARK: - The derived-mode snapshot (what the shipped ladder reports)

    @Test func derivedSnapshotIsHonest() {
        let t = RungTelemetry.derived(ticks: 64, fineBinArea: 64, generation: 7)
        #expect(t.generation == 7)
        #expect(t.rungs.map(\.side) == [64, 32, 16])
        #expect(t.rungs.allSatisfy { !$0.independent })
        // Arrivals are the actual rung frame counts of a full burst.
        #expect(t.rungs.map(\.arrivals) == [64, 32, 16])
        #expect(t.rungs.map(\.expectedArrivals) == [64, 32, 16])
        // Pooling-equivalent EV: +k stops per rung, in centistops.
        #expect(t.rungs.map(\.evCentistops) == [0, 100, 200])
        #expect(t.rungs.allSatisfy { $0.exposureDurationUs == 0 && $0.isoMilli == 0 })
        // The 1:8:64 lattice on N₀ = 64 pixels per fine bin.
        #expect(t.rungs.map(\.sampleVolume) == [64, 512, 4096])
        // Independence health = derived/maximal, reported honestly.
        #expect(t.rungs.map(\.comovementPermilleVsCoarser) == [1000, 1000, -1])
    }

    @Test func derivedSnapshotMidBurst() {
        let t = RungTelemetry.derived(ticks: 8, fineBinArea: 16, generation: 1)
        #expect(t.rungs.map(\.arrivals) == [8, 4, 2])
        #expect(t.rungs.map(\.sampleVolume) == [16, 128, 1024])
    }
}
