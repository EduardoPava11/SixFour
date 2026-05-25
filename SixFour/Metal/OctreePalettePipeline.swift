import Foundation
import Metal
import simd
import os

/// Hybrid Octree pipeline: CPU sequential core (insert + greedy merge →
/// per-pixel assignments, via `OctreeQuantizer.assign`) + GPU per-cluster stats
/// (`octreeStatsKernel` — the parallel "second pass" that computes mean/Σ/count
/// from the fixed assignments). Its own `palette-octree` logger + labeled queue.
///
/// Because the partition is the shared CPU core, GPU and CPU agree on the
/// assignment exactly; the GPU only changes how moments are summed (fixed-point
/// vs Double), so parity is tighter than Wu's (no greedy-split divergence).
final class OctreePalettePipeline: PalettePipeline, @unchecked Sendable {
    static let logger = Logger(subsystem: "com.sixfour.SixFour", category: "palette-octree")
    /// Must match `OCT_SCALE` in OctreeShaders.metal.
    static let fixedPointScale: Double = 65536

    let gpu: GPUContext
    let tileSide: Int
    var family: ClusterStatistics.Family { .hierarchicalOctree }

    private let statsPSO: any MTLComputePipelineState

    enum OctreePipelineError: Error { case commandFailed, bufferAllocationFailed }

    init(tileSide: Int = 64) throws {
        self.gpu = try GPUContext(queueLabel: "palette-octree")
        self.tileSide = tileSide
        self.statsPSO = try gpu.pso("octreeStatsKernel")
        Self.logger.info("OctreePalettePipeline init: tileSide=\(tileSide) device=\(self.gpu.device.name)")
    }

    func extractBatch(tiles: [OKLabTile], K: Int) throws -> [ClusterStatistics] {
        precondition(!tiles.isEmpty, "OctreePalettePipeline: tiles must be non-empty")
        let pixelCount = tileSide * tileSide
        let started = ContinuousClock().now

        let device = gpu.device
        let pixelBytes = pixelCount * MemoryLayout<SIMD4<Float>>.stride
        let assignBytes = pixelCount * MemoryLayout<UInt16>.stride
        let binBytes = K * 10 * MemoryLayout<Int32>.stride
        guard let pixelBuf = device.makeBuffer(length: pixelBytes, options: [.storageModeShared]),
              let assignBuf = device.makeBuffer(length: assignBytes, options: [.storageModeShared]),
              let binsBuf = device.makeBuffer(length: binBytes, options: [.storageModeShared])
        else { throw OctreePipelineError.bufferAllocationFailed }

        var assignNanos: Int64 = 0   // CPU tree core
        var gpuNanos: Int64 = 0      // GPU stats kernel
        var finalizeNanos: Int64 = 0 // CPU readback + MSE
        var out: [ClusterStatistics] = []
        out.reserveCapacity(tiles.count)

        for tile in tiles {
            // --- CPU sequential core: insert + merge → assignments ---
            let assignStart = ContinuousClock().now
            let (assignments, _) = OctreeQuantizer.assign(pixels: tile.pixels, K: K)
            assignNanos += Self.nanos(ContinuousClock().now - assignStart)

            // --- GPU stats kernel ---
            let gpuStart = ContinuousClock().now
            let pPtr = pixelBuf.contents().bindMemory(to: SIMD4<Float>.self, capacity: pixelCount)
            for i in 0..<pixelCount {
                let p = tile.pixels[i]
                pPtr[i] = SIMD4<Float>(p.x, p.y, p.z, 0)
            }
            let aPtr = assignBuf.contents().bindMemory(to: UInt16.self, capacity: pixelCount)
            for i in 0..<pixelCount { aPtr[i] = assignments[i] }
            memset(binsBuf.contents(), 0, binBytes)

            guard let cmd = gpu.queue.makeCommandBuffer(),
                  let enc = cmd.makeComputeCommandEncoder()
            else { throw OctreePipelineError.commandFailed }
            enc.setComputePipelineState(statsPSO)
            enc.setBuffer(pixelBuf, offset: 0, index: 0)
            enc.setBuffer(assignBuf, offset: 0, index: 1)
            enc.setBuffer(binsBuf, offset: 0, index: 2)
            var pc = UInt32(pixelCount)
            enc.setBytes(&pc, length: MemoryLayout<UInt32>.size, index: 3)
            let tgWidth = min(statsPSO.maxTotalThreadsPerThreadgroup, pixelCount)
            enc.dispatchThreads(
                MTLSize(width: pixelCount, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: tgWidth, height: 1, depth: 1))
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
            if let err = cmd.error {
                Self.logger.error("octreeStats GPU command buffer failed: \(err.localizedDescription)")
                throw OctreePipelineError.commandFailed
            }
            gpuNanos += Self.nanos(ContinuousClock().now - gpuStart)

            // --- CPU readback: bins → clusters, then MSE ---
            let finStart = ContinuousClock().now
            let clusters = Self.clustersFromBins(binsBuf: binsBuf, K: K)
            var sse: Double = 0
            for p in 0..<pixelCount {
                let d = tile.pixels[p] - clusters[Int(assignments[p])].mean
                sse += Double(simd_dot(d, d))
            }
            let mse = Float(sse / Double(pixelCount))
            finalizeNanos += Self.nanos(ContinuousClock().now - finStart)

            out.append(ClusterStatistics(
                clusters: clusters,
                assignments: assignments,
                provenance: ClusterStatistics.Provenance(
                    family: .hierarchicalOctree,
                    parameters: .octree(maxDepth: OctreeQuantizer.maxDepth),
                    extractMillis: Int((assignNanos + gpuNanos + finalizeNanos) / Int64(tiles.count) / 1_000_000),
                    mse: mse)))
        }

        let totalMs = Self.millis(ContinuousClock().now - started)
        Self.logger.info(
            "extractBatch done: frames=\(tiles.count) total=\(totalMs)ms assign(cpu)=\(assignNanos / 1_000_000)ms stats(gpu)=\(gpuNanos / 1_000_000)ms finalize(cpu)=\(finalizeNanos / 1_000_000)ms")
        return out
    }

