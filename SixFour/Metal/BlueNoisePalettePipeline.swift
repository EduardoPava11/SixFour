import Foundation
import Metal
import simd
import os

/// GPU blue-noise palette assignment — the parallel counterpart of
/// `Dither.blueNoiseSIMD`, dispatched as one thread per pixel via the
/// `blueNoiseAssignKernel` compute shader. Because ordered dithering has no
/// inter-pixel dependency (unlike sequential error diffusion), the whole frame
/// runs in parallel on the GPU.
///
/// This is the straightforward per-pixel brute-force kernel: every thread
/// scans all K centroids for its two nearest. The A19 Pro's GPU **Neural
/// Accelerators** (Metal 4 TensorOps) could instead compute the N×K distance
/// matrix as a single matmul (`argmax_c(2·X·Cᵀ − ‖c‖²)`, top-2 per row) and
/// fuse the blue-noise pick — a meaningful win at K=256 — but that path is
/// only worth measuring on-device (the simulator's GPU is the Mac's, not the
/// A19 Pro), so it's deferred to the device benchmark. This kernel is the
/// correct, parity-verified baseline that the tensor variant must match.
final class BlueNoisePalettePipeline: @unchecked Sendable {
    static let logger = Logger(subsystem: "com.sixfour.SixFour", category: "palette-bluenoise")

    let gpu: GPUContext
    private let pso: any MTLComputePipelineState

    enum BlueNoiseError: Error { case bufferCreationFailed, commandFailed }

    init() throws {
        self.gpu = try GPUContext(queueLabel: "palette-bluenoise")
        self.pso = try gpu.pso("blueNoiseAssignKernel")
    }

    var device: any MTLDevice { gpu.device }

    /// Assign each pixel to a palette index via blue-noise ordered dithering.
    /// `thresholds[i] ∈ 0...255` is this frame's STBN3D mask slice. Returns one
    /// `UInt8` index per pixel. Surjectivity is NOT guaranteed here — the
    /// caller must follow with `PerFrameSurjectivity.rescue`, exactly as the
    /// CPU path does.
    func assign(
        pixels: [SIMD3<Float>],
        centroids: [SIMD3<Float>],
        thresholds: [UInt8]
    ) throws -> [UInt8] {
        let n = pixels.count
        let k = centroids.count
        precondition(k <= 256, "Palette must fit in UInt8")
        precondition(thresholds.count == n, "thresholds must be one per pixel")

        let stride3 = MemoryLayout<SIMD3<Float>>.stride   // 16 bytes — matches Metal float3
        guard
            let pxBuf  = device.makeBuffer(bytes: pixels,     length: n * stride3, options: [.storageModeShared]),
            let cBuf   = device.makeBuffer(bytes: centroids,  length: k * stride3, options: [.storageModeShared]),
            let thBuf  = device.makeBuffer(bytes: thresholds, length: n,           options: [.storageModeShared]),
            let outBuf = device.makeBuffer(length: n, options: [.storageModeShared])
        else { throw BlueNoiseError.bufferCreationFailed }

        guard
            let cmd = gpu.queue.makeCommandBuffer(),
            let enc = cmd.makeComputeCommandEncoder()
        else { throw BlueNoiseError.commandFailed }

        var kVar = UInt32(k)
        var nVar = UInt32(n)
        enc.setComputePipelineState(pso)
        enc.setBuffer(pxBuf,  offset: 0, index: 0)
        enc.setBuffer(cBuf,   offset: 0, index: 1)
        enc.setBuffer(thBuf,  offset: 0, index: 2)
        enc.setBuffer(outBuf, offset: 0, index: 3)
        enc.setBytes(&kVar, length: MemoryLayout<UInt32>.size, index: 4)
        enc.setBytes(&nVar, length: MemoryLayout<UInt32>.size, index: 5)
        let tg = MTLSize(width: min(pso.maxTotalThreadsPerThreadgroup, max(n, 1)), height: 1, depth: 1)
        enc.dispatchThreads(MTLSize(width: n, height: 1, depth: 1), threadsPerThreadgroup: tg)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        if let err = cmd.error {
            Self.logger.error("blueNoiseAssign GPU failed: \(err.localizedDescription)")
            throw BlueNoiseError.commandFailed
        }

        let outPtr = outBuf.contents().bindMemory(to: UInt8.self, capacity: n)
        return Array(UnsafeBufferPointer(start: outPtr, count: n))
    }

    /// Batched assignment: all frames in ONE command buffer (one commit/wait),
    /// which is the configuration that amortizes GPU dispatch overhead across
    /// the 64-frame burst — the fair comparison against the per-frame CPU path.
    /// `pixels`/`centroids`/`thresholds` are parallel arrays, one entry per
    /// frame. Returns per-frame index arrays.
    func assignBatch(
        pixels: [[SIMD3<Float>]],
        centroids: [[SIMD3<Float>]],
        thresholds: [[UInt8]]
    ) throws -> [[UInt8]] {
        let frames = pixels.count
        precondition(centroids.count == frames && thresholds.count == frames,
                     "assignBatch: parallel arrays must be the same length")
        guard frames > 0 else { return [] }

        let stride3 = MemoryLayout<SIMD3<Float>>.stride
        guard let cmd = gpu.queue.makeCommandBuffer() else { throw BlueNoiseError.commandFailed }

        var outBufs: [any MTLBuffer] = []
        var counts: [Int] = []
        outBufs.reserveCapacity(frames)
        counts.reserveCapacity(frames)

        for f in 0..<frames {
            let n = pixels[f].count
            let k = centroids[f].count
            precondition(k <= 256, "Palette must fit in UInt8")
            precondition(thresholds[f].count == n, "thresholds must be one per pixel")
            guard
                let pxBuf  = device.makeBuffer(bytes: pixels[f],     length: n * stride3, options: [.storageModeShared]),
                let cBuf   = device.makeBuffer(bytes: centroids[f],  length: k * stride3, options: [.storageModeShared]),
                let thBuf  = device.makeBuffer(bytes: thresholds[f], length: n,           options: [.storageModeShared]),
                let outBuf = device.makeBuffer(length: n, options: [.storageModeShared]),
                let enc = cmd.makeComputeCommandEncoder()
            else { throw BlueNoiseError.bufferCreationFailed }

            var kVar = UInt32(k)
            var nVar = UInt32(n)
            enc.setComputePipelineState(pso)
            enc.setBuffer(pxBuf,  offset: 0, index: 0)
            enc.setBuffer(cBuf,   offset: 0, index: 1)
            enc.setBuffer(thBuf,  offset: 0, index: 2)
            enc.setBuffer(outBuf, offset: 0, index: 3)
            enc.setBytes(&kVar, length: MemoryLayout<UInt32>.size, index: 4)
            enc.setBytes(&nVar, length: MemoryLayout<UInt32>.size, index: 5)
            let tg = MTLSize(width: min(pso.maxTotalThreadsPerThreadgroup, max(n, 1)), height: 1, depth: 1)
            enc.dispatchThreads(MTLSize(width: n, height: 1, depth: 1), threadsPerThreadgroup: tg)
            enc.endEncoding()
            outBufs.append(outBuf)
            counts.append(n)
        }

        cmd.commit()
        cmd.waitUntilCompleted()
        if let err = cmd.error {
            Self.logger.error("assignBatch GPU failed: \(err.localizedDescription)")
            throw BlueNoiseError.commandFailed
        }

        return (0..<frames).map { f in
            let p = outBufs[f].contents().bindMemory(to: UInt8.self, capacity: counts[f])
            return Array(UnsafeBufferPointer(start: p, count: counts[f]))
        }
    }
}
