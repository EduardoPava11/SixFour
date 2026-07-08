//  ZigPortKinematicTests.swift
//  Swift port of Native/src/kinematic_test.zig (2026-07-06). Test methods are
//  named after the Zig test names, one method per Zig `test`.
//
//  Host tests for the kinematic kernels — pinned to the Haskell laws
//  (Spec.KinematicLadder / Spec.KinematicHaltPrior): polynomial degree d
//  certifies at d; L_j == 0 iff j >= certified order; t^{k+1} escapes order k
//  with residual exactly (k+1)! at t = k+1; short windows REFUSE (no vacuous
//  certification, stricter than the Haskell harness).

import XCTest
@testable import SixFour

final class ZigPortKinematicTests: XCTestCase {

    /// f(t) = Σ coeffs[i] · t^i over the window (the Zig polyTrajectory helper).
    private func polyTrajectory(_ coeffs: [Int64], _ out: inout [Int64]) {
        for t in 0..<out.count {
            var acc: Int64 = 0
            var p: Int64 = 1
            for c in coeffs {
                acc += c * p
                p *= Int64(t)
            }
            out[t] = acc
        }
    }

    // test "polynomial of exact degree d certifies at d (mirrors trajectory law)"
    func testPolynomialOfExactDegreeDCertifiesAtD() {
        var f = [Int64](repeating: 0, count: 10)
        polyTrajectory([7], &f)
        XCTAssertEqual(Int32(0), s4_certified_order(f, 10, 4))
        polyTrajectory([3, 5], &f)
        XCTAssertEqual(Int32(1), s4_certified_order(f, 10, 4))
        polyTrajectory([1, -2, 9], &f)
        XCTAssertEqual(Int32(2), s4_certified_order(f, 10, 4))
        polyTrajectory([4, 0, -1, 11], &f)
        XCTAssertEqual(Int32(3), s4_certified_order(f, 10, 4))
    }

    // test "LAW (minimal sufficiency): L_j == 0 iff j >= certified order"
    func testLawMinimalSufficiencyLjIsZeroIffJGeqCertifiedOrder() {
        var f = [Int64](repeating: 0, count: 10)
        polyTrajectory([5, 3, 7], &f) // certified order 2
        XCTAssertGreaterThan(s4_residual_loss(f, 10, 0), 0)
        XCTAssertGreaterThan(s4_residual_loss(f, 10, 1), 0)
        XCTAssertEqual(Int64(0), s4_residual_loss(f, 10, 2))
        XCTAssertEqual(Int64(0), s4_residual_loss(f, 10, 3))
        XCTAssertEqual(Int64(0), s4_residual_loss(f, 10, 4))
    }

    // test "TEETH: t^{k+1} escapes order k with residual exactly (k+1)! at t=k+1"
    func testTeethTToTheKPlus1EscapesOrderKWithResidualExactlyKPlus1FactorialAtTEqualsKPlus1() {
        for k in 0..<4 {
            var f = [Int64](repeating: 0, count: 10)
            for t in 0..<10 {
                var p: Int64 = 1
                for _ in 0..<(k + 1) { p *= Int64(t) }
                f[t] = p // f(t) = t^{k+1}
            }
            var fact: Int64 = 1
            var i: Int64 = 1
            while i <= Int64(k + 1) {
                fact *= i
                i += 1
            }
            let t = Int32(k + 1)
            let res = f[Int(t)] - s4_newton_predict(f, 10, Int32(k), t)
            XCTAssertEqual(fact, res)
        }
    }

    // test "Newton full expansion reproduces the window (Mahler loses nothing)"
    func testNewtonFullExpansionReproducesTheWindow() {
        var s: UInt64 = 20260704
        var f = [Int64](repeating: 0, count: 8)
        for i in 0..<8 {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            f[i] = Int64((s >> 33) & 0x3ff) - 512
        }
        for t in 0..<8 {
            XCTAssertEqual(f[t], s4_newton_predict(f, 8, 7, Int32(t)))
        }
    }

    // test "TOTALITY: short windows REFUSE rather than vacuously certify"
    func testTotalityShortWindowsRefuseRatherThanVacuouslyCertify() {
        let f: [Int64] = [1, 2, 3, 4]
        // n=4 can falsify up to Delta^2 (cap <= 2); cap=3 needs n >= 5 -> refuse.
        XCTAssertGreaterThanOrEqual(s4_certified_order(f, 4, 2), 0)
        XCTAssertEqual(S4K_RC_BAD_ARGS, s4_certified_order(f, 4, 3))
        XCTAssertEqual(S4K_RC_BAD_ARGS, s4_certified_order(nil, 4, 1))
        XCTAssertEqual(S4K_RC_BAD_ARGS, s4_certified_order(f, 1, 0))
        XCTAssertEqual(Int64(-1), s4_residual_loss(nil, 4, 1))
    }
}
