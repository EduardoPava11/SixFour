import Testing
import Foundation
@testable import SixFour

/// Cross-tier golden for the V2.1 encoder-input kernels: the Swift FFI wrappers
/// (`SixFourNative.centeredEnergyV21` / `modeRelativeV21` / `anchorAtV21`) must match the Haskell
/// `SixFour.Spec.V21Field` source of truth on the pinned fixture (the SAME curves the Zig
/// `v21_mode_relative_fixture_test` checks), and the anchor must reconstruct the centered curve from
/// the mode-relative curve + the GIF modes (field + GIF reconstruct the field).
struct V21EncoderInputGoldenTests {

    // p = 1 (3 curves R,G,B), nLevels = 6. R has a clear mode with a tie-free min (level 3); G is
    // flat (mode 0); B's min is a tie resolved to the lowest index (level 1).
    private let p = 1, n = 6
    private let curves: [Int32]      = [9, 5, 7, 2, 8, 2,  0, 0, 0, 0, 0, 0,  1, 0, 0, 1, 1, 1]
    private let wantCentered: [Int32] = [7, 3, 5, 0, 6, 0,  0, 0, 0, 0, 0, 0,  1, 0, 0, 1, 1, 1]
    private let wantRel: [Int32]      = [0, 6, 0, 7, 3, 5,  0, 0, 0, 0, 0, 0,  0, 0, 1, 1, 1, 1]
    private let wantModes: [Int32]    = [3, 0, 1]

    @Test func centeredEnergyMatchesSpec() {
        #expect(SixFourNative.centeredEnergyV21(curves: curves, p: p, nLevels: n) == wantCentered)
    }

    @Test func modeRelativeMatchesSpec() {
        #expect(SixFourNative.modeRelativeV21(curves: curves, p: p, nLevels: n) == wantRel)
    }

    /// The GIF byte per curve is `collapseV21` (argmin, lowest index): [3, 0, 1].
    @Test func collapseGivesTheModes() {
        #expect(SixFourNative.collapseV21(curves: curves, p: p, nLevels: n) == wantModes.map { UInt8($0) })
    }

    /// Field + GIF reconstruct the field: `anchorAt(mode_relative, modes) == centered`.
    @Test func anchorReconstructsTheCenteredField() {
        guard let rel = SixFourNative.modeRelativeV21(curves: curves, p: p, nLevels: n) else {
            Issue.record("modeRelativeV21 returned nil"); return
        }
        #expect(SixFourNative.anchorAtV21(rel: rel, modes: wantModes, p: p, nLevels: n) == wantCentered)
    }

    /// The mode-relative input WITHHOLDS the mode: its own argmin is pinned to relative-0 for every
    /// curve, so collapsing the mode-relative input yields all zeros (it carries no absolute-mode bit).
    @Test func modeRelativeWithholdsTheMode() {
        guard let rel = SixFourNative.modeRelativeV21(curves: curves, p: p, nLevels: n) else {
            Issue.record("modeRelativeV21 returned nil"); return
        }
        #expect(SixFourNative.collapseV21(curves: rel, p: p, nLevels: n) == [UInt8](repeating: 0, count: p * 3))
    }
}
