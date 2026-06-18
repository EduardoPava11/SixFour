import Foundation
import simd

/// COLOR ATLAS — the 16³ curation board (docs/COLOR-ATLAS.md §2).
///
/// Swift mirror (UI-track stub) of the PLANNED spec module
/// `SixFour.Spec.AtlasBoard` (`Board16`). Until that module lands and emits a
/// generated contract, this file mirrors the two pieces of arithmetic that are
/// ALREADY spec-pinned elsewhere and adds no authority of its own:
///
///   * the bin rule is `SixFour.Spec.Coverage.okLabBin` in Q16 integer form —
///     byte-identical to the binning `DeterministicRenderer.renderGlobalPalette`
///     uses for `globalCoverage` (`(v·16) >> 16`, a/b shifted by +0.5 = 32768 Q16,
///     clamped to [0,15]);
///   * the grid size is the generated `SixFourShape.coverageBinsPerAxis` (16),
///     never a free literal.
///
/// The board is the AlphaGo "board state s": a [16,16,16,6] tensor. Channels
/// ch0–ch2 are recomputed from σ's data (per-frame palettes / index cube /
/// candidate genome) and are NEVER edited by curation moves; ch3–ch5 are the
/// user's curation field, derived by folding the decision log
/// (`boardFromLog` in AtlasMove.swift — the replay-determinism law).
struct AtlasBinIdx: Codable, Hashable, Sendable {
    /// L bin, 0..15 (L over [0,1]).
    var l: Int
    /// a bin, 0..15 (a over [-0.5, 0.5]).
    var a: Int
    /// b bin, 0..15 (b over [-0.5, 0.5]).
    var b: Int

    /// Bins per axis — the spec-pinned 16 (`SixFourShape.coverageBinsPerAxis`).
    static var perAxis: Int { SixFourShape.coverageBinsPerAxis }

    /// Row-major flat index `(l·16 + a)·16 + b` ∈ [0, 4096) — the same layout
    /// `DeterministicRenderer`'s coverage diagnostic uses (`bL·256 + bA·16 + bB`).
    var flat: Int { (l * Self.perAxis + a) * Self.perAxis + b }

    /// Whether all three coordinates are on the 16³ grid (total-move guard:
    /// out-of-range moves are identity, per the planned `applyCuration` law).
    var inRange: Bool {
        let n = Self.perAxis
        return l >= 0 && l < n && a >= 0 && a < n && b >= 0 && b < n
    }

    /// `Coverage.okLabBin` in exact Q16 integer arithmetic — bit-identical to the
    /// render path's coverage binning (`DeterministicRenderer.renderGlobalPalette`):
    /// `L` over [0,1] → `(L·16) >> 16`; `a`,`b` over [-0.5,0.5] → `((v+32768)·16) >> 16`;
    /// clamped. Arithmetic shift IS floor division by 2¹⁶, matching the spec's `floor`.
    static func bin(ofQ16 c: SIMD3<Int32>) -> AtlasBinIdx {
        let n = perAxis
        @inline(__always) func clamp(_ i: Int) -> Int { min(n - 1, max(0, i)) }
        return AtlasBinIdx(
            l: clamp((Int(c.x) * n) >> 16),
            a: clamp(((Int(c.y) + 32768) * n) >> 16),
            b: clamp(((Int(c.z) + 32768) * n) >> 16)
        )
    }

    /// The bin's centre colour in OKLab Q16 — the colour a `PinAnchor` move pins
    /// when the user taps a bin (exact integers: `(2i+1)·65536 / 32`, truncating).
    var centerQ16: SIMD3<Int32> {
        let n = Self.perAxis   // 16; one cell spans 65536/16 = 4096 Q16 units
        let lC = Int32((2 * l + 1) * 65536 / (2 * n))
        let aC = Int32((2 * a + 1) * 65536 / (2 * n)) - 32768
        let bC = Int32((2 * b + 1) * 65536 / (2 * n)) - 32768
        return SIMD3<Int32>(lC, aC, bC)
    }
}

/// The [16,16,16,6] board tensor, stored as six flat 4096-float planes
/// (row-major `(l·16 + a)·16 + b`, matching `AtlasBinIdx.flat`).
struct AtlasBoard16: Sendable, Equatable {
    /// Total bins: 16³ = 4096.
    static var binCount: Int { let n = AtlasBinIdx.perAxis; return n * n * n }

    // Base channels — recomputed from σ, never edited by moves (lawBaseChannelsUntouched).
    /// ch0 — bin occupancy of the 64×256 per-frame palette slots, count/16384.
    var binMassPalettes: [Float]
    /// ch1 — bin occupancy of the 64³ pixels through their per-frame palettes, count/262144.
    var binMassPixels: [Float]
    /// ch2 — current candidate's 256 leaves per bin, count/256.
    var globalCoverage: [Float]

