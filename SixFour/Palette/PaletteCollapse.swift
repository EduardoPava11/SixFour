import simd

/// A Q16 OKLab triple (scale 2^16) — the integer substrate shared with the
/// Haskell spec (`SixFour.Spec.Collapse` / `ColorFixed`) and the Zig core.
/// Integer math is identical on every device, so the collapse below reproduces
/// the spec's golden bit-for-bit (a float maximin over near-tied points would not).
typealias OKLabQ16 = SIMD3<Int32>

/// The look-NN I/O slot: collapse the 64 per-frame palettes into ONE global
/// palette (GIFA → GIFB). The trained `LookNetCollapse` will conform to this exact
/// signature; today the deterministic `FarthestPointCollapse` fills it. This is a
/// real interface with a real implementation — not a placeholder.
protocol PaletteCollapse: Sendable {
    /// `perFramePalettes` = 64 × K Q16 OKLab centroids. Returns `k` global leaves.
    func collapse(perFramePalettes: [[OKLabQ16]], k: Int) -> CollapsedPalette
}

/// The collapse output: the `k` global leaves (Q16 OKLab, maximin order) and their
/// indices into the pooled candidate cloud (the golden pins both).
struct CollapsedPalette: Sendable, Equatable {
    let leaves: [OKLabQ16]
    let chosenIndices: [Int]
}

/// Deterministic collapse = the coverage/diversity **maximin** floor: farthest-point
/// selection of `k` representatives over the pooled per-frame palettes, in Q16
/// integers. This is the gamut-coverage floor (it picks actual input colours, so it
/// never invents colour). It mirrors `SixFour.Spec.Collapse.globalCollapseQ16`
/// (which reuses `farthestPointSeedsQ16`) and is gated bit-for-bit against
/// `CollapseGolden` (see `CollapseGoldenTests`). It is NOT the Wasserstein
/// barycenter — that is the *trained* `LookNetCollapse`'s target, which drops into
/// the same `PaletteCollapse` slot.
struct FarthestPointCollapse: PaletteCollapse {
    func collapse(perFramePalettes: [[OKLabQ16]], k: Int) -> CollapsedPalette {
        let pooled = perFramePalettes.flatMap { $0 }
        let idxs = Self.maximinIndices(pooled, k: k)
        return CollapsedPalette(leaves: idxs.map { pooled[$0] }, chosenIndices: idxs)
    }

    /// Squared Q16 OKLab distance, accumulated in i64 (matches
    /// `Spec.QuantFixed.distSqQ16`). Q16 deltas are ≤ ~2^17, so the squared sum
    /// stays well inside i64.
    @inline(__always)
    static func distSqQ16(_ a: OKLabQ16, _ b: OKLabQ16) -> Int64 {
        let dl = Int64(a.x) - Int64(b.x)
        let da = Int64(a.y) - Int64(b.y)
        let db = Int64(a.z) - Int64(b.z)
        return dl * dl + da * da + db * db
    }

    /// The maximin seed-index sequence into `pool`, mirroring
    /// `Spec.QuantFixed.farthestPointSeedIndicesQ16`: first = the colour farthest
    /// from the integer cloud mean; each subsequent pick maximises the minimum
    /// distance to the chosen set. Strict `>` ⇒ lowest index on ties. When `k`
    /// exceeds the distinct-colour count the maximin distance hits 0 and indices
    /// repeat (deterministically), exactly as the spec does.
    static func maximinIndices(_ pool: [OKLabQ16], k: Int) -> [Int] {
        let n = pool.count
        guard k > 0, n > 0 else { return [] }

        // Integer cloud mean (truncating division == Haskell `quot`).
        var sl: Int64 = 0, sa: Int64 = 0, sb: Int64 = 0
        for p in pool { sl += Int64(p.x); sa += Int64(p.y); sb += Int64(p.z) }
        let nn = Int64(n)
        let mean = OKLabQ16(Int32(sl / nn), Int32(sa / nn), Int32(sb / nn))

        // First seed: farthest from the mean (strict `>` ⇒ lowest index).
        var first = 0
        var bestD: Int64 = -1
        for i in 0 ..< n {
            let d = distSqQ16(pool[i], mean)
            if d > bestD { bestD = d; first = i }
        }

        var chosen = [first]
        var minD = [Int64](repeating: 0, count: n)
        let firstC = pool[first]
        for i in 0 ..< n { minD[i] = distSqQ16(pool[i], firstC) }

        while chosen.count < k {
            var nextI = 0
            var pickD: Int64 = -1
            for i in 0 ..< n where minD[i] > pickD { pickD = minD[i]; nextI = i }
            chosen.append(nextI)
            let c = pool[nextI]
            for i in 0 ..< n {
                let d = distSqQ16(pool[i], c)
                if d < minD[i] { minD[i] = d }
            }
        }
        return chosen
    }

    /// Nearest leaf for a colour (squared Q16 distance, strict `<` ⇒ lowest index
    /// on ties — the GIF index-map rule). Mirrors `Spec.QuantFixed.nearestCentroidQ16`.
    static func nearestQ16(_ x: OKLabQ16, _ leaves: [OKLabQ16]) -> Int {
        var best = 0
        var bestD = Int64.max
        for i in 0 ..< leaves.count {
            let d = distSqQ16(x, leaves[i])
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    /// Re-index one frame's colours against the global leaves (the per-frame GIF
    /// index map for the single global colour table). Mirrors
    /// `Spec.Collapse.reindexFrameQ16`.
    static func reindex(frame: [OKLabQ16], leaves: [OKLabQ16]) -> [Int] {
        frame.map { nearestQ16($0, leaves) }
    }
}

extension FarthestPointCollapse {
    /// Display adapter for the Review editor: collapse sRGB8 per-frame palettes
    /// (`CaptureOutput.palettesForDisplay`) to float-OKLab global leaves. Converts
    /// sRGB8 → float OKLab → Q16, runs the byte-exact Q16 collapse, returns leaves
    /// as float OKLab. The Q16 collapse is the source of truth; this only adapts the
    /// display palettes the Review screen happens to carry as sRGB8.
    static func collapseForDisplay(srgb8Frames: [[SIMD3<UInt8>]], k: Int = 256) -> [OKLab] {
        let q16Frames: [[OKLabQ16]] = srgb8Frames.map { frame in
            frame.map { c in
                let lab = ColorScience.srgb8ToOKLab(c.x, c.y, c.z).simd
                return OKLabQ16(
                    Int32((lab.x * 65536).rounded(.toNearestOrEven)),
                    Int32((lab.y * 65536).rounded(.toNearestOrEven)),
                    Int32((lab.z * 65536).rounded(.toNearestOrEven))
                )
            }
        }
        let leaves = FarthestPointCollapse().collapse(perFramePalettes: q16Frames, k: k).leaves
        return leaves.map { OKLab(Float($0.x) / 65536, Float($0.y) / 65536, Float($0.z) / 65536) }
    }
}
