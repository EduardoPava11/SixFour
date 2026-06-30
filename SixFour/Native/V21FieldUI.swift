import Foundation

/// Hand-written Swift port of `SixFour.Spec.V21FieldUI`, the V2.1 UI CELL-COUNT layer.
///
/// This is the integer skeleton the two field widgets ride on, and it is byte-exact to the Haskell
/// spec (all-integer Hamilton, no floating point), golden-gated in `V21FieldUIGoldenTests`. Two ideas,
/// kept apart exactly as the spec keeps them:
///
///   * `budgetCells` distributes a cell budget over a Morton-aligned quadtree (single frame) or octree
///     by region uncertainty (`disagree`), conserving every cell.
///   * `allocateWidgets` forces a set of widgets onto pairwise-DISTINCT counts (the OPPOSITION law):
///     two widgets never take the same number of cells. The visual bleed of a widget MAY overlap a
///     neighbour (that is the render layer, `V21WidgetSurface`), but the COUNTS oppose.
///
/// Pure Swift, zero third-party. Inputs are non-negative (saliencies, totals, counts) and coordinates
/// live in `0..63`, so Swift `/` and `%` agree with Haskell `div`/`mod` (no negative-floor hazard).
enum V21FieldUI {

    // MARK: Grid geometry

    /// A voxel coordinate `(x, y, t)` in the 64×64×64 base lattice.
    typealias Voxel = (x: Int, y: Int, t: Int)

    /// A half-open axis-aligned box `[lo,hi)` per axis. The UI only ever lands on whole base voxels.
    struct Region: Equatable {
        var xLo: Int, xHi: Int
        var yLo: Int, yHi: Int
        var tLo: Int, tHi: Int

        var loCorner: Voxel { (xLo, yLo, tLo) }

        var volume: Int { max(0, xHi - xLo) * max(0, yHi - yLo) * max(0, tHi - tLo) }

        var aligned: Bool {
            0 <= xLo && xLo < xHi && xHi <= 64 &&
            0 <= yLo && yLo < yHi && yHi <= 64 &&
            0 <= tLo && tLo < tHi && tHi <= 64
        }

        func subRegionOf(_ b: Region) -> Bool {
            xLo >= b.xLo && xHi <= b.xHi &&
            yLo >= b.yLo && yHi <= b.yHi &&
            tLo >= b.tLo && tHi <= b.tHi
        }
    }

    /// A leaf of a layout: an aligned sub-region, its Morton key, and the cells it owns.
    struct Plot: Equatable {
        var region: Region
        var morton: Int
        var cells: Int
    }

    /// The Morton (Z-order) key of a voxel: interleave the 6 bits of each coordinate. Mirrors the
    /// spec `mortonKey`; the deterministic tie-break for every apportionment and ranking.
    static func mortonKey(_ v: Voxel) -> Int {
        func spread(_ b: Int) -> Int {
            var r = 0
            for i in 0 ..< 6 { r |= ((b >> i) & 1) << (3 * i) }
            return r
        }
        return spread(v.x) | (spread(v.y) << 1) | (spread(v.t) << 2)
    }

    // MARK: Saliency

    /// The non-mode observation mass of a captured histogram (`total − max count`): `0` on a unanimous
    /// bin, growing with spread. The integer "how uncertain is this bin" the budget chases.
    static func disagree(_ counts: [Int]) -> Int {
        guard let m = counts.max() else { return 0 }
        return counts.reduce(0, +) - m
    }

    // MARK: The cell-budget function

    /// Exact integer Hamilton largest-remainder apportionment: split `total` cells across non-negative
    /// weights, summing to EXACTLY `total`. Floor the ideal counts on integer numerators (no `Double`),
    /// then hand the leftover cells to the largest remainders, ties broken by lowest index.
    static func apportion(_ total: Int, _ ws: [Int]) -> [Int] {
        let n = ws.count
        if n == 0 { return [] }
        if total <= 0 { return Array(repeating: 0, count: n) }
        let s = ws.reduce(0, +)
        if s <= 0 {
            let q = total / n, r = total % n
            return (0 ..< n).map { q + ($0 < r ? 1 : 0) }
        }
        let floors = ws.map { (total * $0) / s }
        let fracs  = ws.map { (total * $0) % s }
        let deficit = total - floors.reduce(0, +)
        let order = (0 ..< n).sorted { a, b in
            fracs[a] != fracs[b] ? fracs[a] > fracs[b] : a < b
        }
        let winners = Set(order.prefix(max(0, deficit)))
        return (0 ..< n).map { floors[$0] + (winners.contains($0) ? 1 : 0) }
    }

