import Testing
import Foundation
import simd
@testable import SixFour

/// Parity + microbenchmark for the SIMD8 nearest-centroid kernel
/// (`CentroidSet`) that backs the error-diffusion dither.
///
/// Parity is asserted on **distance**, not index: the SIMD8 argmin and the
/// scalar oracle can pick different (equidistant) centroids on exact ties,
/// which is harmless — the reconstruction error is identical. This mirrors
/// the project's existing GPU-vs-CPU parity convention (Wu/Octree/MetalKMeans
/// all compare within a d² tolerance).
struct NearestCentroidTests {

    /// Deterministic LCG so the fixture is reproducible.
    private struct LCG {
        var s: UInt64
        init(_ seed: UInt64) { s = seed &+ 0x9E37_79B9_7F4A_7C15 }
        mutating func f01() -> Float {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return Float(s >> 40) / Float(1 << 24)
        }
        mutating func oklab() -> SIMD3<Float> {
            SIMD3<Float>(f01(), f01() - 0.5, f01() - 0.5)
        }
    }

    private func makePalette(_ k: Int, seed: UInt64) -> [SIMD3<Float>] {
        var rng = LCG(seed)
        return (0..<k).map { _ in rng.oklab() }
    }

    private func makePixels(_ n: Int, seed: UInt64) -> [SIMD3<Float>] {
        var rng = LCG(seed)
        return (0..<n).map { _ in rng.oklab() }
    }

    @inline(__always)
    private func d2(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let d = a - b; return simd_dot(d, d)
    }

    // MARK: - Parity

    @Test func simd8AgreesWithScalarOnDistance() {
        let palette = makePalette(256, seed: 11)
        let cs = CentroidSet(palette)
        let pixels = makePixels(4096, seed: 22)
        var maxGap: Float = 0
        for p in pixels {
            let kSIMD = cs.nearest(p)
            let kScalar = cs.nearestScalar(p)
            // Equidistant ties are allowed; the distances must match tightly.
            let gap = abs(d2(p, palette[kSIMD]) - d2(p, palette[kScalar]))
            maxGap = max(maxGap, gap)
        }
        #expect(maxGap < 1e-6, "SIMD8 nearest disagrees with scalar by d²=\(maxGap)")
    }

    /// Non-multiple-of-8 K exercises the padding lanes (they must never win).
    @Test func paddingLanesNeverWinForNonMultipleOf8K() {
        for k in [1, 7, 9, 100, 255] {
            let palette = makePalette(k, seed: UInt64(k))
            let cs = CentroidSet(palette)
            #expect(cs.paddedCount % 8 == 0)
            for p in makePixels(512, seed: 99) {
                let idx = cs.nearest(p)
                #expect(idx >= 0 && idx < k, "index \(idx) out of range for K=\(k)")
            }
        }
    }

    /// The full dither: SIMD8 path vs the scalar generic oracle must yield the
    /// same reconstruction MSE (tie divergence can shift individual indices,
    /// but mean error is invariant within tolerance).
    @Test func ditherSIMDMatchesScalarMSE() {
        let palette = makePalette(256, seed: 7)
        let pixels = makePixels(64 * 64, seed: 8)
        let tile = OKLabTile(side: 64, pixels: pixels, captureNanos: 0, palette: palette, finalShift: 0)

        let scalarIdx = Dither.errorDiffuse(
            tile: tile, palette: palette, metric: EuclideanOKLabMetric(), kernel: .floydSteinberg
        )
        let simdIdx = Dither.errorDiffuseSIMD(
            tile: tile, centroids: CentroidSet(palette), kernel: .floydSteinberg
        )

        func mse(_ idx: [UInt8]) -> Float {
            var s: Float = 0
            for i in 0..<pixels.count { s += d2(pixels[i], palette[Int(idx[i])]) }
            return s / Float(pixels.count)
        }
        #expect(abs(mse(scalarIdx) - mse(simdIdx)) < 1e-4,
                "SIMD8 dither MSE \(mse(simdIdx)) vs scalar \(mse(scalarIdx))")
    }

    // MARK: - Microbenchmark (informational; real perf numbers come from device)

    @Test func benchmarkScalarVsSIMD8() {
        let palette = makePalette(256, seed: 3)
        let cs = CentroidSet(palette)
        let pixels = makePixels(4096, seed: 4)

        // Warm up + prevent dead-code elimination via an accumulator.
        var acc = 0
        func time(_ body: () -> Void) -> Double {
            let t0 = ContinuousClock().now
            body()
            let dt = ContinuousClock().now - t0
            let (s, attos) = dt.components
            return Double(s) * 1000 + Double(attos) / 1e15
        }

        // Hoist the probe once per timing run (as the dither does) so we
        // measure the kernel, not per-call pointer setup.
        let reps = 20
        let scalarMs = time {
            cs.withProbe { probe in
                for _ in 0..<reps { for p in pixels { acc &+= probe.nearestScalar(p) } }
            }
        }
        let simdMs = time {
            cs.withProbe { probe in
                for _ in 0..<reps { for p in pixels { acc &+= probe.nearest(p) } }
            }
        }
        let perCapScalar = scalarMs / Double(reps) * 64.0   // ×64 frames
        let perCapSimd = simdMs / Double(reps) * 64.0
        print("[bench] nearest-centroid 4096px×256, ×64 frames/capture:")
        print("[bench]   scalar: \(String(format: "%.2f", perCapScalar)) ms/capture")
        print("[bench]   SIMD8 : \(String(format: "%.2f", perCapSimd)) ms/capture  (\(String(format: "%.2fx", scalarMs / max(simdMs, 1e-9))))")
        #expect(acc != Int.min)  // keep `acc` live
    }
}
