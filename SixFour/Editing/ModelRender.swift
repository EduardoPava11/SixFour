import Foundation
import simd

/// Renders a model output (GIF89a structure: per-frame palette = VALUE, index plane =
/// CONTENT) to displayable pixels, byte-exactly via `palette[index]`.
///
/// Mirrors `SixFour.Spec.ModelIO.renderFrame` and consumes the spec-generated
/// `SixFourModelIO` contract (`SixFour/Generated/SixFourModelIO.swift`). The lookup core
/// is pure integer arithmetic (no float, no colour science) so it matches the spec
/// bit-for-bit; the OKLab → sRGB conversion is display-only and never re-enters the
/// byte-exact pipeline (the `SixFour.Spec.ByteCarrier` discipline, in Swift).
///
/// Scope (W2.1): this renders a GIVEN `SixFourModelOutput`. The zero-nudge output equals
/// the deterministic `Upscale256` floor (`SixFour.Spec.ModelIO.lawNeutralNudgeIsAllFloor`,
/// byte-exact via `lawK0PaletteExact`); asserting that equality in Swift is deferred to
/// when the `Upscale256` floor builder is wired (W1.2 follow-on / Phase 3), since no floor
/// builder exists on the Swift side yet.
enum ModelRender {

    /// The Q16 OKLab colour for one (frame, pixel): `palette[index]`, bounds-safe. This is
    /// the byte-exact core of `renderFrame` -- pure integer lookup, no float.
    static func paletteOKLabQ16(_ output: SixFourModelOutput, frame f: Int, pixel p: Int) -> SIMD3<Int> {
        let (palette, plane) = output.renderFrame(f)
        guard p >= 0, p < plane.count else { return SIMD3<Int>(0, 0, 0) }
        let idx = plane[p]
        guard idx >= 0, idx < palette.count else { return SIMD3<Int>(0, 0, 0) }
        return palette[idx]
    }

    /// A whole frame as Q16 OKLab pixels, one per index-plane entry (byte-exact).
    static func frameOKLabQ16(_ output: SixFourModelOutput, frame f: Int) -> [SIMD3<Int>] {
        let (palette, plane) = output.renderFrame(f)
        return plane.map { idx in
            (idx >= 0 && idx < palette.count) ? palette[idx] : SIMD3<Int>(0, 0, 0)
        }
    }

    /// Convert a Q16 OKLab pixel to display sRGB8 (defers to `ColorScience`). Float path;
    /// display-only, never re-enters the byte-exact pipeline.
    static func displaySRGB8(_ q16: SIMD3<Int>) -> SIMD3<UInt8> {
        let lab = OKLab(Float(q16.x) / 65536, Float(q16.y) / 65536, Float(q16.z) / 65536)
        return ColorScience.okLabToSRGB8(lab)
    }

    /// Render a frame to packed RGBA8 for the screen (alpha = 255).
    static func frameRGBA8(_ output: SixFourModelOutput, frame f: Int) -> [SIMD4<UInt8>] {
        frameOKLabQ16(output, frame: f).map { q in
            let c = displaySRGB8(q)
            return SIMD4<UInt8>(c.x, c.y, c.z, 255)
        }
    }

    /// Defense-in-depth self-check: the generated contract holds and `palette[index]`
    /// round-trips on a synthetic output. Pure; safe to call at startup or in a test.
    static func selfCheck() -> Bool {
        guard SixFourModelIO.selfCheck() else { return false }

        let pal: [SIMD3<Int>] = [SIMD3(0, 0, 0), SIMD3(65536, 0, 0), SIMD3(0, 65536, 0)]
        let out = SixFourModelOutput(palettes: [pal, pal], indexPlanes: [[0, 1, 2, 1], [2, 2, 0, 0]])

        // renderFrame returns the right (palette, plane) pair.
        let (p0, plane0) = out.renderFrame(0)
        guard p0.count == 3, plane0 == [0, 1, 2, 1] else { return false }

        // palette[index] lookups are byte-exact.
        guard paletteOKLabQ16(out, frame: 0, pixel: 1) == SIMD3(65536, 0, 0) else { return false }
        guard frameOKLabQ16(out, frame: 1) == [pal[2], pal[2], pal[0], pal[0]] else { return false }

        // Render-correctness invariant (NOT the model floor): a uniform index plane renders
        // a single colour. The true zero-nudge == Upscale256 floor equality is deferred.
        let uniform = SixFourModelOutput(palettes: [pal], indexPlanes: [[0, 0, 0, 0]])
        guard frameOKLabQ16(uniform, frame: 0).allSatisfy({ $0 == pal[0] }) else { return false }

        return true
    }
}
