import XCTest
import simd
@testable import SixFour

/// On-device parity for the delta-preserving move + schedule — re-asserts the `SixFour.Spec`
/// laws (`IsometryMove` / `MoveRadiusSchedule`) the Swift port must reproduce bit-for-bit.
final class IsometryMoveTests: XCTestCase {

    private func randColor() -> SIMD3<Int32> {
        SIMD3(Int32.random(in: 0...65536), Int32.random(in: -26214...26214), Int32.random(in: -26214...26214))
    }
    private func randMove() -> IsoMove {
        IsoMove(signs: SIMD3(Bool.random() ? 1 : -1, Bool.random() ? 1 : -1, Bool.random() ? 1 : -1),
                shift: SIMD3(Int32.random(in: -16384...16384), Int32.random(in: -16384...16384), Int32.random(in: -16384...16384)))
    }

    /// T1 — the move preserves EVERY pairwise squared distance exactly (no tolerance).
    func testPairwiseDeltaPreservedExactly() {
        for _ in 0..<3000 {
            let m = randMove(), x = randColor(), y = randColor()
            XCTAssertEqual(IsoMove.distSq(m.apply(x), m.apply(y)), IsoMove.distSq(x, y))
        }
    }

    /// T2 — every move is exactly reversible (byte round-trip).
    func testReversible() {
        for _ in 0..<3000 {
            let m = randMove(), x = randColor()
            XCTAssertEqual(m.inverse.apply(m.apply(x)), x)
        }
    }

    /// T4 — σ negates a,b and fixes L.
    func testSigma() {
        for _ in 0..<500 {
            let x = randColor()
            XCTAssertEqual(IsoMove.sigma.apply(x), SIMD3(x.x, -x.y, -x.z))
        }
    }

    /// Schedule — starts at rMax, monotone non-increasing, floored at rMin.
    func testScheduleStartsWideMonotoneBounded() {
        XCTAssertEqual(MoveRadiusSchedule.radius(0), MoveRadiusSchedule.radiusMax)
        var prev = MoveRadiusSchedule.radius(0)
        for n in 1...4096 {
            let r = MoveRadiusSchedule.radius(n)
            XCTAssertLessThanOrEqual(r, prev)
            XCTAssertGreaterThanOrEqual(r, MoveRadiusSchedule.radiusMin)
            prev = r
        }
    }

    /// Cap — every axis of a clamped displacement is within ±cumCap.
    func testClampWithinCap() {
        let cap = MoveRadiusSchedule.cumCap
        for _ in 0..<3000 {
            let t = SIMD3<Int32>(Int32.random(in: -40000...40000), Int32.random(in: -40000...40000), Int32.random(in: -40000...40000))
            let c = MoveRadiusSchedule.clampToCap(t)
            XCTAssertTrue(c.x >= -cap && c.x <= cap && c.y >= -cap && c.y <= cap && c.z >= -cap && c.z <= cap)
        }
    }
}
