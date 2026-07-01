import Foundation
import Metal
import CoreVideo
import simd
import os

/// Per-frame OKLab tile.
///
/// `submitAsync` produces tiles with `palette` empty and `finalShift = 0` —
/// capture only converts the camera frame to OKLab pixels. The 256-entry
/// palette is filled later, post-burst, by a `PalettePipeline`
/// (`KMeansPalettePipeline` / `WuPalettePipeline` / `OctreePalettePipeline`)
/// running on all 64 tiles at once.
///
/// Per-pixel indices are NOT included — those are produced downstream by
/// CPU-side error-diffusion dither against the palette.
struct OKLabTile: Sendable, Codable {
    let side: Int
    let pixels: [SIMD3<Float>]
    let captureNanos: UInt64
    let palette: [SIMD3<Float>]      // K centroids in OKLab (length K); empty until a palette pipeline runs
    let finalShift: Float            // diagnostic only — Σ‖μ' − μ‖² on last iter (set by k-means)
}

/// Capture-time Metal pipeline. Per camera frame:
///   1. cropDownsampleLinearizeKernel  YCbCr10 → RGBA16F(tile²×tile², linear-light)
///   2. linearToOklabKernel            RGBA16F linear → RGBA16F OKLab
///   3. unsharpMaskLKernel             RGBA16F OKLab → RGBA16F OKLab (L sharpened)
///
/// Submission is non-blocking; the completion handler reads back the final
/// OKLab texture. Palette extraction is NOT done here — it lives in the
/// per-algorithm `PalettePipeline`s so each algorithm logs independently.
final class MetalPipeline: @unchecked Sendable {
    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let textureCache: MetalTextureCache
    let tileSide: Int
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
    /// The V2.1 probability-field accumulator (`v21AccumulateHistKernel`): the device twin of Zig
    /// `s4_v21_accumulate_hist`. Dispatched additively per frame only when a `V21HistDispatch` is
    /// passed to `submitAsync` (gated by `Feature.v21Capture`), so the shipped path is unaffected.
    /// OPTIONAL: V2.1 is experimental and must never fail the whole capture pipeline, so a device that
    /// can't build this PSO runs without it (export falls back to the temporal-proxy field).
    let v21HistPSO: (any MTLComputePipelineState)?
    /// The V2.1 SOFT-SPLAT accumulator (`v21AccumulateHistSoftKernel`): the sub-LSB construction that
    /// uses the 10-bit sensor bits the hard round() discards, twin of Zig `s4_v21_accumulate_hist_soft`.
    /// Preferred over `v21HistPSO` for building the field when available (same output layout, richer
    /// counts). OPTIONAL for the same never-fatal reason.
    let v21HistSoftPSO: (any MTLComputePipelineState)?
    /// The sub-level weight budget for the soft splat: each value LSB is subdivided into this many
    /// integer sub-steps (16 = 4 extra bits, ample for the 10-bit sensor plus the box average). Bound so
    /// the per-bin total (scale²·budget·frames) stays inside the Int32 count envelope.
    static let v21SoftBudget: Int32 = 16

    init(tileSide: Int = 64) throws {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            Self.logger.error("MetalPipeline init FAILED: MTLCreateSystemDefaultDevice returned nil")
            throw MetalPipelineError.noDevice
        }
        guard let q = dev.makeCommandQueue() else {
            Self.logger.error("MetalPipeline init FAILED: makeCommandQueue nil (device=\(dev.name, privacy: .public))")
            throw MetalPipelineError.noQueue
        }
        guard let lib = dev.makeDefaultLibrary() else {
            Self.logger.error("MetalPipeline init FAILED: makeDefaultLibrary nil (default.metallib missing or unsigned?)")
            throw MetalPipelineError.noLibrary
        }
        q.label = "capture"
        func pso(_ name: String) throws -> any MTLComputePipelineState {
            guard let fn = lib.makeFunction(name: name) else {
                Self.logger.error("MetalPipeline init FAILED: kernel '\(name, privacy: .public)' not in default.metallib")
                throw MetalPipelineError.missingKernel(name)
            }
            return try dev.makeComputePipelineState(function: fn)
        }
        self.device = dev
        self.queue = q
        self.textureCache = MetalTextureCache(device: dev)
        self.tileSide = tileSide
        // Single YCbCr10 entry-point — BGRA path deleted per no-fallback rule.
        self.cropDownsampleLinearizePSO = try pso("cropDownsampleLinearizeKernel")
        self.linearToOklabPSO = try pso("linearToOklabKernel")
        self.unsharpPSO = try pso("unsharpMaskLKernel")
        // V2.1 (gated, experimental): NEVER fatal. If the kernel PSO can't be built on this device,
        // log it and run without the live field; the shipped capture path is unaffected.
        do {
            self.v21HistPSO = try pso("v21AccumulateHistKernel")
        } catch {
            Self.logger.error("MetalPipeline: v21AccumulateHistKernel unavailable, V2.1 live field OFF: \(String(describing: error), privacy: .public)")
            self.v21HistPSO = nil
        }
        do {
            self.v21HistSoftPSO = try pso("v21AccumulateHistSoftKernel")
        } catch {
            Self.logger.error("MetalPipeline: v21AccumulateHistSoftKernel unavailable, V2.1 sub-LSB field OFF (hard fallback): \(String(describing: error), privacy: .public)")
            self.v21HistSoftPSO = nil
        }
        Self.logger.log("MetalPipeline (capture) init OK: tileSide=\(tileSide) device=\(dev.name, privacy: .public) v21=\(self.v21HistPSO != nil) v21soft=\(self.v21HistSoftPSO != nil)")
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

