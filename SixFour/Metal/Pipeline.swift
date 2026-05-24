import Foundation
import Metal
import CoreVideo
import simd
import os

/// Per-frame OKLab tile.
///
/// `submitAsync` produces tiles with `palette` empty and `finalShift = 0` —
/// the GPU k-means used to fold into the per-frame command buffer, but
/// that put ~46 dispatches of CPU encoding into the 50 ms AVFoundation
/// delegate slot and caused kernel-side frame drops on device. The fix
/// (per the no-fallback rule + the device drop logs) is to capture only
/// OKLab pixels per frame, then run k-means once on all 64 tiles
/// post-burst via `MetalPipeline.runStageAKMeansBatch`.
///
/// After `runStageAKMeansBatch`, every tile's `palette` is its Stage-A
/// 256-entry OKLab palette and `finalShift` is the L² shift on the
/// final Lloyd iteration (diagnostic; ≈ 0 at convergence). Per-pixel
/// indices are NOT included — those are produced downstream by CPU-side
/// error-diffusion dither against the palette.
struct OKLabTile: Sendable, Codable {
    let side: Int
    let pixels: [SIMD3<Float>]
    let captureNanos: UInt64
    let palette: [SIMD3<Float>]      // K centroids in OKLab (length K); empty until batched k-means runs
    let finalShift: Float            // diagnostic only — Σ‖μ' − μ‖² on last iter
}

/// Phase 2 Metal pipeline. Per camera frame:
///   1. cropDownsampleLinearizeKernel  BGRA(W×H sRGB) → RGBA16F(tile²×tile², linear-light)
///   2. linearToOklabKernel            RGBA16F linear → RGBA16F OKLab
///   3. unsharpMaskLKernel             RGBA16F OKLab → RGBA16F OKLab (L sharpened)
///
/// Submission is non-blocking; completion handler reads back the final OKLab texture.
final class MetalPipeline: @unchecked Sendable {
    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let textureCache: MetalTextureCache
    let tileSide: Int
    let kMeansK: Int
    /// Fixed iteration count for the in-command-buffer Lloyd loop.
    /// 15 iters converges 4096 OKLab samples × 256 clusters reliably
    /// (the parity test enforces ≤1e-3 OKLab agreement with the CPU
    /// reference at this depth).
    var kMeansIterations: Int = 15
    var unsharpAmount: Float = 0.6
    /// Color-space tag passed as `buffer(2)` to `cropDownsampleLinearizeKernel`
    /// so it dispatches to the right OETF inverse + RGB-primaries-to-sRGB
    /// path. Raw values are defined by `CaptureSession.ActiveColorSpaceTag`
    /// and MUST stay in sync with the switch in `Shaders.metal`.
    /// Default `0` (Rec.709) is safe because Rec.709 is the floor of the
    /// capture-side priority cascade; `CaptureSession.configure()` sets
    /// the right value before the first frame is submitted.
    var colorSpaceTag: UInt8 = 0

    static let logger = Logger(subsystem: "com.sixfour.SixFour", category: "metal")

    private let cropDownsampleLinearizePSO: any MTLComputePipelineState
    private let linearToOklabPSO: any MTLComputePipelineState
    private let unsharpPSO: any MTLComputePipelineState
    let kmeansSeedPSO: any MTLComputePipelineState
    let kmeansResetPSO: any MTLComputePipelineState
    let kmeansAssignAccumulatePSO: any MTLComputePipelineState
    let kmeansFinalizePSO: any MTLComputePipelineState
    /// Post-Lloyd: K threads compute per-cluster covariance from the
    /// outer-product atomics accumulated in KMeansBin and write 6
    /// floats (upper triangle of Σ) per cluster to the covariances
    /// buffer. Added when ClusterStatistics landed.
    let kmeansFinalizeStatsPSO: any MTLComputePipelineState

