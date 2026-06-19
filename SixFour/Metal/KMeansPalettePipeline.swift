import Foundation
import Metal
import simd
import os

/// All-GPU Lloyd k-means palette extraction. The `iterativeKMeans` sibling of
/// the per-algorithm palette pipelines. Moved verbatim out of `MetalPipeline`
/// (which is now capture-only) so k-means logs and schedules under its own
/// `palette-kmeans` category + labeled command queue, alongside the Wu and
/// Octree pipelines.
///
/// Flow (one command buffer for the whole 64-tile burst): stage each tile into
/// an RGBA16F texture → seed (uniform stride) → 15 × (reset, assign+accumulate,
/// finalize) → finalize-stats covariance pass → read back centroids +
/// covariances + assignments → assemble `[ClusterStatistics]`.
final class KMeansPalettePipeline: PalettePipeline, @unchecked Sendable {
    static let logger = Logger(subsystem: "com.sixfour.SixFour", category: "palette-kmeans")

    let gpu: GPUContext
    let tileSide: Int
    let kMeansK: Int
    /// Fixed iteration count for the Lloyd loop. 15 iters converges 4096 OKLab
    /// samples × 256 clusters reliably (parity test enforces ≤5e-3 OKLab
    /// agreement with the CPU reference at this depth).
    var kMeansIterations: Int = 15

    /// How the Lloyd loop's initial centroids are chosen.
    ///   * `.uniformStride` — the GPU `kmeansSeedKernel` (today's default).
    ///   * `.wuInit` — seed from Wu's variance boxes (CPU), the literature's
    ///     near-optimal "Wu+KM" (Celebi 2011): lower MSE and far fewer dead
    ///     clusters than a uniform stride. Costs one CPU Wu pass per tile;
    ///     opt-in until on-device benchmarking justifies making it the default.
    /// Initial-centroid strategy.
    ///   * `.uniformStride` — GPU stride kernel (fastest, MSE-biased).
    ///   * `.wuInit` — Wu variance boxes (Wu+KM, MSE quality leader).
    ///   * `.farthestPoint` — maximin / FPS: centroids that maximize the min
    ///     pairwise distance → spreads across the gamut, captures extreme
    ///     colours. The *diversity* objective (use with `kMeansIterations = 0`
    ///     to keep the raw spread; Lloyd would pull centroids back to density).
    enum Seed: Sendable { case uniformStride, wuInit, farthestPoint }
    /// Default is Wu+KM (the literature's quality leader) now that it is the
    /// app's sole extraction path. `.uniformStride` is retained for the
    /// MSE-comparison test and as a fallback.
    var seed: Seed = .wuInit

    /// Wall-clock (ms) the last `extractBatch` spent on CPU Wu seeding (0 when
    /// `seed == .uniformStride`). Read by `GIFRenderer` to stamp the GIF's
    /// metadata comment so the cost is in the file, not just the logs.
    private(set) var lastWuSeedMillis: Int = 0

    // Exposed for tests that drive the kernels directly.
    var device: any MTLDevice { gpu.device }
    var queue: any MTLCommandQueue { gpu.queue }

    var family: ClusterStatistics.Family { .iterativeKMeans }

    private let kmeansSeedPSO: any MTLComputePipelineState
    private let kmeansResetPSO: any MTLComputePipelineState
    private let kmeansAssignAccumulatePSO: any MTLComputePipelineState
    private let kmeansFinalizePSO: any MTLComputePipelineState
    private let kmeansFinalizeStatsPSO: any MTLComputePipelineState

    enum KMeansPipelineError: Error { case commandFailed, textureCreationFailed }

    init(tileSide: Int = 64, kMeansK: Int = SixFourShape.K) throws {
        self.gpu = try GPUContext(queueLabel: "palette-kmeans")
        self.tileSide = tileSide
        self.kMeansK = kMeansK
        self.kmeansSeedPSO = try gpu.pso("kmeansSeedKernel")
        self.kmeansResetPSO = try gpu.pso("kmeansResetKernel")
        self.kmeansAssignAccumulatePSO = try gpu.pso("kmeansAssignAccumulateKernel")
        self.kmeansFinalizePSO = try gpu.pso("kmeansFinalizeKernel")
        self.kmeansFinalizeStatsPSO = try gpu.pso("kmeansFinalizeStatsKernel")
        Self.logger.debug("KMeansPalettePipeline init: tileSide=\(tileSide) K=\(kMeansK) device=\(self.gpu.device.name)")
    }

