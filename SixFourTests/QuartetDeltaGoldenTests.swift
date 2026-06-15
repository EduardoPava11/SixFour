import Testing
import simd
@testable import SixFour

/// Gate for the Act II quartet motion outline (`QuartetDelta`) against the spec
/// golden (`QuartetDeltaGolden`, from `SixFour.Spec.QuartetDelta`). Float OKLab
/// Euclidean math can't be bit-exact across languages, so the cross-language
/// readouts are checked within tolerance; the structure (one slot per colour,
/// 3 deltas, core ⊆ slots) is exact-shape.
struct QuartetDeltaGoldenTests {

    private static let tol = QuartetDeltaGolden.tol

    private func close(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Bool {
        abs(a.x - b.x) <= Self.tol && abs(a.y - b.y) <= Self.tol && abs(a.z - b.z) <= Self.tol
    }

    /// `toSlots` transposes 4 palettes into K 4-sample trajectories (one slot per colour).
    @Test func toSlotsShape() {
        let slots = QuartetDelta.toSlots(QuartetDeltaGolden.palettes)
        #expect(slots.count == QuartetDeltaGolden.palettes[0].count)
        #expect(slots.allSatisfy { $0.count == QuartetDelta.quartetFrames })
        // first slot = column 0 across the 4 frames
        for f in 0..<4 {
            #expect(close(slots[0][f], QuartetDeltaGolden.palettes[f][0]))
        }
    }

    /// Swift `slotMean` reproduces the spec's per-slot means (within tol).
    @Test func slotMeansMatchGolden() {
        let slots = QuartetDelta.toSlots(QuartetDeltaGolden.palettes)
        let got = slots.map { QuartetDelta.slotMean($0) }
        #expect(got.count == QuartetDeltaGolden.slotMeans.count)
        for (g, w) in zip(got, QuartetDeltaGolden.slotMeans) {
            #expect(close(g, w), "slotMean drift: \(g) vs \(w)")
        }
    }

    /// Swift `slotDisplacement` reproduces the spec's per-slot motion magnitudes (within tol).
    @Test func slotDisplacementsMatchGolden() {
        let slots = QuartetDelta.toSlots(QuartetDeltaGolden.palettes)
        let got = slots.map { QuartetDelta.slotDisplacement($0) }
        #expect(got.count == QuartetDeltaGolden.slotDisplacements.count)
        for (g, w) in zip(got, QuartetDeltaGolden.slotDisplacements) {
            #expect(abs(g - w) <= Self.tol, "displacement drift: \(g) vs \(w)")
        }
    }

    /// Swift `quartetCore` reproduces the spec's barycenter-of-means (within tol).
    @Test func quartetCoreMatchesGolden() {
        let slots = QuartetDelta.toSlots(QuartetDeltaGolden.palettes)
        let core = QuartetDelta.quartetCore(slots)
        #expect(close(core, QuartetDeltaGolden.quartetCore),
                "core drift: \(core) vs \(QuartetDeltaGolden.quartetCore)")
    }

    /// Swift `coreColors` at the pinned threshold reproduces the spec's core set exactly
    /// (integer indices — exact, not tolerance), and the set is a non-trivial split.
    @Test func coreColorsMatchGolden() {
        let slots = QuartetDelta.toSlots(QuartetDeltaGolden.palettes)
        let got = QuartetDelta.coreColors(QuartetDeltaGolden.coreThreshold, slots)
        #expect(got == QuartetDeltaGolden.coreColors, "core set drift: \(got) vs \(QuartetDeltaGolden.coreColors)")
        // honest split: the median threshold keeps some slots and drops others.
        #expect(!got.isEmpty && got.count < slots.count, "median threshold should split the slots")
    }

    /// Every core slot genuinely has displacement ≤ threshold (the outline is honest —
    /// the spec's `lawCoreIsLowDisplacement`, re-checked on the port).
    @Test func coreIsLowDisplacement() {
        let slots = QuartetDelta.toSlots(QuartetDeltaGolden.palettes)
        for i in QuartetDelta.coreColors(QuartetDeltaGolden.coreThreshold, slots) {
            #expect(QuartetDelta.slotDisplacement(slots[i]) <= QuartetDeltaGolden.coreThreshold + Self.tol)
        }
    }
}
