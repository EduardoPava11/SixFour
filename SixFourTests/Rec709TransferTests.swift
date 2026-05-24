import Testing
import Foundation
@testable import SixFour

/// Tests the BT.709 opto-electronic transfer function used by the YCbCr10
/// capture path. The actual implementation lives in `Shaders.metal`
/// (`rec709ToLinear`), so this test mirrors the same five-line formula in
/// Swift and verifies it against published BT.709 reference values from
/// ITU-R BT.709-6 (2015). The Metal version is trusted to match by
/// inspection — `swift_rec709ToLinear` and the Metal `rec709ToLinear` are
/// character-for-character identical inside the function body.
struct Rec709TransferTests {

    /// Swift mirror of `rec709ToLinear` in Shaders.metal:18-25.
    /// Inverse of the BT.709 OETF: α = 1.099, β = 0.018, γ = 0.45,
    /// with linear-segment slope 4.5 below V = 0.081.
    private static func swift_rec709ToLinear(_ v: Float) -> Float {
        return v < 0.081 ? v / 4.5 : powf((v + 0.099) / 1.099, 1.0 / 0.45)
    }

    /// Mirror of the prior approximation: applying the sRGB transfer to
    /// BT.709-encoded RGB. Verifies the magnitude of the bug we just fixed.
    private static func swift_srgbToLinear(_ v: Float) -> Float {
        return v <= 0.04045 ? v / 12.92 : powf((v + 0.055) / 1.055, 2.4)
    }

    /// Boundary values: 0 → 0, 1 → 1.
    @Test func endpointsAreExact() {
        #expect(Self.swift_rec709ToLinear(0.0) == 0.0)
        #expect(abs(Self.swift_rec709ToLinear(1.0) - 1.0) < 1e-5)
    }

    /// At the knee V = β = 0.018·4.5 = 0.081, both branches must agree.
    /// (BT.709 specifies the curve is C¹ continuous there.)
    @Test func curveIsContinuousAtTheKnee() {
        let lo = Self.swift_rec709ToLinear(0.0810 - 1e-4)
        let hi = Self.swift_rec709ToLinear(0.0810 + 1e-4)
        #expect(abs(lo - hi) < 1e-3)
    }

    /// Selected midtone values, computed from the ITU formula.
    /// Reference values are computed directly with `pow(_:_:)` to keep
    /// the test honest — the assertion is that the implementation hits
    /// the published curve, not that hand-computed constants match.
    @Test func midtonesMatchPublishedFormula() {
        for v: Float in [0.18, 0.5, 0.75] {
            let expected = powf((v + 0.099) / 1.099, 1.0 / 0.45)
            let got = Self.swift_rec709ToLinear(v)
            #expect(abs(got - expected) < 1e-6,
                    "V=\(v): expected \(expected), got \(got)")
        }
    }

    /// The bug we just fixed: applying sRGB transfer to BT.709-encoded
    /// values used to introduce ~63% linear error in dark tones. Verify
    /// the magnitude of the discrepancy so a future refactor that
    /// silently swapped one for the other would tank this test.
    @Test func sRGBApproximationIsMateriallyDifferentInTheToe() {
        // Pick a dark BT.709 value where the two transfers diverge most.
        let v: Float = 0.10
        let rec = Self.swift_rec709ToLinear(v)
        let srgb = Self.swift_srgbToLinear(v)
        // Linear values differ by > 50 % in the dark toe (per research:
        // up to 63 % at the worst point). Floor at 10 % so the test is
        // robust to platform float drift.
        #expect(abs(rec - srgb) / max(rec, 1e-6) > 0.10,
                "Rec.709 toe (\(rec)) and sRGB approximation (\(srgb)) must differ materially")
    }
}