    /// Byte stride of one `KMeansBin`: 10 × 4-byte atomics (4 linear sums +
    /// count, 6 outer-product sums for covariance).
    static let kMeansBinStride: Int = 40
    /// Byte stride of one covariance entry (upper triangle of 3×3 symmetric Σ).
    static let kMeansCovarianceStride: Int = 6 * MemoryLayout<Float>.stride

    /// Run GPU Lloyd k-means on every tile in the burst, in a single command
    /// buffer. Logs total wall-clock + mean per-frame shift + mean MSE.
    func extractBatch(tiles: [OKLabTile], K: Int) throws -> [ClusterStatistics] {
        precondition(!tiles.isEmpty, "KMeansPalettePipeline: tiles must be non-empty")
        precondition(K == kMeansK,
                     "KMeansPalettePipeline: K=\(K) doesn't match kMeansK=\(kMeansK). " +
                     "Reconstruct the pipeline with the new K to change palette size.")
        let frameCount = tiles.count
        Self.logger.debug(
            "extractBatch starting: frames=\(frameCount) K=\(self.kMeansK) iters=\(self.kMeansIterations)"
        )
        let started = ContinuousClock().now

        let centroidBytes   = kMeansK * MemoryLayout<SIMD4<Float>>.stride
        let binBytes        = kMeansK * Self.kMeansBinStride
        let shiftBytes      = MemoryLayout<UInt32>.stride
        let covarianceBytes = kMeansK * Self.kMeansCovarianceStride
        let pixelCount      = tileSide * tileSide
        let assignmentBytes = pixelCount * MemoryLayout<UInt16>.stride

        var centroidBufs:    [any MTLBuffer] = []
        var binBufs:         [any MTLBuffer] = []
        var shiftBufs:       [any MTLBuffer] = []
        var covarianceBufs:  [any MTLBuffer] = []
        var assignmentBufs:  [any MTLBuffer] = []
        var tileTextures:    [any MTLTexture] = []
        centroidBufs.reserveCapacity(frameCount)
        binBufs.reserveCapacity(frameCount)
        shiftBufs.reserveCapacity(frameCount)
        covarianceBufs.reserveCapacity(frameCount)
        assignmentBufs.reserveCapacity(frameCount)
        tileTextures.reserveCapacity(frameCount)

        let device = gpu.device
        for tile in tiles {
            guard
                let cBuf  = device.makeBuffer(length: centroidBytes,   options: [.storageModeShared]),
                let bBuf  = device.makeBuffer(length: binBytes,        options: [.storageModePrivate]),
                let sBuf  = device.makeBuffer(length: shiftBytes,      options: [.storageModeShared]),
                let vBuf  = device.makeBuffer(length: covarianceBytes, options: [.storageModeShared]),
                let aBuf  = device.makeBuffer(length: assignmentBytes, options: [.storageModeShared])
            else { throw KMeansPipelineError.commandFailed }
            sBuf.contents().bindMemory(to: UInt32.self, capacity: 1).pointee = 0
            centroidBufs.append(cBuf)
            binBufs.append(bBuf)
            shiftBufs.append(sBuf)
            covarianceBufs.append(vBuf)
            assignmentBufs.append(aBuf)

            let tex = try makeTileTexture(storageMode: .shared)
            var half = [SIMD4<Float16>](repeating: .zero, count: tile.side * tile.side)
            for i in 0..<tile.pixels.count {
                let p = tile.pixels[i]
                half[i] = SIMD4<Float16>(Float16(p.x), Float16(p.y), Float16(p.z), 1)
            }
            half.withUnsafeBytes { raw in
                tex.replace(
                    region: MTLRegionMake2D(0, 0, tile.side, tile.side),
                    mipmapLevel: 0,
                    withBytes: raw.baseAddress!,
                    bytesPerRow: tile.side * MemoryLayout<SIMD4<Float16>>.stride
                )
            }
            tileTextures.append(tex)
        }

        // CPU seeding (Wu boxes or farthest-point): computed on CPU and written
        // into the shared centroid buffers BEFORE the command buffer runs; the
        // GPU seed dispatch is then skipped (`seedOnGPU: false`). Uniform-stride
        // seeds on the GPU instead.
        let seedOnGPU = (seed == .uniformStride)
        lastWuSeedMillis = 0
        if seed != .uniformStride {
            let seedStart = ContinuousClock().now
            for i in 0..<frameCount {
                let seeds: [SIMD4<Float>] = (seed == .wuInit)
                    ? Self.wuSeedCentroids(pixels: tiles[i].pixels, K: kMeansK)
                    : Self.farthestPointSeedCentroids(pixels: tiles[i].pixels, K: kMeansK)
                let dst = centroidBufs[i].contents().bindMemory(to: SIMD4<Float>.self, capacity: kMeansK)
                for k in 0..<kMeansK { dst[k] = seeds[k] }
            }
            let ms = Self.millis(ContinuousClock().now - seedStart)
            if seed == .wuInit { lastWuSeedMillis = ms }
            let name = (seed == .wuInit) ? "Wu+KM" : "farthest-point"
            // .notice so it persists + shows in Console for on-device benchmarking.
            Self.logger.debug("[bench] \(name) seed (CPU, ×\(frameCount) frames): \(ms)ms total (\(ms / max(1, frameCount))ms/frame)")
        }

        guard let cmd = gpu.queue.makeCommandBuffer() else {
            throw KMeansPipelineError.commandFailed
        }
        for i in 0..<frameCount {
            try encodeKMeans(
                cmd: cmd,
                tile: tileTextures[i],
                centroids: centroidBufs[i],
                bins: binBufs[i],
                shift: shiftBufs[i],
                assignments: assignmentBufs[i],
                iterations: kMeansIterations,
                K: kMeansK,
                seedOnGPU: seedOnGPU
            )
            try encodeKMeansFinalizeStats(
                cmd: cmd,
                bins: binBufs[i],
                covariances: covarianceBufs[i],
                K: kMeansK
            )
        }
        cmd.commit()
        cmd.waitUntilCompleted()

        if let err = cmd.error {
            Self.logger.error("extractBatch GPU command buffer failed: \(err.localizedDescription)")
            throw KMeansPipelineError.commandFailed
        }

        var out: [ClusterStatistics] = []
        out.reserveCapacity(frameCount)
        var shiftAccum: Float = 0
        var mseAccum: Float = 0
        let tileExtractMs = Self.millis(ContinuousClock().now - started) / max(1, frameCount)
        for i in 0..<frameCount {
            let cPtr = centroidBufs[i].contents().bindMemory(to: SIMD4<Float>.self, capacity: kMeansK)
            let vPtr = covarianceBufs[i].contents().bindMemory(to: Float.self, capacity: kMeansK * 6)
            let aPtr = assignmentBufs[i].contents().bindMemory(to: UInt16.self, capacity: pixelCount)
            let shiftRaw = shiftBufs[i].contents().bindMemory(to: UInt32.self, capacity: 1).pointee
            let finalShift = Float(shiftRaw) / 65536.0
            shiftAccum += finalShift

            var counts = [UInt32](repeating: 0, count: kMeansK)
            let assignments = Array(UnsafeBufferPointer(start: aPtr, count: pixelCount))
            for a in assignments {
                counts[Int(a)] &+= 1
            }

            var sse: Float = 0
            let pixels = tiles[i].pixels
            for p in 0..<pixelCount {
                let c4 = cPtr[Int(assignments[p])]
                let d = pixels[p] - SIMD3<Float>(c4.x, c4.y, c4.z)
                sse += simd_dot(d, d)
            }
            let mse = sse / Float(pixelCount)
            mseAccum += mse

            var clusters = [ClusterStatistics.Cluster](repeating: ClusterStatistics.Cluster(
                mean: .zero, covariance: ClusterStatistics.Cluster.emptyCovariance, count: 0
            ), count: kMeansK)
            for k in 0..<kMeansK {
                let c4 = cPtr[k]
                let base = k * 6
                let LL = vPtr[base + 0]
                let La = vPtr[base + 1]
                let Lb = vPtr[base + 2]
                let aa = vPtr[base + 3]
                let ab = vPtr[base + 4]
                let bb = vPtr[base + 5]
                let sigma = simd_float3x3(
                    columns: (
                        SIMD3<Float>(LL, La, Lb),
                        SIMD3<Float>(La, aa, ab),
                        SIMD3<Float>(Lb, ab, bb)
                    )
                )
                clusters[k] = ClusterStatistics.Cluster(
                    mean: SIMD3<Float>(c4.x, c4.y, c4.z),
                    covariance: sigma,
                    count: counts[k]
                )
            }

            let provenance = ClusterStatistics.Provenance(
                family: .iterativeKMeans,
                parameters: .kMeans(seed: .uniformStride, iterations: kMeansIterations),
                extractMillis: tileExtractMs,
                mse: mse
            )
            out.append(ClusterStatistics(
                clusters: clusters,
                assignments: assignments,
                provenance: provenance
            ))
        }
        let elapsed = ContinuousClock().now - started
        let ms = Self.millis(elapsed)
        let meanShift = shiftAccum / Float(frameCount)
        let meanMSE = mseAccum / Float(frameCount)
        Self.logger.debug(
            "extractBatch done in \(ms)ms (mean final shift=\(meanShift), mean MSE=\(meanMSE), \(ms / max(1, frameCount))ms/frame)"
        )
        return out
    }

