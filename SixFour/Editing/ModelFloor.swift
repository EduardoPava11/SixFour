import Foundation
import simd

/// Adapts the existing byte-exact per-frame cube (the committed 64³ hero: per-frame
/// Q16 OKLab palettes + index planes) into the model I/O OUTPUT contract
/// `SixFourModelOutput`, so the W2.1 `ModelRender` surface (and next, the paint tool)
/// previews the REAL, byte-exact floor instead of a synthetic stub.
///
/// This is the floor at the 64³ rung — `DeterministicRenderer` / `LadderGIF` already
/// produce it, byte-exact against the Haskell goldens. The 256³ super-res floor
/// (`SixFour.Spec.Upscale256.upscale256`; zero-nudge byte-exact via `lawK0PaletteExact`)
/// is the eventual upgrade: the codebase defers the 256³ rungs as a tiled decode
/// (`LadderExport`), so a Swift `upscale256` port is Phase 3 work. Until then this
/// adapter is the honest floor the render previews against. The conversion is pure
/// integer widening (`Int32`→`Int`, `UInt8`→`Int`), so it preserves byte-exactness.
enum ModelFloor {

    /// Build a `SixFourModelOutput` from the native cube representation: per-frame Q16
    /// OKLab palettes (`OKLabQ16` = `SIMD3<Int32>`) and per-frame index planes
    /// (`[UInt8]`). Pure and byte-exact — only the integer widths change.
    static func output(perFramePalettes: [[OKLabQ16]], indexPlanes: [[UInt8]]) -> SixFourModelOutput {
        let palettes = perFramePalettes.map { frame in
            frame.map { c in SIMD3<Int>(Int(c.x), Int(c.y), Int(c.z)) }
        }
        let planes = indexPlanes.map { plane in plane.map { Int($0) } }
        return SixFourModelOutput(palettes: palettes, indexPlanes: planes)
    }

    /// Defense-in-depth self-check: a tiny native cube round-trips through the adapter and
    /// renders byte-exact via `ModelRender` (palette[index]).
    static func selfCheck() -> Bool {
        let pal: [OKLabQ16] = [OKLabQ16(0, 0, 0), OKLabQ16(65536, 0, 0), OKLabQ16(0, 65536, 0)]
        let out = output(perFramePalettes: [pal], indexPlanes: [[0, 1, 2, 1]])

        guard out.palettes.count == 1, out.indexPlanes == [[0, 1, 2, 1]] else { return false }
        guard out.palettes[0][1] == SIMD3<Int>(65536, 0, 0) else { return false }   // byte-exact widen
        guard ModelRender.frameOKLabQ16(out, frame: 0)
                == [SIMD3<Int>(0, 0, 0), SIMD3<Int>(65536, 0, 0),
                    SIMD3<Int>(0, 65536, 0), SIMD3<Int>(65536, 0, 0)] else { return false }
        return true
    }
}
