import Testing
import simd
@testable import SixFour

/// Gate for the Haar palette tree (`PaletteHaarTree`) against the spec golden
/// (`PairTreeGolden`, from `SixFour.Spec.PairTree`). Float Haar math can't be
/// bit-exact across languages, so the cross-language `analyze` parity is checked
/// within tolerance; the round-trip and structure are exact-shape.
struct PairTreeGoldenTests {

    private static let tol = 1e-9

    private func close(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Bool {
        abs(a.x - b.x) <= Self.tol && abs(a.y - b.y) <= Self.tol && abs(a.z - b.z) <= Self.tol
    }

    /// Swift `analyze` reproduces the spec's `analyze` on the fixture (within tol).
    @Test func analyzeMatchesGolden() {
        let hp = PaletteHaarTree.analyze(PairTreeGolden.leaves)
        #expect(close(hp.root, PairTreeGolden.root), "root drift: \(hp.root) vs \(PairTreeGolden.root)")
        #expect(hp.levels.count == PairTreeGolden.levels.count)
        for (i, (got, want)) in zip(hp.levels, PairTreeGolden.levels).enumerated() {
            #expect(got.count == want.count, "level \(i) count \(got.count) vs \(want.count)")
            #expect(got.count == (1 << i), "level \(i) must have 2^\(i) offsets")
            for (g, w) in zip(got, want) {
                #expect(close(g, w), "level \(i) offset drift: \(g) vs \(w)")
            }
        }
    }

    /// `reconstruct ∘ analyze = id` on the fixture (the spec's round-trip law).
    @Test func roundTripFixture() {
        let back = PaletteHaarTree.reconstruct(PaletteHaarTree.analyze(PairTreeGolden.leaves))
        #expect(back.count == PairTreeGolden.leaves.count)
        for (b, l) in zip(back, PairTreeGolden.leaves) {
            #expect(close(b, l), "round-trip drift: \(b) vs \(l)")
        }
    }

    /// Round-trip + DOF at the PRODUCTION depth (256 leaves, depth 8): exercises all
    /// 8 levels and pins `degreesOfFreedom == 768`.
    @Test func roundTripProductionSize() {
        // Deterministic 256-leaf palette (LCG), in gamut.
        var s: UInt64 = 0xC0FFEE
        func nextD(_ lo: Double, _ hi: Double) -> Double {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return lo + (hi - lo) * (Double(s >> 40) / Double(1 << 24))
        }
        let leaves = (0..<256).map { _ in SIMD3<Double>(nextD(0, 1), nextD(-0.4, 0.4), nextD(-0.4, 0.4)) }

        let hp = PaletteHaarTree.analyze(leaves)
        #expect(hp.levels.count == 8)
        for i in 0..<8 { #expect(hp.levels[i].count == (1 << i)) }
        // root + Σ 2^i offsets = 256 leaves worth of coefficients.
        let coeffCount = 1 + hp.levels.reduce(0) { $0 + $1.count }
        #expect(coeffCount == 256)
        #expect(PaletteHaarTree.degreesOfFreedom == 3 * coeffCount)
        #expect(PaletteHaarTree.degreesOfFreedom == PairTreeGolden.degreesOfFreedom)

        let back = PaletteHaarTree.reconstruct(hp)
        #expect(back.count == 256)
        var maxErr = 0.0
        for (b, l) in zip(back, leaves) {
            maxErr = max(maxErr, max(abs(b.x - l.x), max(abs(b.y - l.y), abs(b.z - l.z))))
        }
        #expect(maxErr <= 1e-9, "depth-8 round-trip max error \(maxErr)")
    }
}