    init(tileSide: Int = 64, kMeansK: Int = SixFourShape.K) throws {
        guard let dev = MTLCreateSystemDefaultDevice() else { throw MetalPipelineError.noDevice }
        guard let q = dev.makeCommandQueue() else { throw MetalPipelineError.noQueue }
        guard let lib = dev.makeDefaultLibrary() else { throw MetalPipelineError.noLibrary }
        func pso(_ name: String) throws -> any MTLComputePipelineState {
            guard let fn = lib.makeFunction(name: name) else {
                throw MetalPipelineError.missingKernel(name)
            }
            return try dev.makeComputePipelineState(function: fn)
        }
        self.device = dev
        self.queue = q
        self.textureCache = MetalTextureCache(device: dev)
        self.tileSide = tileSide
        self.kMeansK = kMeansK
        // Single YCbCr10 entry-point — BGRA path deleted per no-fallback rule.
        self.cropDownsampleLinearizePSO = try pso("cropDownsampleLinearizeKernel")
        self.linearToOklabPSO = try pso("linearToOklabKernel")
        self.unsharpPSO = try pso("unsharpMaskLKernel")
        self.kmeansSeedPSO = try pso("kmeansSeedKernel")
        self.kmeansResetPSO = try pso("kmeansResetKernel")
        self.kmeansAssignAccumulatePSO = try pso("kmeansAssignAccumulateKernel")
        self.kmeansFinalizePSO = try pso("kmeansFinalizeKernel")
        self.kmeansFinalizeStatsPSO = try pso("kmeansFinalizeStatsKernel")
        Self.logger.info("MetalPipeline init: tileSide=\(tileSide) kMeansK=\(kMeansK) device=\(dev.name)")
    }

    enum MetalPipelineError: Error {
        case noDevice, noQueue, noLibrary
        case missingKernel(String)
        case textureCreationFailed
        case commandFailed
    }

    /// Largest centered square crop that's an exact integer multiple of `tileSide`.
    func optimalCropSide(sourceWidth: Int, sourceHeight: Int) -> Int {
        let minSide = min(sourceWidth, sourceHeight)
        return max(tileSide, (minSide / tileSide) * tileSide)
    }

    /// Submit one camera frame. Returns immediately; completion fires when
    /// the GPU finishes. Builds a 3-pass command buffer (crop+linearize →
    /// OKLab → unsharp). K-means is **not** part of this command buffer —
    /// it runs once on all 64 tiles via `runStageAKMeansBatch` after the
    /// burst completes. Folding k-means into the per-frame submit put
    /// ~46 dispatches of CPU encoding into the 50 ms delegate slot, which
    /// caused kernel-side frame drops on device (`Camera DROPPED a frame`).
    func submitAsync(
        pixelBuffer: CVPixelBuffer,
        captureNanos: UInt64,
        completion: @escaping @Sendable (OKLabTile) -> Void
    ) throws {
        let geom = pixelBufferGeometry(pixelBuffer)
        let intermediates = try allocateIntermediates()

        guard let cmd = queue.makeCommandBuffer() else {
            throw MetalPipelineError.commandFailed
        }

        try encodeCropDownsampleLinearize(cmd: cmd, pixelBuffer: pixelBuffer,
                                          geom: geom, destination: intermediates.linear)
        try encodeLinearToOKLab(cmd: cmd, source: intermediates.linear,
                                destination: intermediates.lab)
        try encodeUnsharpL(cmd: cmd, source: intermediates.lab,
                           destination: intermediates.output)

        let tileSide = self.tileSide
        let outBox = TextureBox(intermediates.output)
        cmd.addCompletedHandler { _ in
            let tile = MetalPipeline.readbackOKLabTile(
                texture: outBox.texture,
                side: tileSide,
                captureNanos: captureNanos
            )
            completion(tile)
        }

        cmd.commit()
    }

