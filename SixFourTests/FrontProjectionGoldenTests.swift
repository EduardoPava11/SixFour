import Testing
import Foundation
@testable import SixFour

/// Gates RULE-CUBE-2D-IDENTITY against the Haskell spec golden: the generated
/// `SixFourFrontProjection` (from `SixFour.Spec.FrontProjection`) must self-check AND
/// agree with the shipped `SixFourPlaybackClock` on the near-face depth→frame map. This
/// is the cross-language closure of the front-projection identity that was previously
/// asserted only inside Swift (`VoxelRestPoseIdentityTests`).
/// Source of truth: spec/src/SixFour/Spec/FrontProjection.hs.
struct FrontProjectionGoldenTests {

    @Test func goldenSelfCheckAndIsIdentity() {
        #expect(SixFourFrontProjection.selfCheck())
        #expect(SixFourFrontProjection.frameCount == 64)
        #expect(SixFourFrontProjection.fieldSide == 64)
        // The near face (z = N-1) shows frame == cursor for every cursor.
        #expect(SixFourFrontProjection.goldenFrontFaceFrame == Array(0..<64))
        print("[FrontProjection] spec golden: selfCheck=\(SixFourFrontProjection.selfCheck()), "
            + "nearFaceMap==identity over 0..<64 = \(SixFourFrontProjection.goldenFrontFaceFrame == Array(0..<64))")
    }

    /// CROSS-CONTRACT: the spec's near-face frame map equals the shipped PlaybackClock's
    /// `threeDFrontFace` (the cube's near face). If the cube's depth→frame math ever
    /// drifts from the spec, this goes red — verification I can't do by driving the app.
    @Test func goldenMatchesPlaybackClockNearFace() {
        let n = SixFourFrontProjection.frameCount
        var mismatches = 0
        for cursor in 0..<n {
            let spec = SixFourFrontProjection.goldenFrontFaceFrame[cursor]
            let shipped = SixFourPlaybackClock.threeDFrontFace(cursor, count: n)
            if spec != shipped { mismatches += 1 }
            #expect(spec == shipped)
        }
        print("[FrontProjection] cross-check vs PlaybackClock.threeDFrontFace: "
            + "\(n - mismatches)/\(n) cursors agree (mismatches=\(mismatches))")
    }
}
