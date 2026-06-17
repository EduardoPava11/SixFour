import Testing
@testable import SixFour

/// Byte-exact gate for the RGBT-4D integer port.
///
/// `RGBT4DLift` is the hand-written Swift port of `SixFour.Spec.RGBTLift` and
/// `SixFour.Spec.CubeLadder`. `RGBT4DGolden` is GENERATED from those specs by
/// `cabal run spec-codegen` (`SixFour.Codegen.RGBT4D`), so the port rides the same
/// drift gate as `CollapseGolden`. Because the lifting is pure integer (Q16) math,
/// every value must match EXACTLY — no tolerance (notably the floor-division parity
/// that Haskell `div` and Swift `/` disagree on for negatives).
struct RGBT4DGoldenTests {

    /// Flatten cube-ladder detail planes to `[Int]` (R/G/B per triple) for comparison
    /// against the generated `distillDetailsFlat` (tuple arrays aren't Equatable).
    private func flatten(_ dets: [[(Int, Int, Int)]]) -> [Int] {
        dets.flatMap { $0.flatMap { [$0.0, $0.1, $0.2] } }
    }

    @Test func liftQuadMatchesGeneratedGolden() {
        let (r, g, b, t) = RGBT4DLift.liftQuad((10, 20, 30, 44))
        #expect([r, g, b, t] == RGBT4DGolden.liftQuad_10_20_30_44)
    }

    @Test func distillMatchesGeneratedGolden() {
        let (coarse, dets) = RGBT4DLift.distill(2, 8, RGBT4DGolden.grid)
        #expect(coarse == RGBT4DGolden.distillCoarse)
        #expect(flatten(dets) == RGBT4DGolden.distillDetailsFlat)
    }

    @Test func synthBeyondMatchesGeneratedGolden() {
        #expect(RGBT4DLift.synthBeyond(8, 1, RGBT4DGolden.grid) == RGBT4DGolden.synthBeyond_8_1)
    }

    @Test func ladderIsBijectiveWithinCapture() {
        let (coarse, dets) = RGBT4DLift.distill(2, 8, RGBT4DGolden.grid)
        #expect(RGBT4DLift.synthesize(2, coarse, dets) == RGBT4DGolden.grid)
    }

    @Test func quadRoundTripsExactlyIncludingNegatives() {
        let q = (-7, 3, -128, 65)
        #expect(RGBT4DLift.unliftQuad(RGBT4DLift.liftQuad(q)) == q)
    }

    @Test func coarsePlaneIsGamutClosed() {
        let (coarse, _) = RGBT4DLift.liftLevel(8, RGBT4DGolden.grid)
        let lo = RGBT4DGolden.grid.min()!, hi = RGBT4DGolden.grid.max()!
        #expect(coarse.allSatisfy { $0 >= lo && $0 <= hi })
    }
}