    /// Run GPU Lloyd k-means on every tile in the burst, in a single
    /// command buffer. Returns new tiles with `palette` populated and
    /// `finalShift` set to the diagnostic. Logs total wall-clock + mean
    /// per-frame shift so on-device runs leave a record of convergence.
    ///
    /// This is the half of Stage A that used to live inside `submitAsync`;
    /// hoisting it out keeps the delegate queue light during capture.
    func runStageAKMeansBatch(tiles: [OKLabTile]) throws -> [ClusterStatistics] {
        precondition(!tiles.isEmpty, "runStageAKMeansBatch: tiles must be non-empty")
        let frameCount = tiles.count
        Self.logger.info(
            "runStageAKMeansBatch starting: frames=\(frameCount) K=\(self.kMeansK) iters=\(self.kMeansIterations)"
        )
        let started = ContinuousClock().now

        // Per-tile scratch GPU buffers. centroids/shift/covariances/
        // assignments are shared so the host can read them after the
        // command buffer completes; bins is private since we never
        // look at it from the host (only the GPU kernels read/write
        // it, and the kmeansFinalizeStatsKernel forwards the
        // statistics into the host-visible covariances buffer).
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

        for tile in tiles {
            guard
                let cBuf  = device.makeBuffer(length: centroidBytes,   options: [.storageModeShared]),
                let bBuf  = device.makeBuffer(length: binBytes,        options: [.storageModePrivate]),
                let sBuf  = device.makeBuffer(length: shiftBytes,      options: [.storageModeShared]),
                let vBuf  = device.makeBuffer(length: covarianceBytes, options: [.storageModeShared]),
                let aBuf  = device.makeBuffer(length: assignmentBytes, options: [.storageModeShared])
            else { throw MetalPipelineError.commandFailed }
            sBuf.contents().bindMemory(to: UInt32.self, capacity: 1).pointee = 0
            centroidBufs.append(cBuf)
            binBufs.append(bBuf)
            shiftBufs.append(sBuf)
            covarianceBufs.append(vBuf)
            assignmentBufs.append(aBuf)

            // Stage the tile pixels back into a Metal texture so the
            // k-means kernels can sample it. (The original
            // `intermediates.output` textures aren't retained past their
            // completion handler.)
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

        guard let cmd = queue.makeCommandBuffer() else {
            throw MetalPipelineError.commandFailed
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
                K: kMeansK
            )
            // After the last Lloyd iteration the bins still hold the
            // accumulated sums; compute covariances before the next
            // iteration would reset them. (There IS no next iteration
            // — we run this kernel once per tile, post-Lloyd.)
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
            Self.logger.error("runStageAKMeansBatch GPU command buffer failed: \(err.localizedDescription)")
            throw MetalPipelineError.commandFailed
        }

        // Read back centroids + covariances + assignments per tile;
        // assemble ClusterStatistics. The provenance.mse is computed
        // CPU-side from tile.pixels + assignments + centroids (one
        // pass over 4096 pixels per tile, ~50 µs).
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

            // Per-cluster (mean, Σ, count). Count comes from a CPU
            // pass over assignments (the bins buffer is .private and
            // not host-readable; this is cheap — 4096 increments).
            var counts = [UInt32](repeating: 0, count: kMeansK)
            let assignments = Array(UnsafeBufferPointer(start: aPtr, count: pixelCount))
            for a in assignments {
                counts[Int(a)] &+= 1
            }

            // MSE = (1/N) Σ ‖pixel − centroid[assignment]‖² in OKLab units².
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
                // simd_float3x3 columns: [col0, col1, col2]. Symmetric Σ:
                //   row 0: (LL, La, Lb)
                //   row 1: (La, aa, ab)
                //   row 2: (Lb, ab, bb)
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
        Self.logger.info(
            "runStageAKMeansBatch done in \(ms)ms (mean final shift=\(meanShift), mean MSE=\(meanMSE), \(ms / max(1, frameCount))ms/frame)"
        )
        return out
    }

    private static func millis(_ d: Duration) -> Int {
        let (s, attos) = d.components
        return Int(s) * 1_000 + Int(attos / 1_000_000_000_000_000)
    }