    // MARK: - Kernel encoding

    /// Encode seed + `iterations × (reset, assign+accumulate, finalize)`.
    /// When `seedOnGPU` is false, the centroid buffer is assumed to already
    /// hold the initial centroids (e.g. CPU Wu+KM seeding) and the GPU seed
    /// dispatch is skipped.
    func encodeKMeans(
        cmd: any MTLCommandBuffer,
        tile: any MTLTexture,
        centroids: any MTLBuffer,
        bins: any MTLBuffer,
        shift: any MTLBuffer,
        assignments: any MTLBuffer,
        iterations: Int,
        K: Int,
        seedOnGPU: Bool = true
    ) throws {
        var kVar = UInt32(K)
        if seedOnGPU {
            try dispatch1D(cmd: cmd, pso: kmeansSeedPSO, threadCount: K) { enc in
                enc.setTexture(tile, index: 0)
                enc.setBuffer(centroids, offset: 0, index: 0)
                enc.setBytes(&kVar, length: MemoryLayout<UInt32>.size, index: 1)
            }
        }

        let pixels = tileSide * tileSide
        for _ in 0..<iterations {
            try dispatch1D(cmd: cmd, pso: kmeansResetPSO, threadCount: max(K, 1)) { enc in
                enc.setBuffer(bins, offset: 0, index: 0)
                enc.setBuffer(shift, offset: 0, index: 1)
                enc.setBytes(&kVar, length: MemoryLayout<UInt32>.size, index: 2)
            }
            try dispatch1D(cmd: cmd, pso: kmeansAssignAccumulatePSO, threadCount: pixels) { enc in
                enc.setTexture(tile, index: 0)
                enc.setBuffer(centroids, offset: 0, index: 0)
                enc.setBuffer(bins, offset: 0, index: 1)
                enc.setBytes(&kVar, length: MemoryLayout<UInt32>.size, index: 2)
                enc.setBuffer(assignments, offset: 0, index: 3)
            }
            try dispatch1D(cmd: cmd, pso: kmeansFinalizePSO, threadCount: K) { enc in
                enc.setBuffer(bins, offset: 0, index: 0)
                enc.setBuffer(centroids, offset: 0, index: 1)
                enc.setBuffer(shift, offset: 0, index: 2)
                enc.setBytes(&kVar, length: MemoryLayout<UInt32>.size, index: 3)
            }
        }
    }

