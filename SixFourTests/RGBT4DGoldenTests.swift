import Testing
@testable import SixFour

/// Byte-exact gate for the RGBT-4D integer port.
///
/// `RGBT4DLift` is the hand-written Swift port of `SixFour.Spec.RGBTLift` and
/// `SixFour.Spec.CubeLadder`. Because the lifting is pure integer (Q16) math, the
/// port must reproduce the spec EXACTLY — no tolerance. These mirror the spec's
/// QuickCheck laws and pin the same golden values (notably the floor-division
/// parity that Haskell `div` and Swift `/` disagree on for negatives).
struct RGBT4DGoldenTests {

    // The fixed 8×8 grid behind the spec's FNV golden pins (Properties.CubeLadder).
    static let goldenGrid: [Int] = (0..<64).map { ((($0 * 37 + 11) % 251)) - 125 }

    @Test func liftQuadMatchesSpecGolden() {
        // SixFour.Spec.RGBTLift golden: liftQuad (10,20,30,44) = (26,-22,-12,4).
        #expect(RGBT4DLift.liftQuad((10, 20, 30, 44)) == (26, -22, -12, 4))
    }

    @Test func quadRoundTripsExactlyIncludingNegatives() {
        let q = (-7, 3, -128, 65)
        #expect(RGBT4DLift.unliftQuad(RGBT4DLift.liftQuad(q)) == q)
    }

    @Test func ladderIsBijectiveWithinCapture() {
        let (coarse, dets) = RGBT4DLift.distill(2, 8, Self.goldenGrid)
        #expect(RGBT4DLift.synthesize(2, coarse, dets) == Self.goldenGrid)
    }

    @Test func oneLevelReversible() {
        let (c, d) = RGBT4DLift.liftLevel(8, Self.goldenGrid)
        #expect(RGBT4DLift.unliftLevel(4, c, d) == Self.goldenGrid)
    }

    @Test func coarsePlaneIsGamutClosed() {
        let (coarse, _) = RGBT4DLift.liftLevel(8, Self.goldenGrid)
        let lo = Self.goldenGrid.min()!, hi = Self.goldenGrid.max()!
        #expect(coarse.allSatisfy { $0 >= lo && $0 <= hi })
    }

    @Test func synthBeyondIsNearestNeighbourReplication() {
        let h = 4
        let coarse = (0..<(h * h)).map { $0 * 7 - 50 }
        // nearest-neighbour ×2 replication, the deterministic floor.
        let side = 2 * h
        var expected = [Int](repeating: 0, count: side * side)
        for oy in 0..<side { for ox in 0..<side { expected[oy * side + ox] = coarse[(oy / 2) * h + (ox / 2)] } }
        #expect(RGBT4DLift.synthBeyond(h, 1, coarse) == expected)
    }
}
