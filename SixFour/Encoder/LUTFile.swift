import Foundation
import simd
import SwiftUI
import UIKit

/// Writes a LOOK as a DaVinci-Resolve-ready `.cube` 3D LUT for grading R3D footage.
/// Input domain = REDWideGamutRGB / Log3G10; output = palette-styled Rec.709 (sRGB
/// gamma). The cube is built by the deterministic Zig core
/// (`SixFourNative.extractLUT`) from the captured palette's luminance-zone profile
/// — the SAME OKLab transform the on-screen look uses, so what you swiped is what
/// you export (preview ≡ cube, golden-gated by `lut_fixture_test.zig`).
enum LUTFile {
    /// Shipped grid size (the python `LUT_SIZE`). 65³ = 274,625 entries.
    static let size = 65

    /// Build the `.cube` for `look` over the captured `palette`, write it to a temp
    /// file, and return a share item. Returns `nil` on `.off`, an empty palette, or
    /// a kernel failure. Builds the profile from the palette itself (data-driven).
    static func makeShareItem(palette: [SIMD3<UInt8>], look: LookVariant) -> LUTShareItem? {
        guard look != .off, !palette.isEmpty else { return nil }
        let rgb = palette.flatMap { [$0.x, $0.y, $0.z] }
        guard let oklab = SixFourNative.srgb8ToOklab(rgb: rgb, k: palette.count),
              let profile = SixFourNative.lookZoneProfile(paletteOklabQ16: oklab),
              let cube = SixFourNative.extractLUT(profile: profile, params: look.params, size: size)
        else { return nil }
        let text = cubeText(cube: cube, size: size, look: look)
        let name = "SixFour_\(look.rawValue.capitalized)_Rec709.cube"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { return nil }
        return LUTShareItem(url: url)
    }

    /// Format the Q16 sRGB-encoded cube as `.cube` text: an Adobe-cube header then
    /// N³ lines of `r g b` to 6 decimals (`value / 65536`), in .cube order (R
    /// fastest, then G, then B — exactly how `s4_build_cube_q16` lays it out).
    static func cubeText(cube: [Int32], size: Int, look: LookVariant) -> String {
        var s = ""
        s.reserveCapacity(size * size * size * 26 + 256)
        s += "# SixFour look LUT — \(look.displayName)\n"
        s += "# Input:  REDWideGamutRGB / Log3G10 (R3D)\n"
        s += "# Output: palette-styled Rec.709 (sRGB gamma)\n"
        s += "# Method: data-driven OKLab luminance-zone chrominance transfer\n"
        s += "#\n"
        s += "TITLE \"SixFour \(look.displayName)\"\n"
        s += "LUT_3D_SIZE \(size)\n"
        s += "DOMAIN_MIN 0.0 0.0 0.0\n"
        s += "DOMAIN_MAX 1.0 1.0 1.0\n"
        s += "\n"
        let inv = 1.0 / 65536.0
        let n3 = size * size * size
        var i = 0
        while i < n3 {
            let r = Double(cube[i * 3 + 0]) * inv
            let g = Double(cube[i * 3 + 1]) * inv
            let b = Double(cube[i * 3 + 2]) * inv
            s += String(format: "%.6f %.6f %.6f\n", r, g, b)
            i += 1
        }
        return s
    }
}

/// A written `.cube` ready to share (the `item:` of a presentation sheet).
struct LUTShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Minimal `UIActivityViewController` bridge for sharing the `.cube` file (the
/// shipped app stays zero-dependency; this is a system framework).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
