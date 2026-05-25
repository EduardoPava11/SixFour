import Testing
import Foundation
import Metal
import simd
@testable import SixFour

/// Parity + convergence tests for the GPU Lloyd k-means kernels in
/// `Shaders.metal`, driven via `KMeansPalettePipeline.encodeKMeans`. The point of
/// these tests is to ensure the GPU path agrees with the CPU `KMeansLab.run`
/// reference within tolerable numerical drift after 15 iterations — the
/// fixed iteration count used in production submission.
struct MetalKMeansTests {

    /// Run the GPU k-means kernels directly on a host-supplied OKLab tile
    /// and return the final centroids + shift. Mirrors what
    /// `MetalPipeline.submitAsync` does internally, but without the camera
    /// path so the test is hermetic.
    private struct GPURun {
        let centroids: [SIMD3<Float>]
        let finalShift: Float
    }

    @MainActor
    private func runGPU(pixels: [SIMD3<Float>], side: Int, K: Int, iterations: Int) throws -> GPURun {
        let pipeline = try KMeansPalettePipeline(tileSide: side, kMeansK: K)
        pipeline.kMeansIterations = iterations
        let device = pipeline.device

        // Build an OKLab tile texture (RGBA16F shared storage so we can write to it).
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: side, height: side, mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .shared
        let tile = try #require(device.makeTexture(descriptor: desc))

        var halfRow = [SIMD4<Float16>](repeating: .zero, count: side * side)
        for i in 0..<pixels.count {
            let p = pixels[i]
            halfRow[i] = SIMD4<Float16>(Float16(p.x), Float16(p.y), Float16(p.z), 1)
        }
        let bytesPerRow = side * MemoryLayout<SIMD4<Float16>>.stride
        halfRow.withUnsafeBytes { ptr in
            tile.replace(
                region: MTLRegionMake2D(0, 0, side, side),
                mipmapLevel: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: bytesPerRow
            )
        }

        let centroidsBytes  = K * MemoryLayout<SIMD4<Float>>.stride
        let binsBytes       = K * KMeansPalettePipeline.kMeansBinStride
        let assignmentBytes = side * side * MemoryLayout<UInt16>.stride
        let centroids   = try #require(device.makeBuffer(length: centroidsBytes,  options: [.storageModeShared]))
        let bins        = try #require(device.makeBuffer(length: binsBytes,       options: [.storageModePrivate]))
        let shift       = try #require(device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: [.storageModeShared]))
        // assignments buffer added when KMeansBin gained covariance
        // atomics; the assign+accumulate kernel now writes per-pixel
        // assignments here for downstream MSE / editing-tool use.
        // This test doesn't read assignments back — it only checks
        // centroid parity — but the buffer is required by the kernel.
        let assignments = try #require(device.makeBuffer(length: assignmentBytes, options: [.storageModeShared]))
        shift.contents().bindMemory(to: UInt32.self, capacity: 1).pointee = 0

        let cmd = try #require(pipeline.queue.makeCommandBuffer())
        try pipeline.encodeKMeans(
            cmd: cmd,
            tile: tile,
            centroids: centroids,
            bins: bins,
            shift: shift,
            assignments: assignments,
            iterations: iterations,
            K: K
        )
        cmd.commit()
        cmd.waitUntilCompleted()

        let cPtr = centroids.contents().bindMemory(to: SIMD4<Float>.self, capacity: K)
        let resultCentroids = (0..<K).map { i in
            let c = cPtr[i]
            return SIMD3<Float>(c.x, c.y, c.z)
        }
        let finalShift = Float(shift.contents().bindMemory(to: UInt32.self, capacity: 1).pointee) / 65536.0
        return GPURun(centroids: resultCentroids, finalShift: finalShift)
    }

    /// GPU centroids agree (set-wise, within tolerance) with CPU centroids on a
    /// deterministic synthetic OKLab tile. Both implementations seed from a
    /// uniform-stride sample of the same pixels and run the same number of
    /// Lloyd iterations, so they should converge to the same local optimum
    /// (modulo float-vs-fixed accumulation drift).
    @MainActor
    @Test func gpuAgreesWithCpuOnSyntheticGradient() throws {
        let side = 64
        let K = 256
        // Synthetic gradient — every position gets a unique (L, a, b) triple.
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

        let gpu = try runGPU(pixels: pixels, side: side, K: K, iterations: 15)

        // CPU reference: same uniform-stride seeds as the GPU kernel uses.
        let stride = max(1, pixels.count / K)
        let seeds: [SIMD3<Float>] = (0..<K).map { pixels[($0 * stride) % pixels.count] }
        let cpu = KMeansLab.run(
            samples: pixels, seeds: seeds,
            metric: EuclideanOKLabMetric(),
            maxIterations: 15, shiftTolerance: 0   // run all 15 to match GPU's fixed loop
        )

        // Compare *as sets* — both implementations are agnostic to centroid
        // order, and small numeric drift can shuffle ties. We assert that for
        // every CPU centroid, some GPU centroid lies within 5e-3 OKLab distance.
        let cpuCentroids = cpu.centroids
        for c in cpuCentroids {
            var bestD: Float = .infinity
            for g in gpu.centroids {
                let d = c - g
                let d2 = d.x * d.x + d.y * d.y + d.z * d.z
                if d2 < bestD { bestD = d2 }
            }
            #expect(bestD < 5e-3,
                    "CPU centroid \(c) has no GPU match within √5e-3 OKLab (best \(sqrt(bestD)))")
        }
    }

    /// 15 iterations is enough that the per-iteration shift has shrunk below
    /// a clearly-converged threshold on a well-conditioned input. We don't
    /// pin a hard number (the GPU's atomic-fixed-point accumulation is noisier
    /// than CPU floats), but we do require it's small relative to the initial
    /// spread.
    @MainActor
    @Test func shiftShrinksMeaningfullyAfter15Iterations() throws {
        let side = 64
        let K = 256
        var pixels: [SIMD3<Float>] = []
        pixels.reserveCapacity(side * side)
        for i in 0..<(side * side) {
            let t = Float(i) / Float(side * side - 1)
            pixels.append(SIMD3<Float>(t, 0.2 * sin(t * 6.28), 0.2 * cos(t * 6.28)))
        }
        let gpu = try runGPU(pixels: pixels, side: side, K: K, iterations: 15)
        // After 15 iterations on this well-conditioned input, the per-iter
        // shift should be modest — strictly less than the initial OKLab volume
        // of the data (~1.0 in each axis).
        #expect(gpu.finalShift < 0.5)
    }
}
