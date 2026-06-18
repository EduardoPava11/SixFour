import Foundation

/// Derives the two orthogonal A/B candidate looks from a captured per-frame palette, on device.
///
/// Composes the owned `GenomePair` port (`sampleOrthogonalPair`) with EXISTING FFI — zero new
/// native code: sRGB8 → OKLab Q16 (`srgb8ToOklab`) → the base genome's generators → the orthogonal
/// displacement pair → σ-pair leaves (`leafOverride`) → sRGB8 (`paletteToSRGB8`). The pair is
/// EXACTLY orthogonal by construction (`GenomePairGoldenTests`), so A and B explore independent
/// directions of the look space. Cold-start path (empty ranking) = the day-1 look before θ trains.
enum ABCandidates {
    typealias RGB = SIMD3<UInt8>

    /// The σ-pair genome width: 128 generators → 256 σ-pair leaves.
    static let generatorCount = 128

    /// Build candidate A and B sRGB palettes from a per-frame palette (≥ 256 colours). Returns nil
    /// on any FFI failure (the caller then shows no picker — MVP1 is unaffected since the surfacing
    /// is gated by `Feature.abCandidatePicker`).
    static func fromPalette(_ palette: [RGB]) -> (a: [RGB], b: [RGB])? {
        guard palette.count >= 2 * generatorCount else { return nil }

        // 1. sRGB8 → OKLab Q16 leaves.
        var rgbFlat = [UInt8](); rgbFlat.reserveCapacity(palette.count * 3)
        for c in palette { rgbFlat.append(c.x); rgbFlat.append(c.y); rgbFlat.append(c.z) }
        guard let oklabFlat = SixFourNative.srgb8ToOklab(rgb: rgbFlat, k: palette.count) else { return nil }
        let leaves: [SIMD3<Int32>] = stride(from: 0, to: oklabFlat.count, by: 3).map {
            SIMD3<Int32>(oklabFlat[$0], oklabFlat[$0 + 1], oklabFlat[$0 + 2])
        }

        // 2. The base genome's generators (first 128 leaves) and the orthogonal A/B displacements.
        let generators = Array(leaves.prefix(generatorCount))
        let (da, db) = GenomePair.sampleOrthogonalPair(generators: generators, ranking: [])

        // 3. Apply each displacement → σ-pair leaves → sRGB8.
        func render(_ delta: [SIMD3<Int32>]) -> [RGB]? {
            guard let leavesQ16 = SixFourNative.leafOverride(generators: generators, deltas: delta) else { return nil }
            var flat = [Int32](); flat.reserveCapacity(leavesQ16.count * 3)
            for c in leavesQ16 { flat.append(c.x); flat.append(c.y); flat.append(c.z) }
            guard let srgb = SixFourNative.paletteToSRGB8(centroidsQ16: flat, k: leavesQ16.count) else { return nil }
            return stride(from: 0, to: srgb.count, by: 3).map { RGB(srgb[$0], srgb[$0 + 1], srgb[$0 + 2]) }
        }
        guard let a = render(da), let b = render(db) else { return nil }
        return (a, b)
    }
}