    private static func clustersFromBins(binsBuf: any MTLBuffer, K: Int) -> [ClusterStatistics.Cluster] {
        let bPtr = binsBuf.contents().bindMemory(to: Int32.self, capacity: K * 10)
        let invS = 1.0 / fixedPointScale
        var clusters = [ClusterStatistics.Cluster](repeating: ClusterStatistics.Cluster(
            mean: .zero, covariance: ClusterStatistics.Cluster.emptyCovariance, count: 0), count: K)
        for k in 0..<K {
            let base = k * 10
            let cnt = Double(bPtr[base + 0])
            if cnt == 0 { continue }
            let inv = 1.0 / cnt
            let sL = Double(bPtr[base + 1]) * invS, sA = Double(bPtr[base + 2]) * invS, sB = Double(bPtr[base + 3]) * invS
            let sLL = Double(bPtr[base + 4]) * invS, sAA = Double(bPtr[base + 5]) * invS, sBB = Double(bPtr[base + 6]) * invS
            let sLA = Double(bPtr[base + 7]) * invS, sLB = Double(bPtr[base + 8]) * invS, sAB = Double(bPtr[base + 9]) * invS
            let mL = sL * inv, mA = sA * inv, mB = sB * inv
            let LL = max(0, sLL * inv - mL * mL)
            let aa = max(0, sAA * inv - mA * mA)
            let bb = max(0, sBB * inv - mB * mB)
            let La = sLA * inv - mL * mA
            let Lb = sLB * inv - mL * mB
            let ab = sAB * inv - mA * mB
            clusters[k] = ClusterStatistics.Cluster(
                mean: SIMD3<Float>(Float(mL), Float(mA), Float(mB)),
                covariance: simd_float3x3(columns: (
                    SIMD3<Float>(Float(LL), Float(La), Float(Lb)),
                    SIMD3<Float>(Float(La), Float(aa), Float(ab)),
                    SIMD3<Float>(Float(Lb), Float(ab), Float(bb)))),
                count: UInt32(cnt))
        }
        return clusters
    }

    private static func nanos(_ d: Duration) -> Int64 {
        let (s, attos) = d.components
        return s * 1_000_000_000 + Int64(attos / 1_000_000_000)
    }
    private static func millis(_ d: Duration) -> Int {
        let (s, attos) = d.components
        return Int(s) * 1_000 + Int(attos / 1_000_000_000_000_000)
    }
}
