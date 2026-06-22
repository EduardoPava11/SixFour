import Testing
import Foundation
@testable import SixFour

/// DEVICE ALIGNMENT GATE for the JEPA encoder's learned forward: the hand-written Swift
/// `MaskedBandForward` (9-D featuresB + 63-param theta_B) must reproduce the Haskell spec
/// (`SixFour.Spec.MaskedBandPrediction`) byte-for-byte. The golden is codegen-emitted
/// (`MaskedBandGolden`, regenerate: cabal run spec-codegen). NO Core AI: theta_B is a
/// dot product, so the on-device forward is hand-written and golden-gated.
struct MaskedBandForwardTests {

    /// The committed Q16 BYTE is BIT-EXACT (integer; no tolerance). This is the load-bearing
    /// assertion: the device commits the same byte the spec proves.
    @Test func predictMatchesGoldenByteExact() {
        for (i, c) in MaskedBandGolden.cases.enumerated() {
            let byte = MaskedBandForward.predict(theta: MaskedBandGolden.theta,
                                                 coarse: c.coarse, detail: c.detail, masked: c.masked)
            #expect(byte == c.byte,
                    "case \(i) (coarse=\(c.coarse), masked=\(c.masked)): Swift byte \(byte) != golden \(c.byte)")
        }
    }

    /// rawMaskedBand within tolerance (float; the value-level cross-check behind the byte).
    @Test func rawMatchesGoldenWithinTolerance() {
        for (i, c) in MaskedBandGolden.cases.enumerated() {
            let r = MaskedBandForward.raw(theta: MaskedBandGolden.theta,
                                          coarse: c.coarse, detail: c.detail, masked: c.masked)
            #expect(abs(r - c.raw) < 1e-9, "case \(i): raw \(r) != golden \(c.raw)")
        }
    }

    /// Shape sanity: featuresB is always 9 wide, theta is numBands*featureCount.
    @Test func shapesMatchSpec() {
        #expect(MaskedBandGolden.theta.count == MaskedBandForward.numBands * MaskedBandForward.featureCount)
        #expect(MaskedBandForward.features(coarse: 12345, siblings: [1, 2, 3]).count == MaskedBandForward.featureCount)
        #expect(MaskedBandForward.siblings(detail: [0, 1, 2, 3, 4, 5, 6], masked: 2) == [0, 1, 3, 4, 5, 6])
    }
}