    /// Split a region into its (up to 8) aligned octant children, halving each axis whose span > 1.
    static func children(_ r: Region) -> [Region] {
        func splitAxis(_ lo: Int, _ hi: Int) -> [(Int, Int)] {
            if hi - lo <= 1 { return [(lo, hi)] }
            let mid = lo + (hi - lo) / 2
            return [(lo, mid), (mid, hi)]
        }
        var out = [Region]()
        for (tl, th) in splitAxis(r.tLo, r.tHi) {
            for (yl, yh) in splitAxis(r.yLo, r.yHi) {
                for (xl, xh) in splitAxis(r.xLo, r.xHi) {
                    out.append(Region(xLo: xl, xHi: xh, yLo: yl, yHi: yh, tLo: tl, tHi: th))
                }
            }
        }
        return out
    }

    /// THE CELL-BUDGET FUNCTION: distribute `n` cells over a region by recursively splitting it into
    /// Morton-ordered quadtree/octree children and Hamilton-apportioning the budget by each child's
    /// weight, until a child holds a single cell or a single voxel. Every cell lands in exactly one
    /// plot (conservation) and every plot is grid-aligned.
    static func budgetCells(_ w: (Region) -> Int, _ region: Region, _ n: Int) -> [Plot] {
        if n <= 0 { return [] }
        let kids = children(region).sorted { mortonKey($0.loCorner) < mortonKey($1.loCorner) }
        if kids.count <= 1 || n == 1 {
            return [Plot(region: region, morton: mortonKey(region.loCorner), cells: n)]
        }
        let shares = apportion(n, kids.map(w))
        var out = [Plot]()
        for (k, s) in zip(kids, shares) { out.append(contentsOf: budgetCells(w, k, s)) }
        return out
    }

    // MARK: The opposition allocator

    /// Whether `k` widgets admit pairwise-DISTINCT non-negative counts summing to `total`: iff
    /// `total >= k(k-1)/2` (the minimal staircase). Below the floor, equal counts are unavoidable.
    static func oppositionFeasible(_ total: Int, _ k: Int) -> Bool {
        total >= k * (k - 1) / 2
    }

    /// THE OPPOSITION ALLOCATOR: distribute `total` cells across widgets so their counts are pairwise
    /// DISTINCT, in input order. Each widget is `(saliency, mortonKey)`. Rank by
    /// `(saliency desc, morton asc, index)`; reserve the strictly-decreasing staircase `k-1, .., 0`;
    /// split the surplus as an even base plus a rank-monotone `+1`, so the per-rank totals stay
    /// strictly decreasing, hence distinct and conserved. Below `oppositionFeasible`, falls back to
    /// plain `apportion` (counts may tie, by necessity).
    static func allocateWidgets(_ total: Int, _ ws: [(sal: Int, morton: Int)]) -> [Int] {
        let k = ws.count
        if k == 0 { return [] }
        if !oppositionFeasible(total, k) { return apportion(total, ws.map { $0.sal }) }
        let ranked = (0 ..< k).sorted { a, b in
            if ws[a].sal != ws[b].sal { return ws[a].sal > ws[b].sal }
            if ws[a].morton != ws[b].morton { return ws[a].morton < ws[b].morton }
            return a < b
        }
        let floorNeeded = k * (k - 1) / 2
        let base = (total - floorNeeded) / k
        let rem  = (total - floorNeeded) % k
        var out = Array(repeating: 0, count: k)
        for (r, origIdx) in ranked.enumerated() {
            out[origIdx] = base + (k - 1 - r) + (r < rem ? 1 : 0)
        }
        return out
    }
}