    /// Post-Lloyd covariance pass: K threads compute Σ = E[xxᵀ] − μμᵀ from the
    /// outer-product atomics still held in `bins`. Encode AFTER the Lloyd loop
    /// on the same command buffer (do NOT reset between).
    func encodeKMeansFinalizeStats(
        cmd: any MTLCommandBuffer,
        bins: any MTLBuffer,
        covariances: any MTLBuffer,
        K: Int
    ) throws {
        var kVar = UInt32(K)
        try dispatch1D(cmd: cmd, pso: kmeansFinalizeStatsPSO, threadCount: K) { enc in
            enc.setBuffer(bins, offset: 0, index: 0)
            enc.setBuffer(covariances, offset: 0, index: 1)
            enc.setBytes(&kVar, length: MemoryLayout<UInt32>.size, index: 2)
        }
    }

    private func dispatch1D(
        cmd: any MTLCommandBuffer,
        pso: any MTLComputePipelineState,
        threadCount: Int,
        configure: (any MTLComputeCommandEncoder) -> Void
    ) throws {
        guard let enc = cmd.makeComputeCommandEncoder() else {
            throw KMeansPipelineError.commandFailed
        }
        defer { enc.endEncoding() }
        enc.setComputePipelineState(pso)
        configure(enc)
        let tg = MTLSize(width: min(pso.maxTotalThreadsPerThreadgroup, max(threadCount, 1)),
                        height: 1, depth: 1)
        let grid = MTLSize(width: threadCount, height: 1, depth: 1)
        enc.dispatchThreads(grid, threadsPerThreadgroup: tg)
    }