    // Curation channels — edited ONLY by folding the decision log.
    /// ch3 — signed weight field (Q8.8 deltas accumulated, stored as float).
    var weightField: [Float]
    /// ch4 — kill mask {0,1} (ToggleBin is involutive).
    var killMask: [Float]
    /// ch5 — anchor mask {0,1} (PinAnchor is idempotent).
    var anchorMask: [Float]

    /// The pinned anchor colours (flat bin → OKLab Q16) — the tensor table's
    /// `anchorColors` companion of ch5 (the palette MUST contain these verbatim).
    var anchorColors: [Int: SIMD3<Int32>]

    /// The all-zero board (`lawTotalOnEmpty`).
    static let empty = AtlasBoard16(
        binMassPalettes: [Float](repeating: 0, count: binCount),
        binMassPixels: [Float](repeating: 0, count: binCount),
        globalCoverage: [Float](repeating: 0, count: binCount),
        weightField: [Float](repeating: 0, count: binCount),
        killMask: [Float](repeating: 0, count: binCount),
        anchorMask: [Float](repeating: 0, count: binCount),
        anchorColors: [:]
    )

    /// Build the base channels (ch0–ch2) from σ's data; curation channels start
    /// at zero and are folded on by `boardFromLog`. All binning goes through the
    /// ONE `AtlasBinIdx.bin(ofQ16:)` rule.
    ///
    /// - `perFramePalettesQ16`: the 64 × 256 per-frame palette centroids (Q16 OKLab).
    /// - `indexCube`: the flat 64³ index cube (row-major t,y,x) into those palettes.
    /// - `candidateLeavesQ16`: the current candidate global palette's 256 leaves.
    static func base(
        perFramePalettesQ16: [[SIMD3<Int32>]],
        indexCube: [UInt8],
        candidateLeavesQ16: [SIMD3<Int32>]
    ) -> AtlasBoard16 {
        var board = AtlasBoard16.empty

        // All three base channels are the DETERMINISTIC Q16 mass (owned Zig
        // `s4_board_mass_q16` / `s4_board_counts_to_mass_q16`, port of
        // `SixFour.Spec.BoardQ16`): integer floor-div binning + integer counts +
        // ONE round-half-up of count·2¹⁶/total. We store `massQ16 / 65536` — an
        // EXACT dyadic conversion (1/65536 = 2⁻¹⁶), so the policy/value board input
        // is now cross-device bit-identical (debt `board-q16-unported`). This
        // replaces the old non-dyadic `1/total` float normalise that leaked into
        // the first matmul's argmax.
        let q16ToUnit: Float = 1.0 / 65536.0

        // ch0 — palette-slot mass (the 64×256 slots).
        var paletteColors = [SIMD3<Int32>]()
        for frame in perFramePalettesQ16 { paletteColors.append(contentsOf: frame) }
        if let mass = SixFourNative.boardMassQ16(colorsQ16: paletteColors) {
            for i in 0 ..< Self.binCount { board.binMassPalettes[i] = Float(mass[i]) * q16ToUnit }
        }

        // ch1 — pixel mass: every voxel's colour through its frame's palette. Counts
        // are built by an integer slot→bin table (already order-independent); the Q16
        // normalise is the owned kernel.
        if !perFramePalettesQ16.isEmpty, !indexCube.isEmpty {
            let perFrame = indexCube.count / perFramePalettesQ16.count
            if perFrame > 0 {
                var counts = [Int32](repeating: 0, count: Self.binCount)
                for (t, palette) in perFramePalettesQ16.enumerated() {
                    let binOfSlot = palette.map { AtlasBinIdx.bin(ofQ16: $0).flat }
                    let lo = t * perFrame
                    let hi = min(indexCube.count, lo + perFrame)
                    guard lo < hi else { break }
                    for i in lo ..< hi {
                        let slot = Int(indexCube[i])
                        if slot < binOfSlot.count { counts[binOfSlot[slot]] += 1 }
                    }
                }
                if let mass = SixFourNative.boardMassQ16(counts: counts, total: indexCube.count) {
                    for i in 0 ..< Self.binCount { board.binMassPixels[i] = Float(mass[i]) * q16ToUnit }
                }
            }
        }

        // ch2 — candidate-leaf coverage.
        if !candidateLeavesQ16.isEmpty,
           let mass = SixFourNative.boardMassQ16(colorsQ16: candidateLeavesQ16) {
            for i in 0 ..< Self.binCount { board.globalCoverage[i] = Float(mass[i]) * q16ToUnit }
        }

        return board
    }
}
