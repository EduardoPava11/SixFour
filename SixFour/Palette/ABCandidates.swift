import Foundation

/// Derives the two orthogonal A/B candidate looks from a captured per-frame palette, on device.
///
/// Composes the owned `GenomePair` port (`sampleOrthogonalPair`) with EXISTING FFI — zero new
/// native code: sRGB8 → OKLab Q16 (`srgb8ToOklab`) → the base genome's generators → (θ-tint toward
/// the user's learned taste) → the orthogonal displacement pair → σ-pair leaves (`leafOverride`) →
/// sRGB8 (`paletteToSRGB8`). The pair is EXACTLY orthogonal by construction (`GenomePairGoldenTests`).
/// Cold start (θ empty) = the day-1 look; each pick folds θ so the next pair tracks taste.
enum ABCandidates {
    typealias RGB = SIMD3<UInt8>
    typealias Q16 = SIMD3<Int32>

    /// The σ-pair genome width: 128 generators → 256 σ-pair leaves.
    static let generatorCount = 128

    /// One candidate look: the sRGB swatch (for the tile) + its Q16 leaves (for the `btUpdate`
    /// embedding when this candidate wins/loses).
    struct Candidate { let rgb: [RGB]; let leaves: [Q16] }

    /// Build candidate A and B from a per-frame palette (≥ 256 colours), tinting the base genome by
    /// the taste vector `theta` (empty = cold start). Returns nil on any FFI failure (caller then
    /// shows no picker — MVP1 is unaffected since the surfacing is gated by `Feature.abCandidatePicker`).
    static func fromPalette(_ palette: [RGB], theta: [Double] = []) -> (a: Candidate, b: Candidate)? {
        guard palette.count >= 2 * generatorCount else { return nil }

        // 1. sRGB8 → OKLab Q16 leaves.
        var rgbFlat = [UInt8](); rgbFlat.reserveCapacity(palette.count * 3)
        for c in palette { rgbFlat.append(c.x); rgbFlat.append(c.y); rgbFlat.append(c.z) }
        guard let oklabFlat = SixFourNative.srgb8ToOklab(rgb: rgbFlat, k: palette.count) else { return nil }
        let leaves: [Q16] = stride(from: 0, to: oklabFlat.count, by: 3).map {
            Q16(oklabFlat[$0], oklabFlat[$0 + 1], oklabFlat[$0 + 2])
        }

        // 2. The base genome's generators (first 128 leaves), shifted toward the user's taste.
        var generators = Array(leaves.prefix(generatorCount))
        if !theta.isEmpty { generators = PersonalTaste.leafTint(generators, theta: theta) }

        // 3. The orthogonal A/B displacements (cold-start ranking by colour energy).
        let (da, db) = GenomePair.sampleOrthogonalPair(generators: generators, ranking: [])

        // 4. Apply each displacement → σ-pair leaves → sRGB8.
        func render(_ delta: [Q16]) -> Candidate? {
            guard let leavesQ16 = SixFourNative.leafOverride(generators: generators, deltas: delta) else { return nil }
            var flat = [Int32](); flat.reserveCapacity(leavesQ16.count * 3)
            for c in leavesQ16 { flat.append(c.x); flat.append(c.y); flat.append(c.z) }
            guard let srgb = SixFourNative.paletteToSRGB8(centroidsQ16: flat, k: leavesQ16.count) else { return nil }
            let rgb: [RGB] = stride(from: 0, to: srgb.count, by: 3).map { RGB(srgb[$0], srgb[$0 + 1], srgb[$0 + 2]) }
            return Candidate(rgb: rgb, leaves: leavesQ16)
        }
        guard let a = render(da), let b = render(db) else { return nil }
        return (a, b)
    }

    /// DELTA-PRESERVING A/B (the genome-game redesign): instead of an unbounded per-leaf θ-tint
    /// (the degrader), apply ONE bounded `IsoMove` isometry per candidate to the WHOLE palette, so
    /// every relative colour delta is preserved exactly (`SixFour.Spec.IsometryMove`). A and B are
    /// two scheduled moves; the look shifts coherently, never degrades. Returns each candidate's
    /// sRGB palette + its moved OKLab Q16 leaves (for the chosen-look export). Nil on FFI failure.
    static func deltaPreservingPair(_ palette: [RGB], moveA: IsoMove, moveB: IsoMove)
        -> (a: Candidate, b: Candidate)? {
        guard palette.count >= 256 else { return nil }

        var rgbFlat = [UInt8](); rgbFlat.reserveCapacity(palette.count * 3)
        for c in palette { rgbFlat.append(c.x); rgbFlat.append(c.y); rgbFlat.append(c.z) }
        guard let oklabFlat = SixFourNative.srgb8ToOklab(rgb: rgbFlat, k: palette.count) else { return nil }
        let leaves: [Q16] = stride(from: 0, to: oklabFlat.count, by: 3).map {
            Q16(oklabFlat[$0], oklabFlat[$0 + 1], oklabFlat[$0 + 2])
        }

        func move(_ m: IsoMove) -> Candidate? {
            let moved = leaves.map { m.apply($0) }                 // ONE isometry → all leaves
            var flat = [Int32](); flat.reserveCapacity(moved.count * 3)
            for c in moved { flat.append(c.x); flat.append(c.y); flat.append(c.z) }
            guard let srgb = SixFourNative.paletteToSRGB8(centroidsQ16: flat, k: moved.count) else { return nil }
            let rgb: [RGB] = stride(from: 0, to: srgb.count, by: 3).map { RGB(srgb[$0], srgb[$0 + 1], srgb[$0 + 2]) }
            return Candidate(rgb: rgb, leaves: moved)
        }
        guard let a = move(moveA), let b = move(moveB) else { return nil }
        return (a, b)
    }
}
