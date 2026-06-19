import Foundation
import simd

/// Encodes the CHOSEN A/B look to a shareable GIF (P3b — "Share ships the chosen look").
///
/// The displayed A/B heroes re-quantize per candidate (P3a — genuinely different index cubes),
/// but the EXPORT re-encodes the COMPLETE base `indexCube` (the engine-validated
/// `CompleteVoxelVolume`) through the chosen look's per-frame palettes. This is:
///   - faithful to the chosen genome's COLOURS (the genome's visible effect), and
///   - always brand-encodable — a re-quantized candidate cube need NOT be K-surjective per
///     frame, so it cannot pass the per-frame completeness brand; the base cube always can.
///
/// The genome-carrying S4GN block + the {16³, 256³} cube-ladder rungs (`ABExportFamily`) are a
/// follow-on; this covers the core deliverable: the shared GIF reflects the user's pick.
enum ABExport {

    /// Re-encode `indexCube` (flat `t·pixelsPerFrame`) through `palettes` (T × 256 sRGB8) into a
    /// temp GIF, returning its URL — or `nil` if the inputs are not a complete 64³ volume or the
    /// encode declines (the caller then falls back to the base auto-render). Nonisolated so it
    /// can run off the κ clock.
    static func encodeChosenLook(indexCube: [UInt8], palettes: [[SIMD3<UInt8>]]) -> URL? {
        let t = SixFourShape.T
        let per = SixFourShape.pixelsPerFrame
        guard palettes.count == t, indexCube.count == t * per else { return nil }

        var frames = [[UInt8]]()
        frames.reserveCapacity(t)
        for i in 0 ..< t { frames.append(Array(indexCube[i * per ..< (i + 1) * per])) }

        // The base cube is the engine's validated render output, so this brand holds; a
        // candidate re-quant cube would not, which is why the export recolours the base.
        guard let volume = CompleteVoxelVolume(checkingFrames: frames) else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sixfour-look-\(UUID().uuidString).gif")
        do {
            // Export at 256×256 (the 256³ rung): GIFEncoder replicates each 64² index 4×4 at LZW
            // EMIT time, so the volume stays 64² (the brand holds, no memory blow-up) but every
            // colour pixel becomes a 4×4 "thick" block on a 256² canvas.
            try GIFEncoder(upscale: 4).encode(volume: volume, perFramePalettes: palettes, to: url,
                                              comment: "SixFour A/B look · 256² (4× thick pixels)")
            return url
        } catch {
            return nil
        }
    }
}
