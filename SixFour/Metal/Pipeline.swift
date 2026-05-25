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

    init(tileSide: Int = 64) throws {
        guard let dev = MTLCreateSystemDefaultDevice() else { throw MetalPipelineError.noDevice }
        guard let q = dev.makeCommandQueue() else { throw MetalPipelineError.noQueue }
        guard let lib = dev.makeDefaultLibrary() else { throw MetalPipelineError.noLibrary }
        q.label = "capture"
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
        // Single YCbCr10 entry-point — BGRA path deleted per no-fallback rule.
        self.cropDownsampleLinearizePSO = try pso("cropDownsampleLinearizeKernel")
        self.linearToOklabPSO = try pso("linearToOklabKernel")
        self.unsharpPSO = try pso("unsharpMaskLKernel")
        Self.logger.info("MetalPipeline (capture) init: tileSide=\(tileSide) device=\(dev.name)")
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
