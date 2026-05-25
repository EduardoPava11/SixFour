import Testing
import Foundation
import simd
@testable import SixFour

/// GPU↔CPU parity for Octree: the hybrid `OctreePalettePipeline` (CPU
/// insert+merge core + GPU per-cluster stats) must agree with the pure-CPU
/// `OctreeReference` oracle. Both share `OctreeQuantizer.assign`, so the
/// partition is IDENTICAL — parity is purely fixed-point vs Double on the
/// covariance/mean moments (no greedy-split divergence, so it's tighter than Wu).
@MainActor
struct OctreeParityTests {

    /// ~400 distinct colours cycled across the tile. Enough to push the octree
    /// past K=256 (so the greedy merge path is exercised) while keeping the
    /// tree small — the reduce is O(merges × poolScan), so a 4096-distinct tile
    /// is needlessly slow for a parity test (parity holds at any diversity).
    private func cycledPaletteTile(side: Int = 64) -> OKLabTile {
        let distinct = 400
        var palette: [SIMD3<Float>] = []
        palette.reserveCapacity(distinct)
        for i in 0..<distinct {
            let l = Float(i % 20) / 19.0                       // 20 levels
            let a = (Float((i / 20) % 20) / 19.0 - 0.5) * 0.6  // 20 levels → 400 (l,a) pairs
            let b = (Float(i % 7) / 6.0 - 0.5) * 0.4
            palette.append(SIMD3<Float>(l, a, b))
        }
        var pixels = [SIMD3<Float>](repeating: .zero, count: side * side)
        for p in 0..<pixels.count { pixels[p] = palette[p % distinct] }
        return OKLabTile(side: side, pixels: pixels, captureNanos: 0, palette: [], finalShift: 0)
    }

    @Test func gpuStatsAgreeWithCpuReference() throws {
        let tile = cycledPaletteTile()
        let K = 256
        let gpu = try OctreePalettePipeline(tileSide: 64).extractBatch(tiles: [tile], K: K)[0]
        let cpu = try OctreeReference().extract(tile: tile, K: K)

        // Partition is shared (OctreeQuantizer.assign) → per-pixel assignments
        // must be byte-identical on both paths.
        #expect(gpu.assignments == cpu.assignments, "Octree GPU vs CPU assignments differ")

        // MSE agreement — the headline quality metric.
        #expect(abs(gpu.provenance.mse - cpu.provenance.mse) < 1e-3,
                "Octree GPU vs CPU MSE: gpu=\(gpu.provenance.mse) cpu=\(cpu.provenance.mse)")

        // Per-cluster mean agreement (same partition → only fixed-point drift).
        for k in 0..<K where cpu.clusters[k].count > 0 {
            let d = gpu.clusters[k].mean - cpu.clusters[k].mean
            let d2 = d.x * d.x + d.y * d.y + d.z * d.z
            #expect(d2 < 1e-6,
                    "Octree cluster \(k) mean: gpu=\(gpu.clusters[k].mean) cpu=\(cpu.clusters[k].mean)")
            #expect(gpu.clusters[k].count == cpu.clusters[k].count,
                    "Octree cluster \(k) count: gpu=\(gpu.clusters[k].count) cpu=\(cpu.clusters[k].count)")
        }
    }
}
