import Foundation
import simd

/// Live analysis of the camera preview — the capture screen's instrument.
///
/// Each ~10 fps preview frame arrives as a full 64×64 `OKLabTile` (4096 OKLab
/// pixels). We answer one question cheaply (~0.1 ms, one O(4096) pass): **how
/// much distinct colour is the camera seeing right now**, and **what is the
/// dominant hue**. That drives the live diversity gauge + chrome tint, teaching
/// the user to frame colour-rich scenes that fill the significant 256-palette.
///
/// "Diversity" is the *same* metric the renderer optimizes: distinct occupied
/// bins of the 16³ OKLab grid (`SixFour.Spec.Coverage`). The binning here is a
/// bit-for-bit mirror of `ClusterStatisticsOps.gamutCoverage`'s `binL`/`binAB`,
/// so the live viewfinder and the offline metric agree.
struct SceneReadout: Sendable, Equatable {
    /// Distinct occupied 16³ OKLab bins in the current frame.
    let occupiedBins: Int
    /// Normalised gauge ∈ [0,1]: `min(1, occupiedBins / K)` — "enough distinct
    /// colour for a full 256-palette?" Full ring ⇔ the scene already carries
    /// ≥ K distinct colour-bins.
    let gauge: Float
    /// Dominant scene colour (most-populated bin's mean), sRGB.
    let tint: SIMD3<UInt8>
    /// Top-N populated bin colours (sRGB), most-populated first — the live
    /// scene palette (reserved for a future accent strip).
    let accents: [SIMD3<UInt8>]

    static let empty = SceneReadout(
        occupiedBins: 0, gauge: 0, tint: SIMD3<UInt8>(255, 255, 255), accents: []
    )
}

enum LivePreviewAnalysis {

    /// Analyse one preview tile. Pure + `nonisolated` so it runs on the Metal
    /// completion queue (where the preview callback fires) without touching the
    /// main actor.
    ///
    /// - `binsPerAxis`: 16³ grid, spec-pinned via `SixFourShape.coverageBinsPerAxis`.
    /// - `target`: gauge denominator. `SixFourShape.K` (256) ties "full gauge"
    ///   to "enough colour for a complete significant palette".
    /// - `accentCount`: how many dominant bin colours to surface.
    static func analyze(
        _ tile: OKLabTile,
        binsPerAxis: Int = SixFourShape.coverageBinsPerAxis,
        target: Int = SixFourShape.K,
        accentCount: Int = 6
    ) -> SceneReadout {
        let pixels = tile.pixels
        guard !pixels.isEmpty else { return .empty }

        let n = binsPerAxis
        let nf = Float(n)
        // Bit-mirror of ClusterStatisticsOps.gamutCoverage binning.
        @inline(__always) func binL(_ v: Float) -> Int { min(max(0, Int(v * nf)), n - 1) }
        @inline(__always) func binAB(_ v: Float) -> Int { min(max(0, Int((v + 0.5) * nf)), n - 1) }

        // Per-bin population + OKLab colour sum, for occupancy + dominant hue.
        var counts: [Int: Int] = [:]
        var sums: [Int: SIMD3<Float>] = [:]
        counts.reserveCapacity(512)
        sums.reserveCapacity(512)
        for p in pixels {
            let key = (binL(p.x) * n + binAB(p.y)) * n + binAB(p.z)
            counts[key, default: 0] += 1
            sums[key, default: .zero] += p
        }

        let occupied = counts.count
        let gauge = min(1, Float(occupied) / Float(max(1, target)))

        // Rank bins by population; map each to its mean OKLab → sRGB.
        let ranked = counts.sorted { $0.value > $1.value }
        @inline(__always) func srgb(_ key: Int) -> SIMD3<UInt8> {
            let c = sums[key]! / Float(counts[key]!)
            return ColorScience.okLabToSRGB8(OKLab(c))
        }
        let tint = ranked.first.map { srgb($0.key) } ?? SIMD3<UInt8>(255, 255, 255)
        let accents = ranked.prefix(accentCount).map { srgb($0.key) }

        return SceneReadout(occupiedBins: occupied, gauge: gauge, tint: tint, accents: accents)
    }
}
