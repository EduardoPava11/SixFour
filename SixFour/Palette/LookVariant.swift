import Foundation
import simd

/// A capture-screen LOOK: a data-driven OKLab palette→palette colour transform
/// derived from the captured palette's OWN luminance-zone chroma profile (a port
/// of `~/lut-generator/src/python/gif_palette_lut.py`, in OKLab). The user SWIPES
/// on the capture screen to cycle variants; the on-screen preview re-grades and
/// the SAME transform is what `extractLUT` bakes into the R3D `.cube`
/// (preview ≡ cube — golden-gated by `lut_fixture_test.zig`).
///
/// A variant only chooses strength + polarity; the PROFILE is always live-derived
/// from the current palette, so the look is "your scene, graded by itself", not a
/// canned recipe. `.off` is the honest identity (no grade).
enum LookVariant: String, CaseIterable, Codable, Sendable {
    case off, soft, medium, strong, inverted

    /// Cell-text label shown on the capture screen while this look is active.
    var displayName: String {
        switch self {
        case .off:      return "LOOK OFF"
        case .soft:     return "SOFT"
        case .medium:   return "MEDIUM"
        case .strong:   return "STRONG"
        case .inverted: return "INVERTED"
        }
    }

    /// Q16 transfer parameters for this variant (applied over a live-derived
    /// profile). Strength is the python `TRANSFER_STRENGTH`; `.inverted` flips the
    /// target hue (polarity −1) toward the scene's complement.
    var params: SixFourNative.LookParams {
        var p = SixFourNative.LookParams()
        switch self {
        case .off:      p.strength = 0
        case .soft:     p.strength = Self.q16(0.35)
        case .medium:   p.strength = Self.q16(0.60)
        case .strong:   p.strength = Self.q16(0.85)
        case .inverted: p.strength = Self.q16(0.60); p.polarity = -65536
        }
        return p
    }

    private static func q16(_ x: Double) -> Int32 { Int32((x * 65536).rounded()) }

    /// Next / previous look in the closed cycle (swipe-right / swipe-left).
    var next: LookVariant { Self.cycle(self, 1) }
    var prev: LookVariant { Self.cycle(self, -1) }
    private static func cycle(_ v: LookVariant, _ d: Int) -> LookVariant {
        let all = Self.allCases
        let i = all.firstIndex(of: v) ?? 0
        let n = ((i + d) % all.count + all.count) % all.count
        return all[n]
    }

    /// Re-grade an sRGB8 palette through this look — a cheap 256-colour round-trip
    /// through the Zig core (sRGB8 → OKLab → zone profile → transfer → sRGB8).
    /// `.off` (or any kernel failure) returns the palette unchanged, so the live
    /// preview never breaks. Recolours the 64×64 hero AND the 16×16 palette/shutter
    /// without moving anything (the index tile is untouched — cell-grid law safe).
    func apply(to palette: [SIMD3<UInt8>]) -> [SIMD3<UInt8>] {
        guard self != .off, !palette.isEmpty else { return palette }
        let rgb = palette.flatMap { [$0.x, $0.y, $0.z] }
        guard let oklab = SixFourNative.srgb8ToOklab(rgb: rgb, k: palette.count),
              let profile = SixFourNative.lookZoneProfile(paletteOklabQ16: oklab),
              let graded = SixFourNative.lookTransfer(oklabQ16: oklab, profile: profile, params: params),
              let out = SixFourNative.paletteToSRGB8(centroidsQ16: graded, k: palette.count)
        else { return palette }
        var result = [SIMD3<UInt8>]()
        result.reserveCapacity(palette.count)
        var i = 0
        while i + 2 < out.count {
            result.append(SIMD3(out[i], out[i + 1], out[i + 2]))
            i += 3
        }
        return result
    }
}
