import XCTest
@testable import SixFour

/// Golden parity between `HaltDepthBridge` (device) and `SixFour.Spec.HaltDepth` (Haskell law).
/// The spec proves `lawHaltDepthThresholds : map haltDepth [-1,0,1,2,3,4,99] == [0,0,0,1,2,2,2]`
/// and `lawHaltDepthMonotone` / `lawMergeSemilattice`; these assert the Swift mirror agrees, so the
/// render path and the spec can never drift.
final class HaltDepthBridgeTests: XCTestCase {

    /// KEYSTONE: the exact thresholds the spec pins (`lawHaltDepthThresholds`).
    func testThresholdsMatchSpecGolden() {
        let orders: [Int32]   = [-1, 0, 1, 2, 3, 4, 99]
        let expected: [Int32] = [ 0, 0, 0, 1, 2, 2,  2]
        XCTAssertEqual(orders.map(HaltDepthBridge.depth(order:)), expected)
    }

    /// `lawHaltDepthMonotone`: more motion order never yields a coarser depth.
    func testMonotone() {
        for a in Int32(-2) ... Int32(8) {
            for b in a ... Int32(8) {
                XCTAssertLessThanOrEqual(HaltDepthBridge.depth(order: a),
                                         HaltDepthBridge.depth(order: b))
            }
        }
    }

    /// The spatial face broadcasts across every temporal region (region-major (gridSide)³),
    /// exactly the field `s4_render_select` consumes.
    func testDepthFieldBroadcastsSpatialFace() {
        let g = 16
        var orders = [Int32](repeating: -1, count: g * g)   // all coarse
        orders[0] = 5                                        // order 5 → depth 2 at (x0,y0)
        orders[g * g - 1] = 2                                // order 2 → depth 1 at the far corner
        let field = HaltDepthBridge.depthField(fromHaltOrders: orders, gridSide: g)
        XCTAssertEqual(field.count, g * g * g)
        for tr in 0 ..< g {
            let base = tr * g * g
            XCTAssertEqual(field[base + 0], 2)             // fine region, every temporal slice
            XCTAssertEqual(field[base + g * g - 1], 1)     // mid region
            XCTAssertEqual(field[base + 1], 0)             // uncertified → coarse
        }
    }

    /// `lawMergeSemilattice` / `lawUserCanOnlyRefine`: finest-wins max, clamped to {0,1,2}.
    func testMergeFinestWinsAndClamps() {
        XCTAssertEqual(HaltDepthBridge.merge(0, 2), 2)
        XCTAssertEqual(HaltDepthBridge.merge(1, 0), 1)
        XCTAssertEqual(HaltDepthBridge.merge(5, -1), 2)    // out-of-range clamps into {0,1,2}
        // commutative + idempotent
        XCTAssertEqual(HaltDepthBridge.merge(2, 1), HaltDepthBridge.merge(1, 2))
        XCTAssertEqual(HaltDepthBridge.merge(1, 1), 1)
    }
}
