import CoreVideo
import Metal

/// Thin wrapper around CVMetalTextureCache so the rest of the code never
/// has to think about CV objects. Single-threaded use (the capture delegate
/// queue) — the underlying CVMetalTextureCache is documented thread-safe but
/// we serialize on a known queue.
final class MetalTextureCache: @unchecked Sendable {
    let device: any MTLDevice
    private var cache: CVMetalTextureCache?

    init(device: any MTLDevice) {
        self.device = device
        var c: CVMetalTextureCache?
        let result = CVMetalTextureCacheCreate(
            kCFAllocatorDefault, nil, device, nil, &c
        )
        precondition(result == kCVReturnSuccess, "CVMetalTextureCacheCreate failed: \(result)")
        self.cache = c
    }

    /// Wrap a BGRA CVPixelBuffer as an MTLTexture without copying.
    func textureBGRA(from pixelBuffer: CVPixelBuffer) -> (any MTLTexture)? {
        guard let cache else { return nil }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        var cvTex: CVMetalTexture?
        let r = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pixelBuffer, nil,
            .bgra8Unorm, w, h, 0, &cvTex
        )
        guard r == kCVReturnSuccess, let cvTex else { return nil }
        return CVMetalTextureGetTexture(cvTex)
    }

    /// Wrap a 4:2:0 biplanar 10-bit YpCbCr CVPixelBuffer as two MTLTextures:
    /// luma (R16Unorm at full res) and chroma (RG16Unorm at half res).
    /// 10-bit values are stored in the upper bits of each 16-bit word.
    func texturesYCbCr10(from pixelBuffer: CVPixelBuffer) -> (luma: any MTLTexture, chroma: any MTLTexture)? {
        guard let cache else { return nil }
        let yw = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let yh = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let cw = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
        let ch = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)

        var yCVTex: CVMetalTexture?
        let r1 = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pixelBuffer, nil,
            .r16Unorm, yw, yh, 0, &yCVTex
        )
        var cCVTex: CVMetalTexture?
        let r2 = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pixelBuffer, nil,
            .rg16Unorm, cw, ch, 1, &cCVTex
        )
        guard r1 == kCVReturnSuccess, r2 == kCVReturnSuccess,
              let yCVTex, let cCVTex,
              let luma = CVMetalTextureGetTexture(yCVTex),
              let chroma = CVMetalTextureGetTexture(cCVTex)
        else { return nil }
        return (luma, chroma)
    }

    func flush() {
        if let cache { CVMetalTextureCacheFlush(cache, 0) }
    }
}