    // MARK: - Stage helpers (one per encode pass)

    private struct PixelBufferGeometry {
        let sourceWidth: Int
        let sourceHeight: Int
        let cropSide: Int
        let scale: Int
        let offsetX: Int
        let offsetY: Int
    }

    private func pixelBufferGeometry(_ pixelBuffer: CVPixelBuffer) -> PixelBufferGeometry {
        // CaptureSession.configure() guarantees we only see YCbCr10. If a
        // future code path ever delivers a different format here we want
        // the read width to still be defined — use the luma plane (which
        // matches frame width for any biplanar YCbCr format).
        let sw = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let sh = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let cropSide = optimalCropSide(sourceWidth: sw, sourceHeight: sh)
        return PixelBufferGeometry(
            sourceWidth: sw, sourceHeight: sh,
            cropSide: cropSide, scale: cropSide / tileSide,
            offsetX: (sw - cropSide) / 2, offsetY: (sh - cropSide) / 2
        )
    }

    /// Per-submit GPU resources. K-means buffers are NOT allocated here
    /// any more — they live inside `runStageAKMeansBatch` so the
    /// per-frame command buffer stays light.
    private struct Intermediates {
        let linear: any MTLTexture
        let lab: any MTLTexture
        let output: any MTLTexture
    }

    /// Byte stride of one `KMeansBin`. Currently 10 × 4-byte atomics:
    /// 4 linear sums (sum_L, sum_a, sum_b, count) + 6 outer-product
    /// sums for covariance (sum_LL, sum_La, sum_Lb, sum_aa, sum_ab,
    /// sum_bb). atomic_int / atomic_uint are 4 bytes each with no
    /// alignment padding required at 4-byte boundaries.
    static let kMeansBinStride: Int = 40
    /// Byte stride of one covariance entry (upper triangle of 3×3
    /// symmetric Σ: LL, La, Lb, aa, ab, bb).
    static let kMeansCovarianceStride: Int = 6 * MemoryLayout<Float>.stride

    private func allocateIntermediates() throws -> Intermediates {
        return Intermediates(
            linear: try makeTileTexture(storageMode: .private),
            lab: try makeTileTexture(storageMode: .private),
            output: try makeTileTexture(storageMode: .shared)
        )
    }

