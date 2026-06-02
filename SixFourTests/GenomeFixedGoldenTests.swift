import Testing
import simd
@testable import SixFour

/// Gate for the BYTE-EXACT integer genome projections (`BranchedPalette.projectQ16`)
/// against the spec golden (`GenomeFixedGolden`, from `Spec.Quad4Fixed` +
/// `Spec.SigmaPairFixed`). Pure integer math ⇒ EXACT equality (no tolerance), so a
/// 4⁴ or 2⁸ GIFB colour table is byte-exact cross-device. σ-pair rides the owned
/// Zig `s4_haar`; Quad4 is the pure-Swift integer port.
struct GenomeFixedGoldenTests {

    @Test func flatIsIdentityQ16() {
        #expect(BranchedPalette.projectQ16(GenomeFixedGolden.leaves, branching: .b16) == GenomeFixedGolden.leaves)
        #expect(GenomeFixedGolden.flat == GenomeFixedGolden.leaves)
    }

    @Test func quad4MatchesGoldenExactly() {
        let got = BranchedPalette.projectQ16(GenomeFixedGolden.leaves, branching: .b4)
        #expect(got.count == 256)
        #expect(got == GenomeFixedGolden.quad4, "integer Quad4 (4⁴) projection drifted from spec")
    }

    @Test func sigmaPairMatchesGoldenExactly() {
        let got = BranchedPalette.projectQ16(GenomeFixedGolden.leaves, branching: .b2)
        #expect(got.count == 256)
        #expect(got == GenomeFixedGolden.sigmaPair, "integer σ-pair (2⁸) projection drifted from spec")
    }

    /// The lossy genomes shift colours (4⁴/2⁸ ≠ flat); σ-pair output is σ-symmetric;
    /// Quad4 output satisfies the opponent-quadrant balance c₀−c₁−c₂+c₃ = 0.
    @Test func integerGenomeStructuralInvariants() {
        let quad4 = BranchedPalette.projectQ16(GenomeFixedGolden.leaves, branching: .b4)
        let sigma = BranchedPalette.projectQ16(GenomeFixedGolden.leaves, branching: .b2)
        #expect(quad4 != GenomeFixedGolden.leaves)
        #expect(sigma != GenomeFixedGolden.leaves)
        // σ-pair: odd leaf = σ(even) exactly (integer).
        for i in stride(from: 0, to: 256, by: 2) {
            let c = sigma[i], s = sigma[i + 1]
            #expect(s == SIMD3<Int32>(c.x, -c.y, -c.z))
        }
        // Quad4: every leaf-quad balances exactly.
        for i in stride(from: 0, to: 256, by: 4) {
            #expect(quad4[i] &- quad4[i + 1] &- quad4[i + 2] &+ quad4[i + 3] == SIMD3<Int32>(repeating: 0))
        }
    }
}
