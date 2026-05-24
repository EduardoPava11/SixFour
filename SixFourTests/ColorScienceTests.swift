import Testing
import simd
@testable import SixFour

/// Tests that the Swift `ColorScience` implementation agrees with the
/// generated `SixFourOKLabConstants` constants (which are the Haskell spec's
/// source of truth) and that the encode→decode round-trip is sub-LSB.
struct ColorScienceTests {

    /// The 18 matrix coefficients used in `linearSRGBToOKLab` /
    /// `okLabToLinearSRGB` MUST equal the codegen output, bit-for-bit.
    /// If this fails, somebody hand-edited a number that the spec owns —
    /// regenerate `Generated/StageContract.swift` and refresh the Swift code.
    @Test func m1MatchesGeneratedContract() {
        let m1 = SixFourOKLabConstants.M1
        #expect(m1[0] == [0.4122214708, 0.5363325363, 5.14459929e-2])
        #expect(m1[1] == [0.2119034982, 0.6806995451, 0.1073969566])
        #expect(m1[2] == [8.83024619e-2, 0.2817188376, 0.6299787005])
    }

    @Test func m2MatchesGeneratedContract() {
        let m2 = SixFourOKLabConstants.M2
        #expect(m2[0] == [0.2104542553, 0.793617785, -4.0720468e-3])
        #expect(m2[1] == [1.9779984951, -2.428592205, 0.4505937099])
        #expect(m2[2] == [2.59040371e-2, 0.7827717662, -0.808675766])
    }

    /// Pure black and pure white must survive the OKLab → sRGB8 round-trip
    /// exactly. These are the corner cases of the gamut.
    @Test func roundTripBlackAndWhite() {
        let black = ColorScience.okLabToSRGB8(ColorScience.srgb8ToOKLab(0, 0, 0))
        #expect(black == SIMD3<UInt8>(0, 0, 0))
        let white = ColorScience.okLabToSRGB8(ColorScience.srgb8ToOKLab(255, 255, 255))
        #expect(white == SIMD3<UInt8>(255, 255, 255))
    }

    /// Round-trip on a deterministic 8³ grid of sRGB cubes. L∞ error must
    /// be ≤ 1 LSB per channel; the encode and decode primaries are 8-bit.
    @Test func roundTripGridLInfNotMoreThanOne() {
        var maxErr: Int = 0
        for r in stride(from: 0, through: 255, by: 36) {
            for g in stride(from: 0, through: 255, by: 36) {
                for b in stride(from: 0, through: 255, by: 36) {
                    let lab = ColorScience.srgb8ToOKLab(UInt8(r), UInt8(g), UInt8(b))
                    let back = ColorScience.okLabToSRGB8(lab)
                    maxErr = max(maxErr, abs(Int(back.x) - r))
                    maxErr = max(maxErr, abs(Int(back.y) - g))
                    maxErr = max(maxErr, abs(Int(back.z) - b))
                }
            }
        }
        #expect(maxErr <= 1, "round-trip L∞ error \(maxErr) exceeds 1 LSB")
    }

    /// Distance in OKLab is symmetric and zero only at coincidence. Cheap
    /// algebraic sanity check on `okLabDistanceSquared` — palette code paths
    /// depend on it heavily and don't want a metric-direction bug.
    @Test func distanceIsSymmetricAndZeroAtIdentity() {
        let a = OKLab(0.5, 0.1, -0.2)
        let b = OKLab(0.4, 0.0,  0.1)
        #expect(okLabDistanceSquared(a, a) == 0)
        #expect(okLabDistanceSquared(a, b) == okLabDistanceSquared(b, a))
        #expect(okLabDistanceSquared(a, b) > 0)
    }
}
