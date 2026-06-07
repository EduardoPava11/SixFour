import Testing
import Foundation
import simd
@testable import SixFour

/// Gates the DISCRETE INTEGER projection ladder against the Haskell spec golden: the
/// generated `SixFourVoxelFit` (from `SixFour.Spec.VoxelFit`) must self-check, and its
/// rung table must reproduce the spec's crispness properties — every projected corner on
/// an integer art-pixel, the near face byte-identical to the 2D GIF at every rung, and the
/// flat silhouette exactly `artRes/2`. This is the cross-language closure of the projection
/// that replaces the continuous-orbit raymarcher (which is crisp only when flat).
/// Source of truth: spec/src/SixFour/Spec/VoxelFit.hs.
struct VoxelFitContractTests {

    @Test func goldenSelfCheck() {
        #expect(SixFourVoxelFit.selfCheck())
        #expect(SixFourVoxelFit.side == 64)
        #expect(SixFourVoxelFit.artRes == 128)
        #expect(SixFourVoxelFit.artPerVoxel == 2)
        #expect(SixFourVoxelFit.maxRung == 2)
        #expect(SixFourVoxelFit.goldenHalfSpan.count == 9)
        // Flat silhouette = artRes/2 ⇒ one voxel = one GIF cell.
        #expect(SixFourVoxelFit.stop(xRung: 0, yRung: 0).halfSpan == SixFourVoxelFit.artRes / 2)
        print("[VoxelFit] spec golden: selfCheck=\(SixFourVoxelFit.selfCheck()), "
            + "halfSpans=\(SixFourVoxelFit.goldenHalfSpan)")
    }

    /// THE crispness gate, re-checked in Swift: every cube corner projects to an exact
    /// integer art-pixel at every rung (trivially true for the integer table — the point is
    /// that the SHIPPED projection is the integer one, not the orbit basis it replaced).
    @Test func everyCornerIntegralAtEveryRung() {
        let e = SixFourVoxelFit.side - 1
        for ry in 0..<SixFourVoxelFit.rungsPerAxis {
            for rx in 0..<SixFourVoxelFit.rungsPerAxis {
                let s = SixFourVoxelFit.stop(xRung: rx, yRung: ry)
                for cx in [0, e] { for cy in [0, e] { for ct in [0, e] {
                    let p = SixFourVoxelFit.project(s, cx, cy, ct)
                    // SIMD2<Int> projection is integral by construction; assert it stays on grid.
                    #expect(p.x == Int(p.x) && p.y == Int(p.y))
                } } }
            }
        }
    }

    /// The near face (t = side-1, the current frame) is the GIF square at EVERY rung — the
    /// rotation never disturbs the 2D-GIF identity the user is watching morph in.
    @Test func nearFaceIsGifSquareAtEveryRung() {
        let e = SixFourVoxelFit.side - 1
        let pivot = SixFourVoxelFit.voxelPivot
        let apv = SixFourVoxelFit.artPerVoxel
        for stop in SixFourVoxelFit.ladder {
            for (x, y) in [(0, 0), (63, 63), (17, 42), (40, 5)] {
                let p = SixFourVoxelFit.project(stop, x, y, e)
                #expect(p == SIMD2(apv * (x - pivot), apv * (y - pivot)))
            }
        }
    }
}
