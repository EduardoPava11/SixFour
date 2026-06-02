import Testing
import Foundation
import simd
@testable import SixFour

/// Gate for the three radix genome projections (`BranchedPalette.project`) against
/// the spec golden (`GenomeGolden`, from `Spec.Quad4` + `Spec.SigmaPairHead`).
/// 16² is exact (identity); 4⁴ and 2⁸ are lossy projections checked within
/// tolerance (float genome math can't be bit-exact across languages).
struct GenomeGoldenTests {

    private static let tol = 1e-9

    private func close(_ a: [SIMD3<Double>], _ b: [SIMD3<Double>]) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) {
            if abs(x.x - y.x) > Self.tol || abs(x.y - y.y) > Self.tol || abs(x.z - y.z) > Self.tol {
                return false
            }
        }
        return true
    }

    @Test func flatIsIdentity() {
        let got = BranchedPalette.project(GenomeGolden.leaves, branching: .b16)
        #expect(got == GenomeGolden.leaves)        // exact — identity
        #expect(close(got, GenomeGolden.flat))
    }

    @Test func quad4MatchesGolden() {
        let got = BranchedPalette.project(GenomeGolden.leaves, branching: .b4)
        #expect(got.count == 256)
        #expect(close(got, GenomeGolden.quad4), "Quad4 (4⁴) projection drifted from spec")
    }

    @Test func sigmaPairMatchesGolden() {
        let got = BranchedPalette.project(GenomeGolden.leaves, branching: .b2)
        #expect(got.count == 256)
        #expect(close(got, GenomeGolden.sigmaPair), "σ-pair (2⁸) projection drifted from spec")
    }

    /// The lossy genomes genuinely SHIFT colours (4⁴/2⁸ ≠ the flat leaves), while
    /// 16² does not — the inductive bias the radix imposes is real and visible.
    @Test func lossyGenomesShiftColoursButFlatDoesNot() {
        let flat = BranchedPalette.project(GenomeGolden.leaves, branching: .b16)
        let quad4 = BranchedPalette.project(GenomeGolden.leaves, branching: .b4)
        let sigma = BranchedPalette.project(GenomeGolden.leaves, branching: .b2)
        #expect(flat == GenomeGolden.leaves)
        #expect(quad4 != GenomeGolden.leaves, "Quad4 must be a lossy projection")
        #expect(sigma != GenomeGolden.leaves, "σ-pair must be a lossy projection")
        // σ-pair output is σ-symmetric: odd leaf = σ(even leaf).
        for i in stride(from: 0, to: 256, by: 2) {
            let c = sigma[i], s = sigma[i + 1]
            #expect(abs(s.x - c.x) <= Self.tol && abs(s.y + c.y) <= Self.tol && abs(s.z + c.z) <= Self.tol)
        }
    }
}
