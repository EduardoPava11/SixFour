import XCTest
import simd
@testable import SixFour

/// The multiscale encode bridge (`MultiScaleRender`). The load-bearing test is the SAFETY golden:
/// an all-depth-2 (all-fine) field must reproduce the input tiles bit-for-bit — the multiscale
/// analog of zero-gene==floor, so the always-on path can never regress the certified renderer.
final class MultiScaleRenderTests: XCTestCase {

    private func makeTiles() -> [OKLabTile] {
        (0 ..< 64).map { t in
            let px = (0 ..< 64 * 64).map { i in
                SIMD3<Float>(Float((t * 7 + i) % 101) / 100,
                             Float((i * 3) % 97) / 97 - 0.5,
                             Float((t + i) % 89) / 89 - 0.5)
            }
            return OKLabTile(side: 64, pixels: px, captureNanos: UInt64(t), palette: [], finalShift: 0)
        }
    }

    /// SAFETY GOLDEN: all-depth-2 ⇒ fused == input, bit-for-bit (renderSelect is identity on V64).
    func testAllFineIsIdentity() {
        let tiles = makeTiles()
        let allFine = [Int32](repeating: 2, count: 16 * 16 * 16)
        guard let fused = MultiScaleRender.fusedTiles(from: tiles, depthField: allFine) else {
            return XCTFail("fusedTiles returned nil for a valid 64³ input")
        }
        XCTAssertEqual(fused.count, tiles.count)
        for t in 0 ..< 64 {
            XCTAssertEqual(fused[t].pixels, tiles[t].pixels, "frame \(t) must be bit-identical at all-fine")
        }
    }

    /// Bad shapes → nil, so the caller falls back to the uniform 64³ tiles.
    func testBadShapeReturnsNil() {
        XCTAssertNil(MultiScaleRender.fusedTiles(from: [], depthField: [Int32](repeating: 0, count: 4096)))
        XCTAssertNil(MultiScaleRender.fusedTiles(from: makeTiles(), depthField: [0, 1, 2]))
    }

    /// All-depth-0 (coarse): each 4×4 spatial block is block-constant (block-replicated V16) — the
    /// chunky multiscale look where the scene is static.
    func testAllCoarseIsBlockConstant() {
        let tiles = makeTiles()
        let allCoarse = [Int32](repeating: 0, count: 16 * 16 * 16)
        guard let fused = MultiScaleRender.fusedTiles(from: tiles, depthField: allCoarse) else {
            return XCTFail("fusedTiles returned nil")
        }
        let corner = fused[0].pixels[0]
        for dy in 0 ..< 4 {
            for dx in 0 ..< 4 {
                XCTAssertEqual(fused[0].pixels[dy * 64 + dx], corner, "4×4 block must be constant at depth 0")
            }
        }
    }
}
