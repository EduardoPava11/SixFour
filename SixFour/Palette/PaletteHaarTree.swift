import simd

/// A palette as a Haar pyramid — the hand-written Swift port of
/// `SixFour.Spec.PairTree`. The global palette is not "256 colours" but a perfect
/// binary tree of balanced mirror pairs (`child = parent ± δ`); `root` is the DC
/// mean and `levels[i]` holds the `2^i` detail offsets at level `i`. This is the
/// multiresolution space the search's reversible `Move`s perturb: one step in LAB
/// space = a delta on one coefficient.
///
/// Carried as `SIMD3<Double>` (not the Float `OKLab`) to match the spec's precision
/// and keep the round-trip tolerance tight. Gated against `PairTreeGolden`
/// (`PairTreeGoldenTests`) — float Haar can't be bit-exact across languages, so the
/// gate is within tolerance.
struct HaarPalette: Equatable {
    /// The DC / mean colour.
    let root: SIMD3<Double>
    /// Offsets top-down; `levels[i]` has `2^i` entries.
    let levels: [[SIMD3<Double>]]
}

enum PaletteHaarTree {
    /// Free reals for the production palette: `3 · 2^8 = 768` (root + 255 offsets).
    static let degreesOfFreedom = 3 * 256

    /// Inverse Haar: expand the tree into its `2^D` leaves (the palette), in a fixed
    /// order. At each level a node `n` with offset `d` yields `[n+d, n-d]`. Mirrors
    /// `SixFour.Spec.PairTree.reconstruct`.
    static func reconstruct(_ hp: HaarPalette) -> [SIMD3<Double>] {
        var nodes = [hp.root]
        for offs in hp.levels {
            var next: [SIMD3<Double>] = []
            next.reserveCapacity(nodes.count * 2)
            for (n, d) in zip(nodes, offs) {
                next.append(n + d)
                next.append(n - d)
            }
            nodes = next
        }
        return nodes
    }

    /// Forward Haar: collapse a palette of `2^D` leaves into its tree. Adjacent
    /// leaves `(x, y)` give parent `(x+y)/2` and offset `(x−y)/2`; recurse to the
    /// root, accumulating offset levels coarsest-first (`levels[0]` = 1 offset).
    /// Inverse of `reconstruct`. Mirrors `SixFour.Spec.PairTree.analyze` (including
    /// its convention of dropping a trailing unpaired leaf on non-power-of-two input).
    static func analyze(_ leaves: [SIMD3<Double>]) -> HaarPalette {
        var cur = leaves
        var acc: [[SIMD3<Double>]] = []
        while cur.count > 1 {
            var parents: [SIMD3<Double>] = []
            var offsets: [SIMD3<Double>] = []
            parents.reserveCapacity(cur.count / 2)
            offsets.reserveCapacity(cur.count / 2)
            var i = 0
            while i + 1 < cur.count {
                let x = cur[i], y = cur[i + 1]
                parents.append((x + y) * 0.5)
                offsets.append((x - y) * 0.5)
                i += 2
            }
            acc.insert(offsets, at: 0)   // prepend ⇒ coarsest level ends up first
            cur = parents
        }
        return HaarPalette(root: cur.first ?? SIMD3<Double>(repeating: 0), levels: acc)
    }
}
