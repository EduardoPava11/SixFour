import Testing
import Foundation
import Metal
import simd
@testable import SixFour

/// Verifies the `v21AccumulateHistKernel` GPU dispatch (the V2.1 camera-box probability accumulator)
/// against the STRUCTURAL invariants of `SixFour.Spec.V21Field` / Zig `s4_v21_accumulate_hist`, and the
/// `MetalPipeline.poolV21Counts` time-pool. This closes the audit's open "no runtime Metal == Zig
/// golden" gap for the laws that do not depend on the colour-conversion values:
///
///   * lawHistCellSumsToCellSize: each (voxel, channel) histogram sums to scale² (the box it owns).
///   * lawHistUniformIsSpike: a uniform input box collapses to a single histogram spike.
///   * lawHistTotalPreserved: total counts == coarseVoxels · 3 · scale².
///
/// The exact value LEVELS depend on the shared YCbCr->linear path (trusted, reused from the box-average
/// kernel), so the test uses uniform input and checks the spike STRUCTURE, not which bin it lands in.
/// Metal runs in the simulator, so this is verifiable headless (no camera needed).
struct V21MetalParityTests {

    private func uniformLuma(_ device: any MTLDevice, side: Int, value: UInt16) throws -> any MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Unorm, width: side, height: side, mipmapped: false)
        desc.usage = [.shaderRead]; desc.storageMode = .shared
        let tex = try #require(device.makeTexture(descriptor: desc))
        var data = [UInt16](repeating: value, count: side * side)
        data.withUnsafeBytes { tex.replace(region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: side * 2) }
        return tex
    }

    private func uniformChroma(_ device: any MTLDevice, side: Int, cb: UInt16, cr: UInt16) throws -> any MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg16Unorm, width: side, height: side, mipmapped: false)
        desc.usage = [.shaderRead]; desc.storageMode = .shared
        let tex = try #require(device.makeTexture(descriptor: desc))
        var data = [UInt16](); data.reserveCapacity(side * side * 2)
        for _ in 0 ..< side * side { data.append(cb); data.append(cr) }
        data.withUnsafeBytes { tex.replace(region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: side * 4) }
        return tex
    }

    /// Dispatch the kernel once at slice `coarseFrame` into `outBuf`. Mirrors `encodeV21Hist` bindings.
    private func dispatch(_ pipe: MetalPipeline, luma: any MTLTexture, chroma: any MTLTexture,
                          outBuf: any MTLBuffer, scale: Int, nLevels: Int, coarse: Int, coarseFrame: Int) throws {
        let pso = try #require(pipe.v21HistPSO)   // V2.1 PSO is optional on the pipeline; required here
        let cmd = try #require(pipe.queue.makeCommandBuffer())
        let enc = try #require(cmd.makeComputeCommandEncoder())
        var offset = SIMD2<Int32>(0, 0)
        var sc = Int32(scale), tag = UInt8(0), lv = Int32(nLevels)
        var cd = SIMD2<Int32>(Int32(coarse), Int32(coarse))
        var cf = Int32(coarseFrame)
        enc.setComputePipelineState(pso)
        enc.setTexture(luma, index: 0)
        enc.setTexture(chroma, index: 1)
        enc.setBuffer(outBuf, offset: 0, index: 0)
        enc.setBytes(&offset, length: MemoryLayout<SIMD2<Int32>>.size, index: 1)
        enc.setBytes(&sc, length: MemoryLayout<Int32>.size, index: 2)
        enc.setBytes(&tag, length: MemoryLayout<UInt8>.size, index: 3)
        enc.setBytes(&lv, length: MemoryLayout<Int32>.size, index: 4)
        enc.setBytes(&cd, length: MemoryLayout<SIMD2<Int32>>.size, index: 5)
        enc.setBytes(&cf, length: MemoryLayout<Int32>.size, index: 6)
        let w = pso.threadExecutionWidth
        let h = max(1, pso.maxTotalThreadsPerThreadgroup / w)
        enc.dispatchThreads(MTLSize(width: coarse, height: coarse, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1))
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
    }

    /// Single frame, uniform input: every voxel/channel is a spike summing to scale² (the box size).
    @Test func kernelConservesAndSpikesOnUniformInput() throws {
        let pipe = try MetalPipeline()
        let coarse = 4, scale = 2, nLevels = 8, src = coarse * scale   // 8x8 luma, 4x4 chroma
        let luma = try uniformLuma(pipe.device, side: src, value: 0x8000)
        let chroma = try uniformChroma(pipe.device, side: src / 2, cb: 0x8000, cr: 0x8000)
        let count = coarse * coarse * 3 * nLevels
        // u16 counts (PERF 2026-07-08): the kernel writes ushort, so the buffer is 2 B/cell.
        let outBuf = try #require(pipe.device.makeBuffer(length: count * 2, options: [.storageModeShared]))

        try dispatch(pipe, luma: luma, chroma: chroma, outBuf: outBuf,
                     scale: scale, nLevels: nLevels, coarse: coarse, coarseFrame: 0)

        let ptr = outBuf.contents().bindMemory(to: UInt16.self, capacity: count)
        var total = 0
        for v in 0 ..< coarse * coarse {
            for ch in 0 ..< 3 {
                let base = (v * 3 + ch) * nLevels
                var sum = 0, nonzeroBins = 0
                for l in 0 ..< nLevels {
                    let c = Int(ptr[base + l]); sum += c
                    if c != 0 { nonzeroBins += 1; #expect(c == scale * scale) }   // spike value = box size
                }
                #expect(sum == scale * scale)        // lawHistCellSumsToCellSize
                #expect(nonzeroBins == 1)            // lawHistUniformIsSpike
            }
        }
        for i in 0 ..< count { total += Int(ptr[i]) }
        #expect(total == coarse * coarse * 3 * scale * scale)   // lawHistTotalPreserved
    }

    /// Dispatch the SOFT-splat kernel once. Mirrors `encodeV21Hist`'s soft path (budget at index 7).
    private func dispatchSoft(_ pipe: MetalPipeline, luma: any MTLTexture, chroma: any MTLTexture,
                              outBuf: any MTLBuffer, scale: Int, nLevels: Int, coarse: Int,
                              coarseFrame: Int, budget: Int32) throws {
        let pso = try #require(pipe.v21HistSoftPSO)   // soft PSO is optional; required for this test
        let cmd = try #require(pipe.queue.makeCommandBuffer())
        let enc = try #require(cmd.makeComputeCommandEncoder())
        var offset = SIMD2<Int32>(0, 0)
        var sc = Int32(scale), tag = UInt8(0), lv = Int32(nLevels)
        var cd = SIMD2<Int32>(Int32(coarse), Int32(coarse))
        var cf = Int32(coarseFrame)
        var wb = budget
        enc.setComputePipelineState(pso)
        enc.setTexture(luma, index: 0)
        enc.setTexture(chroma, index: 1)
        enc.setBuffer(outBuf, offset: 0, index: 0)
        enc.setBytes(&offset, length: MemoryLayout<SIMD2<Int32>>.size, index: 1)
        enc.setBytes(&sc, length: MemoryLayout<Int32>.size, index: 2)
        enc.setBytes(&tag, length: MemoryLayout<UInt8>.size, index: 3)
        enc.setBytes(&lv, length: MemoryLayout<Int32>.size, index: 4)
        enc.setBytes(&cd, length: MemoryLayout<SIMD2<Int32>>.size, index: 5)
        enc.setBytes(&cf, length: MemoryLayout<Int32>.size, index: 6)
        enc.setBytes(&wb, length: MemoryLayout<Int32>.size, index: 7)
        let w = pso.threadExecutionWidth
        let h = max(1, pso.maxTotalThreadsPerThreadgroup / w)
        enc.dispatchThreads(MTLSize(width: coarse, height: coarse, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1))
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
    }

    /// Soft splat, uniform input: each voxel/channel totals scale²·budget (mass conserved), and the
    /// mass lands on AT MOST two ADJACENT levels (lawSoftSplatIsLocal). This closes the runtime
    /// Metal==spec gap for the sub-LSB construction's value-independent laws.
    @Test func softKernelConservesMassAndIsLocal() throws {
        let pipe = try MetalPipeline()
        let coarse = 4, scale = 2, nLevels = 8, src = coarse * scale
        let budget: Int32 = 16
        let luma = try uniformLuma(pipe.device, side: src, value: 0x5000)     // mid-ish, likely between levels
        let chroma = try uniformChroma(pipe.device, side: src / 2, cb: 0x8000, cr: 0x8000)
        let count = coarse * coarse * 3 * nLevels
        // u16 counts (PERF 2026-07-08): 2 B/cell; cell mass scale²·budget = 64 ≪ 65535.
        let outBuf = try #require(pipe.device.makeBuffer(length: count * 2, options: [.storageModeShared]))

        try dispatchSoft(pipe, luma: luma, chroma: chroma, outBuf: outBuf,
                         scale: scale, nLevels: nLevels, coarse: coarse, coarseFrame: 0, budget: budget)

        let ptr = outBuf.contents().bindMemory(to: UInt16.self, capacity: count)
        var total = 0
        let cellMass = scale * scale * Int(budget)
        for v in 0 ..< coarse * coarse {
            for ch in 0 ..< 3 {
                let base = (v * 3 + ch) * nLevels
                var sum = 0
                var nonzero: [Int] = []
                for l in 0 ..< nLevels {
                    let c = Int(ptr[base + l]); sum += c
                    if c != 0 { nonzero.append(l) }
                }
                #expect(sum == cellMass)                       // partition of unity: box·budget
                #expect(nonzero.count <= 2)                    // locality: at most two levels
                if nonzero.count == 2 {
                    #expect(nonzero[1] == nonzero[0] + 1)      // ...and they are adjacent
                }
            }
        }
        for i in 0 ..< count { total += Int(ptr[i]) }
        #expect(total == coarse * coarse * 3 * cellMass)       // lawSoftHistTotalPreserved (box·budget)
    }

    /// Two frames into a 2-slice buffer, then pooled over t: each voxel/channel sums to 2·scale².
    @Test func burstPoolsOverTime() throws {
        let pipe = try MetalPipeline()
        let coarse = 4, scale = 2, nLevels = 8, frames = 2, src = coarse * scale
        let luma = try uniformLuma(pipe.device, side: src, value: 0x6000)
        let chroma = try uniformChroma(pipe.device, side: src / 2, cb: 0x8000, cr: 0x8000)
        // Allocate to our small coarse dims directly (makeV21HistBuffer is sized to the 64 tile).
        let count = frames * coarse * coarse * 3 * nLevels
        let outBuf = try #require(pipe.device.makeBuffer(length: count * 2, options: [.storageModeShared]))
        for t in 0 ..< frames {
            try dispatch(pipe, luma: luma, chroma: chroma, outBuf: outBuf,
                         scale: scale, nLevels: nLevels, coarse: coarse, coarseFrame: t)
        }
        // Pool over t into [coarse², 3, nLevels] — widening u16 → Int32 like poolV21Counts.
        let spatial = coarse * coarse * 3 * nLevels
        var pooled = [Int32](repeating: 0, count: spatial)
        let ptr = outBuf.contents().bindMemory(to: UInt16.self, capacity: count)
        for t in 0 ..< frames { for i in 0 ..< spatial { pooled[i] &+= Int32(ptr[t * spatial + i]) } }

        for v in 0 ..< coarse * coarse {
            for ch in 0 ..< 3 {
                let base = (v * 3 + ch) * nLevels
                let sum = (0 ..< nLevels).reduce(0) { $0 + Int(pooled[base + $1]) }
                #expect(sum == frames * scale * scale)
            }
        }
    }

    /// `poolV21Counts` sums the t slices exactly (pure-logic check, no GPU).
    @Test func poolV21CountsSumsSlices() throws {
        let pipe = try MetalPipeline()
        // tileSide 1, nLevels 2, frames 2 -> spatial = 1·1·3·2 = 6, buffer = 12 UInt16.
        let frames = 2, nLevels = 2, tileSide = 1
        let spatial = tileSide * tileSide * 3 * nLevels
        let buf = try #require(pipe.device.makeBuffer(length: frames * spatial * 2, options: [.storageModeShared]))
        let p = buf.contents().bindMemory(to: UInt16.self, capacity: frames * spatial)
        let frame0: [UInt16] = [1, 0, 2, 0, 3, 0]
        let frame1: [UInt16] = [0, 1, 0, 2, 0, 3]
        for i in 0 ..< spatial { p[i] = frame0[i]; p[spatial + i] = frame1[i] }
        let pooled = MetalPipeline.poolV21Counts(buffer: buf, frames: frames, tileSide: tileSide, nLevels: nLevels)
        #expect(pooled == [1, 1, 2, 2, 3, 3])
    }
}
