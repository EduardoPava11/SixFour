import Foundation
import simd

/// Median-cut spatial partition of a per-frame palette — the navigable structure
/// behind the Review-screen palette-structure visualisation.
///
/// This is the Swift port of `SixFour.Spec.SplitTree` (Haskell source of truth,
/// `cabal test` green). Same algorithm, same **pinned `(coord, index)` tie-break**,
/// so it reproduces the spec's golden vector bit-for-bit:
///
///   four greyscale points (0.1, 0.9, 0.2, 0.8 in L) → leaf order **[0, 2, 3, 1]**,
///   root splits axis **L** at **0.5**.
///
/// The canonical tree is binary (median-cut, one axis per split). The three
/// on-screen structures the user chooses between — `16²`, `4⁴`, `2⁸` — are *views*
/// of the one binary tree, obtained by collapsing `k` binary levels into one
/// `2^k`-ary level (`bᵈ = 256` for all three). Octree (`b = 8`) is excluded by
/// arithmetic: `3 ∤ 8`, so no integer depth gives `8ᵈ = 256`.
///
/// Pure value types — no Metal, no UIKit. (Tier-2: zero third-party deps.)

/// One OKLab axis, in SIMD lane order (L, a, b).
enum SplitAxis: Int, Sendable {
    case L = 0, a = 1, b = 2
    @inline(__always) func coord(_ c: SIMD3<Float>) -> Float { c[rawValue] }
}

/// A palette colour with its original slot index pinned. `index` is the position
/// in `palettesForDisplay[frame]` and the tie-break key that makes `build`
/// deterministic regardless of input order.
struct IndexedColor: Sendable, Hashable {
    let index: Int
    let oklab: SIMD3<Float>
    let srgb: SIMD3<UInt8>
}

/// The branching factor a structure view uses. `16² / 4⁴ / 2⁸`.
enum PaletteBranching: String, CaseIterable, Codable, Sendable {
    case b16, b4, b2

    /// Children per internal node.
    var factor: Int { self == .b16 ? 16 : self == .b4 ? 4 : 2 }
    /// View depth: `factor ^ depth == 256`.
    var depth: Int { self == .b16 ? 2 : self == .b4 ? 4 : 8 }
    /// Binary levels collapsed into one view level (`log2 factor`).
    var collapseK: Int { self == .b16 ? 4 : self == .b4 ? 2 : 1 }

    var label: String { self == .b16 ? "16²" : self == .b4 ? "4⁴" : "2⁸" }
    var blurb: String {
        switch self {
        // Honesty note (docs/SIXFOUR-HIGHDIM-UIUX.md): these are radix
        // factorizations of ONE median-cut tree (16²=4⁴=2⁸=256 leaves), NOT
        // coordinate grids or independent feature axes. Each split cuts the
        // WIDEST of L/a/b (data-dependent), so the exponent = tree depth, not
        // data dimensionality.
        case .b16: "16 groups of 16 — two collapsed binary levels, by in-order tree position (not a coordinate grid; that's the separate grid view)."
        case .b4:  "Four collapsed binary levels — each median-cut split cuts the widest of L/a/b (data-dependent; greyscale splits L,L,L,L), not a fixed axis pairing."
        case .b2:  "Median-cut binary tree — 8 nested half-set splits, one axis per split. The address is 8 bits over the 3-D OKLab space, not 8 features."
        }
    }
}

/// The canonical binary median-cut tree.
indirect enum SplitTree: Sendable {
    case leaf(IndexedColor)
    case branch(axis: SplitAxis, pos: Float, lo: SplitTree, hi: SplitTree)

    /// Median-cut: widest axis, sort by `(coord, index)`, split in equal halves at
    /// the median, recurse. For `2^d` points this is a perfect binary tree.
    static func build(_ ics: [IndexedColor]) -> SplitTree {
        guard ics.count > 1 else {
            return .leaf(ics.first ?? IndexedColor(index: 0, oklab: SIMD3<Float>(0, 0, 0), srgb: SIMD3<UInt8>(0, 0, 0)))
        }
        let ax = widestAxis(ics)
        let sorted = ics.sorted { l, r in
            let cl = ax.coord(l.oklab), cr = ax.coord(r.oklab)
            return cl != cr ? cl < cr : l.index < r.index
        }
        let n = sorted.count
        let lo = Array(sorted[0 ..< n / 2])
        let hi = Array(sorted[n / 2 ..< n])
        let pos = 0.5 * (ax.coord(lo[lo.count - 1].oklab) + ax.coord(hi[0].oklab))
        return .branch(axis: ax, pos: pos, lo: build(lo), hi: build(hi))
    }

    /// Leaves in canonical in-order (`lo` before `hi`). Median-cut clusters
    /// perceptually-near colours adjacently in this order.
    var leaves: [IndexedColor] {
        switch self {
        case .leaf(let ic):            return [ic]
        case .branch(_, _, let lo, let hi): return lo.leaves + hi.leaves
        }
    }

    /// The subtrees rooted at binary depth `k` (clamped at leaves).
    func descendants(at k: Int) -> [SplitTree] {
        if k <= 0 { return [self] }
        switch self {
        case .leaf:                          return [self]
        case .branch(_, _, let lo, let hi):  return lo.descendants(at: k - 1) + hi.descendants(at: k - 1)
        }
    }

    /// Collapse every `k` binary levels into one `2^k`-ary level.
    func collapse(_ k: Int) -> NaryNode {
        switch self {
        case .leaf(let ic): return .leaf(ic)
        case .branch:       return .branch(descendants(at: k).map { $0.collapse(k) })
        }
    }

    /// The branching view: `b` chooses how many levels to collapse.
    func view(_ b: PaletteBranching) -> NaryNode { collapse(b.collapseK) }

    private static func widestAxis(_ ics: [IndexedColor]) -> SplitAxis {
        var lo = ics[0].oklab, hi = ics[0].oklab
        for ic in ics { lo = simd_min(lo, ic.oklab); hi = simd_max(hi, ic.oklab) }
        let e = hi - lo
        if e.x >= e.y && e.x >= e.z { return .L }
        if e.y >= e.z { return .a }
        return .b
    }
}

/// An `n`-ary view of the partition (children count = `factor` at internal nodes).
indirect enum NaryNode: Sendable {
    case leaf(IndexedColor)
    case branch([NaryNode])

    var leaves: [IndexedColor] {
        switch self {
        case .leaf(let ic):   return [ic]
        case .branch(let cs): return cs.flatMap { $0.leaves }
        }
    }
}
