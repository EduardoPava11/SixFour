import Foundation
import Metal
import simd
import os

/// Hybrid Wu pipeline: GPU 3-D moment histogram (the genuinely parallel stage)
/// + the shared CPU `WuQuantizer` greedy core. Its own `palette-wu` logger +
/// labeled command queue, so its per-stage GPU/CPU timings are attributable
/// independently of k-means and octree.
///
/// Honest scope: at 4096 px the GPU footprint is the histogram only; the
/// inherently-sequential 3-D prefix-sum + 255-way greedy box-split run on CPU
/// (`WuQuantizer`). The per-stage log line makes that split explicit, which is
/// the point of giving each algorithm its own instrumented pipeline.
final class WuPalettePipeline: PalettePipeline, @unchecked Sendable {
    static let logger = Logger(subsystem: "com.sixfour.SixFour", category: "palette-wu")
    /// Must match `WU_SCALE` in WuShaders.metal.
    static let fixedPointScale: Double = 65536

    let gpu: GPUContext
    let tileSide: Int
    var family: ClusterStatistics.Family { .recursiveBipartitionWu }

    private let histogramPSO: any MTLComputePipelineState

    enum WuPipelineError: Error { case commandFailed, bufferAllocationFailed }

    init(tileSide: Int = 64) throws {
        self.gpu = try GPUContext(queueLabel: "palette-wu")
        self.tileSide = tileSide
        self.histogramPSO = try gpu.pso("wuHistogramKernel")
        Self.logger.info("WuPalettePipeline init: tileSide=\(tileSide) device=\(self.gpu.device.name)")
    }

    func extractBatch(tiles: [OKLabTile], K: Int) throws -> [ClusterStatistics] {
        precondition(!tiles.isEmpty, "WuPalettePipeline: tiles must be non-empty")
        let N = WuQuantizer.binsPerAxis
        let cells = N * N * N
        let pixelCount = tileSide * tileSide
        let started = ContinuousClock().now

        let device = gpu.device
        // Buffers reused across tiles: 1 pixel input, 10 moment tables, 1 cellOfPixel.
        let pixelBytes = pixelCount * MemoryLayout<SIMD4<Float>>.stride
        let momentBytes = cells * MemoryLayout<Int32>.stride
        let cellBytes = pixelCount * MemoryLayout<UInt32>.stride
        guard let pixelBuf = device.makeBuffer(length: pixelBytes, options: [.storageModeShared]),
              let cellBuf = device.makeBuffer(length: cellBytes, options: [.storageModeShared])
        else { throw WuPipelineError.bufferAllocationFailed }
        var momentBufs: [any MTLBuffer] = []
        momentBufs.reserveCapacity(10)
        for _ in 0..<10 {
            guard let b = device.makeBuffer(length: momentBytes, options: [.storageModeShared])
            else { throw WuPipelineError.bufferAllocationFailed }
            momentBufs.append(b)
        }

        var gpuNanos: Int64 = 0
        var cpuNanos: Int64 = 0
        var out: [ClusterStatistics] = []
        out.reserveCapacity(tiles.count)

        for tile in tiles {
            // --- GPU histogram stage ---
            let gpuStart = ContinuousClock().now
            let pPtr = pixelBuf.contents().bindMemory(to: SIMD4<Float>.self, capacity: pixelCount)
            for i in 0..<pixelCount {
                let p = tile.pixels[i]
                pPtr[i] = SIMD4<Float>(p.x, p.y, p.z, 0)
            }
            for b in momentBufs { memset(b.contents(), 0, momentBytes) }

            guard let cmd = gpu.queue.makeCommandBuffer(),
                  let enc = cmd.makeComputeCommandEncoder()
            else { throw WuPipelineError.commandFailed }
            enc.setComputePipelineState(histogramPSO)
            enc.setBuffer(pixelBuf, offset: 0, index: 0)
            for (i, b) in momentBufs.enumerated() { enc.setBuffer(b, offset: 0, index: 1 + i) }
            enc.setBuffer(cellBuf, offset: 0, index: 11)
            var pc = UInt32(pixelCount)
            enc.setBytes(&pc, length: MemoryLayout<UInt32>.size, index: 12)
            let tgWidth = min(histogramPSO.maxTotalThreadsPerThreadgroup, pixelCount)
            enc.dispatchThreads(
                MTLSize(width: pixelCount, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: tgWidth, height: 1, depth: 1))
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
            if let err = cmd.error {
                Self.logger.error("wuHistogram GPU command buffer failed: \(err.localizedDescription)")
                throw WuPipelineError.commandFailed
            }
            gpuNanos += Self.nanos(ContinuousClock().now - gpuStart)

            // --- CPU greedy core (shared with WuReference) ---
            let cpuStart = ContinuousClock().now
            let histogram = Self.readbackHistogram(
                momentBufs: momentBufs, cellBuf: cellBuf, cells: cells, pixelCount: pixelCount)
            let r = WuQuantizer.quantize(histogram, pixels: tile.pixels, K: K)
            let tileCPUNanos = Self.nanos(ContinuousClock().now - cpuStart)
            cpuNanos += tileCPUNanos

            out.append(ClusterStatistics(
                clusters: r.clusters,
                assignments: r.assignments,
                provenance: ClusterStatistics.Provenance(
                    family: .recursiveBipartitionWu,
                    parameters: .wu(histogramBinsPerAxis: N),
                    extractMillis: Int((gpuNanos + cpuNanos) / Int64(tiles.count) / 1_000_000),
                    mse: r.mse)))
        }

        let totalMs = Self.millis(ContinuousClock().now - started)
        Self.logger.info(
            "extractBatch done: frames=\(tiles.count) total=\(totalMs)ms histogram(gpu)=\(gpuNanos / 1_000_000)ms quantize(cpu)=\(cpuNanos / 1_000_000)ms")
        return out
    }

    private static func readbackHistogram(
        momentBufs: [any MTLBuffer], cellBuf: any MTLBuffer, cells: Int, pixelCount: Int
    ) -> WuQuantizer.Histogram {
        func table(_ idx: Int, scaled: Bool) -> [Double] {
            let ptr = momentBufs[idx].contents().bindMemory(to: Int32.self, capacity: cells)
            var arr = [Double](repeating: 0, count: cells)
            if scaled {
                let inv = 1.0 / fixedPointScale
                for c in 0..<cells { arr[c] = Double(ptr[c]) * inv }
            } else {
                for c in 0..<cells { arr[c] = Double(ptr[c]) }
            }
            return arr
        }
        let cPtr = cellBuf.contents().bindMemory(to: UInt32.self, capacity: pixelCount)
        var cellOfPixel = [Int](repeating: 0, count: pixelCount)
        for i in 0..<pixelCount { cellOfPixel[i] = Int(cPtr[i]) }
        // Buffer index ↔ table mapping (see kernel + encoder): 0 hist, 1 sumL, 2 sumA,
        // 3 sumB, 4 sumLL, 5 sumAA, 6 sumBB, 7 sumLA, 8 sumLB, 9 sumAB.
        return WuQuantizer.Histogram(
            hist: table(0, scaled: false),
            sumL: table(1, scaled: true), sumA: table(2, scaled: true), sumB: table(3, scaled: true),
            sumLL: table(4, scaled: true), sumAA: table(5, scaled: true), sumBB: table(6, scaled: true),
            sumLA: table(7, scaled: true), sumLB: table(8, scaled: true), sumAB: table(9, scaled: true),
            cellOfPixel: cellOfPixel)
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