    /// Submit one camera frame. Returns immediately; completion fires when the
    /// GPU finishes. Builds a 3-pass command buffer (crop+linearize → OKLab →
    /// unsharp), then reads back the OKLab tile. Palette extraction runs later
    /// on all tiles via a `PalettePipeline`.
    /// One frame's slice of a V2.1 probability-field accumulation: the persistent burst histogram
    /// buffer (from `makeV21HistBuffer`), this frame's `coarseFrame` index along `t`, and the level
    /// alphabet. Passed to `submitAsync` so the hist pass rides the SAME per-frame command buffer.
    struct V21HistDispatch {
        let buffer: any MTLBuffer
        let coarseFrame: Int
        let nLevels: Int
    }

    func submitAsync(
        pixelBuffer: CVPixelBuffer,
        captureNanos: UInt64,
        v21Hist: V21HistDispatch? = nil,
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

        // V2.1 (gated): additively accumulate this frame's camera-box histogram into the burst buffer
        // at slice `coarseFrame`. Same source textures, crop offset, and scale as the box-average pass,
        // so the field is the box-average's distributional sibling. Off the shipped path when nil.
        if let v21 = v21Hist {
            try encodeV21Hist(cmd: cmd, pixelBuffer: pixelBuffer, geom: geom,
                              histBuffer: v21.buffer, coarseFrame: v21.coarseFrame, nLevels: v21.nLevels)
        }

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

    private struct Intermediates {
        let linear: any MTLTexture
        let lab: any MTLTexture
        let output: any MTLTexture
    }

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

    /// Allocate the persistent burst histogram buffer for a V2.1 capture: `frames · tileSide² · 3 ·
    /// nLevels` `Int32`s, `.storageModeShared` so the CPU can read it after the burst. Layout matches
    /// the Zig `s4_v21_accumulate_hist` / Metal kernel: `((coarseFrame·cy + y)·cx + x)·3·nLevels`.
    /// Returns nil if the allocation fails (the caller falls back to the index-cube proxy field).
    func makeV21HistBuffer(frames: Int, nLevels: Int) -> (any MTLBuffer)? {
        let count = frames * tileSide * tileSide * 3 * nLevels
        let bytes = count * MemoryLayout<Int32>.stride
        return device.makeBuffer(length: bytes, options: [.storageModeShared])
    }

    /// Pool a burst histogram buffer over the `t` axis into the time-pooled field the V2.1 export uses:
    /// `[y, x, 3, nLevels]` (`tileSide² · 3 · nLevels` `Int32`s), summing each spatial bin's per-frame
    /// histograms. This is the camera-box twin of `V21FieldData.fromCapture`'s index-cube histogram.
    static func poolV21Counts(buffer: any MTLBuffer, frames: Int, tileSide: Int, nLevels: Int) -> [Int32] {
        let spatial = tileSide * tileSide * 3 * nLevels
        var out = [Int32](repeating: 0, count: spatial)
        let ptr = buffer.contents().bindMemory(to: Int32.self, capacity: frames * spatial)
        for t in 0 ..< frames {
            let base = t * spatial
            for i in 0 ..< spatial { out[i] &+= ptr[base + i] }
        }
        return out
    }

    private func encodeV21Hist(
        cmd: any MTLCommandBuffer,
        pixelBuffer: CVPixelBuffer,
        geom: PixelBufferGeometry,
        histBuffer: any MTLBuffer,
        coarseFrame: Int,
        nLevels: Int
    ) throws {
        // Prefer the SOFT-SPLAT kernel (the sub-LSB construction) when its PSO built; fall back to the
        // hard accumulator, then skip silently if neither is available (shipped path unaffected).
        let soft = v21HistSoftPSO != nil
        guard let pso = v21HistSoftPSO ?? v21HistPSO else { return }
        guard let enc = cmd.makeComputeCommandEncoder() else {
            throw MetalPipelineError.commandFailed
        }
        defer { enc.endEncoding() }
        guard let pair = textureCache.texturesYCbCr10(from: pixelBuffer) else {
            throw MetalPipelineError.textureCreationFailed
        }
        var offset = SIMD2<Int32>(Int32(geom.offsetX), Int32(geom.offsetY))
        var scaleVal = Int32(geom.scale)
        var tag = colorSpaceTag
        var levels = Int32(nLevels)
        var coarseDims = SIMD2<Int32>(Int32(tileSide), Int32(tileSide))
        var frame = Int32(coarseFrame)
        var budget = Self.v21SoftBudget
        enc.setComputePipelineState(pso)
        enc.setTexture(pair.luma, index: 0)
        enc.setTexture(pair.chroma, index: 1)
        enc.setBuffer(histBuffer, offset: 0, index: 0)
        enc.setBytes(&offset, length: MemoryLayout<SIMD2<Int32>>.size, index: 1)
        enc.setBytes(&scaleVal, length: MemoryLayout<Int32>.size, index: 2)
        enc.setBytes(&tag, length: MemoryLayout<UInt8>.size, index: 3)
        enc.setBytes(&levels, length: MemoryLayout<Int32>.size, index: 4)
        enc.setBytes(&coarseDims, length: MemoryLayout<SIMD2<Int32>>.size, index: 5)
        enc.setBytes(&frame, length: MemoryLayout<Int32>.size, index: 6)
        if soft { enc.setBytes(&budget, length: MemoryLayout<Int32>.size, index: 7) }
        dispatch2D(enc, width: tileSide, height: tileSide, pso: pso)
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

    // MARK: - Readback

    /// Read an RGBA16Float texture back to host memory and convert each pixel
    /// to a `SIMD3<Float>` OKLab triple. The returned tile carries an empty
    /// `palette`; a `PalettePipeline` fills it after the burst.
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
}
