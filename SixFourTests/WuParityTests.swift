import Testing
import Foundation
import simd
@testable import SixFour

/// GPU↔CPU parity for Wu: the hybrid `WuPalettePipeline` (GPU moment histogram
/// + shared CPU greedy core) must agree with the pure-CPU `WuReference` oracle.
/// Both feed identical `cellOfPixel` (integer-exact quantization of the same
/// Float32 pixels) into the same `WuQuantizer.quantize`, so the only gap is the
/// fixed-point vs Double moment sums — agreement is tight.
@MainActor
struct WuParityTests {

    /// Smooth gradient: every pixel gets a distinct (L, a, b), so the greedy
    /// box-split landscape is well-separated and won't flip on tiny moment
    /// differences.
    private func gradientTile(side: Int = 64) -> OKLabTile {
        var pixels: [SIMD3<Float>] = []
        pixels.reserveCapacity(side * side)
        for y in 0..<side {
            for x in 0..<side {
                let l = Float(x) / Float(side - 1)
                let a = (Float(y) / Float(side - 1) - 0.5) * 0.6
                let b = ((Float(x + y) / Float(2 * side - 2)) - 0.5) * 0.6
                pixels.append(SIMD3<Float>(l, a, b))
            }
        }
        return OKLabTile(side: side, pixels: pixels, captureNanos: 0, palette: [], finalShift: 0)
    }

    @Test func gpuHistogramAgreesWithCpuReference() throws {
        let tile = gradientTile()
        let K = 256
        let gpu = try WuPalettePipeline(tileSide: 64).extractBatch(tiles: [tile], K: K)[0]
        let cpu = try WuReference().extract(tile: tile, K: K)

        // MSE agreement — the headline quality metric.
        #expect(abs(gpu.provenance.mse - cpu.provenance.mse) < 1e-3,
                "Wu GPU vs CPU MSE: gpu=\(gpu.provenance.mse) cpu=\(cpu.provenance.mse)")

        // Same number of live (non-empty) clusters.
        let cpuMeans = cpu.clusters.filter { $0.count > 0 }.map { $0.mean }
        let gpuMeans = gpu.clusters.filter { $0.count > 0 }.map { $0.mean }
        #expect(cpuMeans.count == gpuMeans.count,
                "Wu live-cluster count: cpu=\(cpuMeans.count) gpu=\(gpuMeans.count)")

        // Set-wise centroid agreement within quantization resolution. Greedy
        // bipartition is sensitive to tie-breaks: on a perfectly regular
        // gradient, the GPU's fixed-point moments vs the CPU's Double sums can
        // flip a single split, shifting a band of centroids by ~half a 32³ bin
        // (~0.016 OKLab) at equal MSE. 5e-3 (√≈0.07) is the same tolerance
        // MetalKMeansTests uses for GPU↔CPU quantizer parity.
        for c in cpuMeans {
            var best: Float = .infinity
            for g in gpuMeans {
                let d = c - g
                let d2 = d.x * d.x + d.y * d.y + d.z * d.z
                if d2 < best { best = d2 }
            }
            #expect(best < 5e-3,
                    "Wu CPU centroid \(c) has no GPU match within √5e-3 (best \(best.squareRoot()))")
        }
    }
}
