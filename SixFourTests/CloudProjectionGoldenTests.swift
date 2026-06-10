import Testing
import simd
@testable import SixFour

/// Pins the P4 cloud's hand-ported OKLab→world map (`CloudWorld.map`) to the spec
/// golden `SixFour.Spec.CloudProjection.oklabToWorld` (`CloudProjectionGolden`).
/// The Swift port is `Float`, the spec is `Double` ⇒ tolerance gate. Closes the old
/// `TODO(spec-pin)` on the cloud's distance-honest projection.
struct CloudProjectionGoldenTests {

    /// Float port vs Double golden: scale·(value−centre) over [-1,1] stays well within this.
    private static let tol: Float = 1e-5

    @Test func constantsMatchGolden() {
        #expect(abs(CloudWorld.scale - Float(CloudProjectionGolden.scale)) <= Self.tol)
        #expect(abs(CloudWorld.centreL - Float(CloudProjectionGolden.centre.x)) <= Self.tol)
        #expect(abs(CloudWorld.centreA - Float(CloudProjectionGolden.centre.y)) <= Self.tol)
        #expect(abs(CloudWorld.centreB - Float(CloudProjectionGolden.centre.z)) <= Self.tol)
    }

    @Test func worldMapMatchesGolden() {
        #expect(CloudProjectionGolden.colors.count == CloudProjectionGolden.world.count)
        for (lab, expected) in zip(CloudProjectionGolden.colors, CloudProjectionGolden.world) {
            // Golden `colors` are (L, a, b); `CloudWorld.map` reads lab as (x=L, y=a, z=b).
            let got = CloudWorld.map(SIMD3<Float>(Float(lab.x), Float(lab.y), Float(lab.z)))
            #expect(abs(got.x - Float(expected.x)) <= Self.tol,
                    "x \(got.x) vs \(expected.x)")
            #expect(abs(got.y - Float(expected.y)) <= Self.tol,
                    "y \(got.y) vs \(expected.y)")
            #expect(abs(got.z - Float(expected.z)) <= Self.tol,
                    "z \(got.z) vs \(expected.z)")
        }
    }
}