    private func makeTileTexture(storageMode: MTLStorageMode) throws -> any MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: tileSide, height: tileSide, mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = storageMode
        guard let tex = gpu.device.makeTexture(descriptor: desc) else {
            throw KMeansPipelineError.textureCreationFailed
        }
        return tex
    }

    /// Wu+KM seed: K initial centroids from Wu's variance boxes (CPU). Empty
    /// Wu slots — low-diversity tiles can't always fill K boxes — are seeded
    /// from uniformly-strided pixels so no seed sits dead at the origin (which
    /// would just reintroduce the dead-cluster problem Wu+KM is meant to cure).
    static func wuSeedCentroids(pixels: [SIMD3<Float>], K: Int) -> [SIMD4<Float>] {
        let h = WuQuantizer.buildHistogramCPU(pixels: pixels)
        let r = WuQuantizer.quantize(h, pixels: pixels, K: K)
        var out = [SIMD4<Float>](repeating: SIMD4<Float>(0, 0, 0, 1), count: K)
        let n = max(pixels.count, 1)
        let stride = max(1, n / max(K, 1))
        for k in 0..<K {
            let c = r.clusters[k]
            if c.count > 0 {
                out[k] = SIMD4<Float>(c.mean.x, c.mean.y, c.mean.z, 1)
            } else {
                let p = pixels[(k * stride) % n]
                out[k] = SIMD4<Float>(p.x, p.y, p.z, 1)
            }
        }
        return out
    }

    /// Farthest-point (maximin) seeds: the diversity objective. Greedily pick K
    /// pixels each maximizing the minimum distance to those already chosen, so
    /// the palette SPREADS across the scene's gamut and captures rare/extreme
    /// colours (the opposite of MSE's density bias). First seed = the pixel
    /// farthest from the data mean (a deterministic extreme). O(K·N) with
    /// incremental min-distance tracking (same shape as the dither/seed loops).
    static func farthestPointSeedCentroids(pixels: [SIMD3<Float>], K: Int) -> [SIMD4<Float>] {
        let n = pixels.count
        precondition(n > 0, "farthestPoint: need ≥1 pixel")
        // First seed: farthest pixel from the mean (deterministic extreme).
        var mean = SIMD3<Float>.zero
        for p in pixels { mean += p }
        mean /= Float(n)
        var current = 0
        var bestD: Float = -1
        for i in 0..<n {
            let d = pixels[i] - mean
            let dd = simd_dot(d, d)
            if dd > bestD { bestD = dd; current = i }
        }

        var out = [SIMD4<Float>](repeating: SIMD4<Float>(0, 0, 0, 1), count: K)
        var minDist = [Float](repeating: .greatestFiniteMagnitude, count: n)
        for k in 0..<K {
            let c = pixels[current]
            out[k] = SIMD4<Float>(c.x, c.y, c.z, 1)
            var nextIdx = 0
            var nextD: Float = -1
            for i in 0..<n {
                let d = pixels[i] - c
                let dd = simd_dot(d, d)
                if dd < minDist[i] { minDist[i] = dd }
                if minDist[i] > nextD { nextD = minDist[i]; nextIdx = i }
            }
            current = nextIdx
        }
        return out
    }

    private static func millis(_ d: Duration) -> Int {
        let (s, attos) = d.components
        return Int(s) * 1_000 + Int(attos / 1_000_000_000_000_000)
    }
}
