import Foundation
import simd

/// Produces any shareable GIF-**ladder** rung (SIXFOUR-WIDGETS Family 1) from the Review
/// surface data, on demand, to a temp file — the backend of the "save a GIF, any size"
/// gesture. Deterministic, no NN: collapse the 64 per-frame palettes to ONE global table
/// (via `branching`), reindex the cube against it (`LadderGIF`), encode with the
/// global-color-table `GIFEncoder` mode. 16³ is a cheap working copy; 64³-B is the GIFB.
enum LadderExport {

    /// The rungs the deterministic producer can emit today. (Per-frame 64³-A is already
    /// the committed hero `Surface.gifURL`; the two 256³ rungs are the deferred tiled
    /// decode.) `16³` is the free, any-time working copy.
    enum Rung: String, CaseIterable, Identifiable, Sendable {
        case working16     // 16³ working copy — global palette, cheap snapshot
        case global64      // 64³-B — the global GIFB

        var id: String { rawValue }
        var title: String {
            switch self {
            case .working16: "16³ working copy"
            case .global64:  "64³ global (GIFB)"
            }
        }
    }

    /// Build the chosen rung from the surface's per-frame palettes + index cube, collapsed
    /// to one global palette via `branching`. Returns a temp-file URL for the share sheet.
    static func makeURL(rung: Rung,
                        palettesPerFrame: [[SIMD3<UInt8>]],
                        indexCube: [UInt8],
                        branching: PaletteBranching,
                        srcSide: Int = SixFourShape.W,
                        srcFrames: Int = SixFourShape.T) throws -> URL {
        let perFrameQ16 = toQ16(palettesPerFrame)
        let global = FarthestPointCollapse()
            .collapse(perFramePalettes: perFrameQ16, k: SixFourShape.K, branching: branching)
            .branchedLeaves
        let cube = chunkFrames(indexCube, side: srcSide, frames: srcFrames)

        switch rung {
        case .global64:
            let url = tempURL("sixfour-64-global")
            try LadderGIF.encodeGlobalGIF(perFramePalettes: perFrameQ16, frameIndices: cube,
                                          global: global, side: srcSide,
                                          upscale: SixFourExport.upscaleFactor, to: url)
            return url
        case .working16:
            // 16³: subsample frames AND per-frame palettes the SAME way (both use
            // `temporalSubsample` floor-stride, so they stay aligned), shrink spatially.
            let frames16 = LadderGIF.workingCopy(frameIndices: cube, srcSide: srcSide, side: 16, frames: 16)
            let palettes16 = LadderGIF.temporalSubsample(perFrameQ16, dstCount: 16)
            let url = tempURL("sixfour-16-working")
            try LadderGIF.encodeGlobalGIF(perFramePalettes: palettes16, frameIndices: frames16,
                                          global: global, side: 16, upscale: 1, to: url)
            return url
        }
    }

    // MARK: - Helpers

    /// sRGB8 per-frame palettes → Q16 OKLab (mirrors `FarthestPointCollapse
    /// .collapseForDisplay`'s conversion — the Q16 substrate the collapse expects).
    private static func toQ16(_ frames: [[SIMD3<UInt8>]]) -> [[OKLabQ16]] {
        frames.map { frame in
            frame.map { c in
                let lab = ColorScience.srgb8ToOKLab(c.x, c.y, c.z).simd
                return OKLabQ16(Int32((lab.x * 65536).rounded(.toNearestOrEven)),
                                Int32((lab.y * 65536).rounded(.toNearestOrEven)),
                                Int32((lab.z * 65536).rounded(.toNearestOrEven)))
            }
        }
    }

    /// Chunk the flat `side·side·frames` index cube into per-frame index arrays.
    private static func chunkFrames(_ cube: [UInt8], side: Int, frames: Int) -> [[UInt8]] {
        let per = side * side
        guard cube.count >= per * frames else { return [] }
        return (0 ..< frames).map { Array(cube[($0 * per) ..< (($0 + 1) * per)]) }
    }

    private static func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name).gif")
    }
}

/// Share-sheet item for a produced ladder GIF (mirrors `LUTShareItem`). `Sendable` so the
/// background producer task can hand it back to the main actor.
struct LadderShareItem: Identifiable, Sendable {
    let id = UUID()
    let url: URL
}
