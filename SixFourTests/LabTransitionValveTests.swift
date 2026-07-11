import Foundation
import Testing
@testable import SixFour

/// `Spec.LabTransition`'s ONE-WAY VALVE, witnessed on the shipped kernels
/// (2026-07-11 link-ledger wave 1): photons pool in LINEAR light and the
/// nonlinear encode happens ONCE, at the boundary — pooling after the valve
/// (averaging encoded bytes) over-reads by Jensen's gap. This test makes the
/// ordering discipline the live paths ride on (`ColorHead` pools linear sums,
/// realizes once at emit) an executable fact, not a convention.
struct LabTransitionValveTests {

    @Test func poolBeforeValveDiffersFromValveThenPool() {
        // A maximally contrasty 2×2 window: two black, two white pixels.
        let rgb: [UInt8] = [0, 0, 0, 255, 255, 255,
                            255, 255, 255, 0, 0, 0]
        // VALVE-CORRECT: pool in linear light, then encode once.
        var sums = [UInt64](repeating: 0, count: 3)
        #expect(s4_pool_sums_linear_srgb8(rgb, 2, 1, &sums) == 0)
        var pooled = [UInt8](repeating: 0, count: 3)
        #expect(s4_sums_to_srgb8_linear(sums, 1, 4, &pooled) == 0)
        // VALVE-VIOLATING: average the ENCODED bytes (the gamma-space mean of
        // two 0s and two 255s, rounded) = 128.
        let gammaMean: UInt8 = 128
        // Jensen: linear-light pooling of a 50% black/white mix encodes to
        // ~188 (the sRGB code for half linear energy), NOT the byte mean 127.
        // The gap IS the window's variance — the mid-gray trap the valve law
        // forbids. If these ever agree on this window, the linearization
        // kernel has been silently bypassed.
        #expect(pooled[0] != gammaMean)
        #expect(pooled[0] > 180 && pooled[0] < 196)
        // And on a CONSTANT window the two orders agree exactly (Jensen's
        // equality case) — the valve costs nothing where there is no variance.
        let flat: [UInt8] = Array(repeating: 128, count: 12)
        var flatSums = [UInt64](repeating: 0, count: 3)
        #expect(s4_pool_sums_linear_srgb8(flat, 2, 1, &flatSums) == 0)
        var flatPooled = [UInt8](repeating: 0, count: 3)
        #expect(s4_sums_to_srgb8_linear(flatSums, 1, 4, &flatPooled) == 0)
        #expect(flatPooled[0] == 128)
    }
}
