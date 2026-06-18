import Foundation

/// The per-frame cube-ladder export family {16³, 64³, 256³}, carrying the chosen genome — the
/// "export the full stack" build (workflow `docs/SIXFOUR-AB-GAME-EXPORT-LEARNINGS-WORKFLOW.md` §3).
///
/// All three rungs are DETERMINISTIC and per-frame (no dependency on the V2-deferred global path):
/// - **64³** = the committed index cube (identity — the reference itself).
/// - **256³** = `SixFourExport.replicate4x` per frame (nearest-neighbour floor; the *learned*
///   `NetSynth256` detail above the floor is G6, a gated future enhancement).
/// - **16³** = temporal + spatial 4× subsample (the honest deterministic 16³ substrate).
/// The chosen 384-DOF genome rides in EVERY rung's GIF as an S4GN block (`GenomeCarrier`), so each
/// exported look is self-describing and shareable.
///
/// This type owns the index-cube transforms + the genome splicing. Turning a rung's index cube +
/// per-frame palettes into GIF bytes uses the existing `GIFEncoder` (which requires the branded
/// `CompleteVoxelVolume`) at the live render seam.
enum ABExportFamily {

    /// One rung: `frames` index frames of `side × side`.
    struct Rung { let side: Int; let frames: [[UInt8]] }

    /// The assembled family + the genome block to splice into each rung's GIF.
    struct Family { let rung16: Rung; let rung64: Rung; let rung256: Rung; let genomeBlock: [UInt8] }

    /// Split a flat `frames · side²` index cube into per-frame arrays.
    static func splitFrames(_ cube: [UInt8], frames: Int, side: Int) -> [[UInt8]] {
        let n = side * side
        return (0..<frames).map { f in Array(cube[(f * n)..<min((f + 1) * n, cube.count)]) }
    }

    /// Spatially subsample a `side×side` frame by `factor` (nearest, top-left of each block).
    static func subsampleSpatial(_ frame: [UInt8], side: Int, factor: Int) -> [UInt8] {
        let h = side / factor
        var out = [UInt8](repeating: 0, count: h * h)
        for y in 0..<h {
            for x in 0..<h { out[y * h + x] = frame[(y * factor) * side + (x * factor)] }
        }
        return out
    }

    /// Assemble {16³, 64³, 256³} from the committed 64³ cube + the chosen genome (Int32 Q16 coeffs).
    /// `factor` is the ×4 ladder step; with `frames = side = 64` the rungs are 16³ / 64³ / 256³.
    static func assemble(indexCube: [UInt8], frames: Int = 64, side: Int = 64,
                         factor: Int = 4, genome: [Int]) -> Family {
        let cube = splitFrames(indexCube, frames: frames, side: side)

        // 64³ — the committed cube (identity).
        let rung64 = Rung(side: side, frames: cube)

        // 256³ — replicate4x each frame (the nearest-neighbour floor).
        let rung256 = Rung(side: side * factor, frames: cube.map { SixFourExport.replicate($0, side: side, factor: factor) })

        // 16³ — temporal subsample (every `factor`-th frame) + spatial subsample.
        let temporal = stride(from: 0, to: frames, by: factor).map { cube[$0] }
        let rung16 = Rung(side: side / factor, frames: temporal.map { subsampleSpatial($0, side: side, factor: factor) })

        // The genome rides in every rung's GIF.
        let payload = GenomeCarrier.Payload(
            header: GenomeCarrier.Header(major: 1, minor: 0, flags: 0,
                                         dof: UInt16(genome.count), radix: 0, deviceIdHash: 0, btCompares: 0),
            coeffs: genome)
        return Family(rung16: rung16, rung64: rung64, rung256: rung256,
                      genomeBlock: GenomeCarrier.encode(payload))
    }

    /// Splice the genome S4GN block into a GIF89a byte stream (after the 13-byte header + logical
    /// screen descriptor — a valid Application-Extension position; `GenomeCarrier.extract` finds it
    /// anywhere). The exported GIF then self-describes its genome.
    static func spliceGenome(into gif: [UInt8], block: [UInt8]) -> [UInt8] {
        guard gif.count >= 13 else { return gif + block }
        return Array(gif[0..<13]) + block + Array(gif[13...])
    }
}
