import Testing
import simd
@testable import SixFour

/// Gate for the on-device Zig collapse kernel (`s4_global_collapse`, via
/// `SixFourNative.globalCollapse`) against the same spec golden the pure-Swift
/// `FarthestPointCollapse` uses (`CollapseGolden`). Pure integer math ⇒ byte-exact.
/// This pins the THIRD home of the collapse (Haskell ≡ Swift ≡ Zig) from the app side.
struct ZigCollapseGoldenTests {

    @Test func zigGlobalCollapseMatchesGolden() {
        guard let r = SixFourNative.globalCollapse(perFramePalettes: CollapseGolden.frames,
                                                   kOut: CollapseGolden.k) else {
            Issue.record("s4_global_collapse returned nil")
            return
        }
        #expect(r.leaves == CollapseGolden.leaves)
        let flatExpected = CollapseGolden.reindexedFrames.flatMap { $0 }
        #expect(r.indices == flatExpected)
    }

    /// The Zig kernel and the pure-Swift reference agree (both ≡ spec ⇒ ≡ each other).
    @Test func zigAgreesWithSwiftReference() {
        guard let zig = SixFourNative.globalCollapse(perFramePalettes: CollapseGolden.frames,
                                                     kOut: CollapseGolden.k) else {
            Issue.record("s4_global_collapse returned nil")
            return
        }
        let swift = FarthestPointCollapse().collapse(perFramePalettes: CollapseGolden.frames,
                                                     k: CollapseGolden.k)
        #expect(zig.leaves == swift.leaves)
    }
}