    private func makeTileTexture(storageMode: MTLStorageMode) throws -> any MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: tileSide, height: tileSide, mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = storageMode
        guard let tex = device.makeTexture(descriptor: desc) else {
            throw MetalPipelineError.textureCreationFailed
        }
        return tex
    }

    private func encodeCropDownsampleLinearize(
        cmd: any MTLCommandBuffer,
        pixelBuffer: CVPixelBuffer,
        geom: PixelBufferGeometry,
        destination: any MTLTexture
    ) throws {
        guard let enc = cmd.makeComputeCommandEncoder() else {
            throw MetalPipelineError.commandFailed
        }
        defer { enc.endEncoding() }

        var offset = SIMD2<Int32>(Int32(geom.offsetX), Int32(geom.offsetY))
        var scaleVal = Int32(geom.scale)
        var tag = colorSpaceTag
        guard let pair = textureCache.texturesYCbCr10(from: pixelBuffer) else {
            Self.logger.error("encodeCropDownsampleLinearize: YCbCr10 texture cache lookup failed (pixelBuffer format mismatch?)")
            throw MetalPipelineError.textureCreationFailed
        }
        enc.setComputePipelineState(cropDownsampleLinearizePSO)
        enc.setTexture(pair.luma, index: 0)
        enc.setTexture(pair.chroma, index: 1)
        enc.setTexture(destination, index: 2)
        enc.setBytes(&offset, length: MemoryLayout<SIMD2<Int32>>.size, index: 0)
        enc.setBytes(&scaleVal, length: MemoryLayout<Int32>.size, index: 1)
        enc.setBytes(&tag, length: MemoryLayout<UInt8>.size, index: 2)
        dispatch2D(enc, width: tileSide, height: tileSide, pso: cropDownsampleLinearizePSO)
    }

    private func encodeLinearToOKLab(
        cmd: any MTLCommandBuffer,
        source: any MTLTexture,
        destination: any MTLTexture
    ) throws {
        guard let enc = cmd.makeComputeCommandEncoder() else {
            throw MetalPipelineError.commandFailed
        }
        defer { enc.endEncoding() }
        enc.setComputePipelineState(linearToOklabPSO)
        enc.setTexture(source, index: 0)
        enc.setTexture(destination, index: 1)
        dispatch2D(enc, width: tileSide, height: tileSide, pso: linearToOklabPSO)
    }

    private func encodeUnsharpL(
        cmd: any MTLCommandBuffer,
        source: any MTLTexture,
        destination: any MTLTexture
    ) throws {
        guard let enc = cmd.makeComputeCommandEncoder() else {
            throw MetalPipelineError.commandFailed
        }
        defer { enc.endEncoding() }
        enc.setComputePipelineState(unsharpPSO)
        enc.setTexture(source, index: 0)
        enc.setTexture(destination, index: 1)
        var amount = unsharpAmount
        enc.setBytes(&amount, length: MemoryLayout<Float>.size, index: 0)
        dispatch2D(enc, width: tileSide, height: tileSide, pso: unsharpPSO)
    }

    // MARK: - GPU Lloyd k-means

    /// Encode the full in-command-buffer Lloyd k-means loop into `cmd`:
    /// seed once, then `iterations × (reset, assign+accumulate, finalize)`.
    /// Centroids and shift live in shared-storage buffers so the completion
    /// handler can read them back directly without an extra copy pass.
    ///
    /// `assignments` is a `pixels × ushort` device buffer that the
    /// assign+accumulate kernel writes per pixel each iteration; only
    /// the last iteration's write is observable (each pixel slot is
    /// overwritten). Used by KMeansExtractor to populate
    /// `ClusterStatistics.assignments`.
    func encodeKMeans(
        cmd: any MTLCommandBuffer,
        tile: any MTLTexture,
        centroids: any MTLBuffer,
        bins: any MTLBuffer,
        shift: any MTLBuffer,
        assignments: any MTLBuffer,
        iterations: Int,
        K: Int
    ) throws {
        var kVar = UInt32(K)
        // Seed: K threads write initial centroids from uniform-stride samples.
        try dispatch1D(cmd: cmd, pso: kmeansSeedPSO, threadCount: K) { enc in
            enc.setTexture(tile, index: 0)
            enc.setBuffer(centroids, offset: 0, index: 0)
            enc.setBytes(&kVar, length: MemoryLayout<UInt32>.size, index: 1)
        }

        let pixels = tileSide * tileSide
        for _ in 0..<iterations {
            // Reset bins + shift in one dispatch (max(K, 1) threads).
            try dispatch1D(cmd: cmd, pso: kmeansResetPSO, threadCount: max(K, 1)) { enc in
                enc.setBuffer(bins, offset: 0, index: 0)
                enc.setBuffer(shift, offset: 0, index: 1)
                enc.setBytes(&kVar, length: MemoryLayout<UInt32>.size, index: 2)
            }
            // Assign + accumulate: one thread per pixel.
            try dispatch1D(cmd: cmd, pso: kmeansAssignAccumulatePSO, threadCount: pixels) { enc in
                enc.setTexture(tile, index: 0)
                enc.setBuffer(centroids, offset: 0, index: 0)
                enc.setBuffer(bins, offset: 0, index: 1)
                enc.setBytes(&kVar, length: MemoryLayout<UInt32>.size, index: 2)
                enc.setBuffer(assignments, offset: 0, index: 3)
            }
            // Finalize: K threads divide sum/count, accumulate shift.
            try dispatch1D(cmd: cmd, pso: kmeansFinalizePSO, threadCount: K) { enc in
                enc.setBuffer(bins, offset: 0, index: 0)
                enc.setBuffer(centroids, offset: 0, index: 1)
                enc.setBuffer(shift, offset: 0, index: 2)
                enc.setBytes(&kVar, length: MemoryLayout<UInt32>.size, index: 3)
            }
        }
    }

    /// Encode the post-Lloyd covariance pass: K threads, one per
    /// cluster. Reads the outer-product atomics + linear sums from
    /// `bins`, computes Σ = E[xxᵀ] − μμᵀ, and writes 6 floats
    /// (upper triangle: LL, La, Lb, aa, ab, bb) per cluster to
    /// `covariances`. Must be encoded AFTER the Lloyd loop, on the
    /// same command buffer; the bins must still hold the last
    /// iteration's accumulations (do NOT reset between Lloyd's last
    /// finalize and this kernel).
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

    /// 1-D dispatch convenience: builds an encoder, lets the caller bind
    /// resources via `configure`, then dispatches `threadCount` threads at
    /// the PSO's preferred threadgroup size.
    private func dispatch1D(
        cmd: any MTLCommandBuffer,
        pso: any MTLComputePipelineState,
        threadCount: Int,
        configure: (any MTLComputeCommandEncoder) -> Void
    ) throws {
        guard let enc = cmd.makeComputeCommandEncoder() else {
            throw MetalPipelineError.commandFailed
        }
        defer { enc.endEncoding() }
        enc.setComputePipelineState(pso)
        configure(enc)
        let tg = MTLSize(width: min(pso.maxTotalThreadsPerThreadgroup, max(threadCount, 1)),
                        height: 1, depth: 1)
        let grid = MTLSize(width: threadCount, height: 1, depth: 1)
        enc.dispatchThreads(grid, threadsPerThreadgroup: tg)
    }

    // MARK: - Readback

    /// Read an RGBA16Float texture back to host memory and convert each
    /// pixel to a `SIMD3<Float>` OKLab triple. The returned tile carries
    /// an empty `palette`; `runStageAKMeansBatch` fills it after the burst.
    private static func readbackOKLabTile(
        texture: any MTLTexture,
        side: Int,
        captureNanos: UInt64
    ) -> OKLabTile {
        let count = side * side
        var halfPixels = [SIMD4<Float16>](
            repeating: SIMD4<Float16>(0, 0, 0, 0), count: count
        )
        let bytesPerRow = side * MemoryLayout<SIMD4<Float16>>.stride
        halfPixels.withUnsafeMutableBytes { rawPtr in
            guard let base = rawPtr.baseAddress else { return }
            let region = MTLRegionMake2D(0, 0, side, side)
            texture.getBytes(base, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        }
        let pixels: [SIMD3<Float>] = halfPixels.map { h in
            SIMD3<Float>(Float(h.x), Float(h.y), Float(h.z))
        }
        return OKLabTile(
            side: side,
            pixels: pixels,
            captureNanos: captureNanos,
            palette: [],
            finalShift: 0
        )
    }

    private func dispatch2D(
        _ enc: any MTLComputeCommandEncoder,
        width: Int, height: Int,
        pso: any MTLComputePipelineState
    ) {
        let w = pso.threadExecutionWidth
        let h = max(1, pso.maxTotalThreadsPerThreadgroup / w)
        let tg = MTLSize(width: w, height: h, depth: 1)
        let grid = MTLSize(width: width, height: height, depth: 1)
        enc.dispatchThreads(grid, threadsPerThreadgroup: tg)
    }

    private final class TextureBox: @unchecked Sendable {
        let texture: any MTLTexture
        init(_ t: any MTLTexture) { self.texture = t }
    }

    private final class BufferBox: @unchecked Sendable {
        let buffer: any MTLBuffer
        init(_ b: any MTLBuffer) { self.buffer = b }
    }
}
