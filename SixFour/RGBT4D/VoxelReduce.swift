import Foundation

/// Hand-written Swift port of `SixFour.Spec.VoxelReduce` — the joint spatio-temporal
/// `(2×2)×(2×2)→1` reversible reduction `64³ ↔ 16³`.
///
/// Owns NO lift math. The spatial half reuses `RGBT4DLift.distill` / `synthesize` (per OKLab
/// channel, per frame); the temporal half reuses `RGBT4DLift.sLift` / `sUnlift` (per reduced
/// spatial position). It is a pure *composition*, mirroring the Haskell spec, gated byte-exact by
/// `VoxelReduceGoldenTests` (substrate vs `Codegen.VoxelReduce`, plus round-trip).
///
/// Two of these run as independent searches become the orthogonal A and B candidates; this type is
/// the lossless `64³→16³` substrate they both stand on. See
/// `docs/SIXFOUR-PER-FRAME-GENOME-AB-MIGRATION-WORKFLOW.md` §A / §5 Phase 1b.
enum VoxelReduce {
    typealias Px = (Int, Int, Int)        // OKLabI (Q16 l, a, b)
    typealias Detail = [(Int, Int, Int)]  // one CubeLadder detail plane (G,B,T triples)

    /// Per-frame spatial detail: one CubeLadder detail-plane stack per OKLab channel.
    struct SpatialDetail { var l: [Detail]; var a: [Detail]; var b: [Detail] }

    /// The reduced cube: the coarse `16³` substrate plus all detail needed to invert exactly.
    struct Reduced {
        var substrate: [[Px]]          // frames' × side'²  — the lossless 16³ tier
        var spatialDetail: [SpatialDetail]  // one per ORIGINAL frame
        var temporalDetail: [[[Px]]]   // one per reduced spatial position: the temporal high bands
    }

    static func reducedSide(_ levels: Int, _ side: Int) -> Int { side / (1 << levels) }
    static func reducedFrames(_ levels: Int, _ frames: Int) -> Int { frames / (1 << levels) }

    // MARK: - Temporal half (per position) — reuses RGBT4DLift.sLift / sUnlift

    /// One level of the temporal integer Haar split (mirrors `TemporalLoop.haarSplitTime`):
    /// adjacent frames pair into a lifted parent (low) + detail (high); odd tail carried into low.
    static func tSplit(_ xs: [Px]) -> (low: [Px], high: [Px]) {
        var low = [Px](), high = [Px]()
        var i = 0
        while i + 1 < xs.count {
            let (l0, h0) = RGBT4DLift.sLift(xs[i].0, xs[i + 1].0)
            let (l1, h1) = RGBT4DLift.sLift(xs[i].1, xs[i + 1].1)
            let (l2, h2) = RGBT4DLift.sLift(xs[i].2, xs[i + 1].2)
            low.append((l0, l1, l2)); high.append((h0, h1, h2))
            i += 2
        }
        if i < xs.count { low.append(xs[i]) }   // carried odd tail (no detail)
        return (low, high)
    }

    /// Exact inverse of one `tSplit` level (mirrors `TemporalLoop.haarJoinTime`).
    static func tJoin(_ highs: [Px], _ low: [Px]) -> [Px] {
        var out = [Px]()
        for i in 0..<highs.count {
            let (x0, y0) = RGBT4DLift.sUnlift(low[i].0, highs[i].0)
            let (x1, y1) = RGBT4DLift.sUnlift(low[i].1, highs[i].1)
            let (x2, y2) = RGBT4DLift.sUnlift(low[i].2, highs[i].2)
            out.append((x0, x1, x2)); out.append((y0, y1, y2))
        }
        if low.count > highs.count { out.append(low[highs.count]) }  // carried odd tail
        return out
    }

    /// `levels` temporal splits on the low band (highs returned finest-first).
    static func tDistill(_ levels: Int, _ xs: [Px]) -> (low: [Px], highs: [[Px]]) {
        var cur = xs, highs = [[Px]]()
        for _ in 0..<levels { let (l, h) = tSplit(cur); cur = l; highs.append(h) }
        return (cur, highs)
    }

    /// Exact inverse of `tDistill` (joins coarsest-first).
    static func tExpand(_ low: [Px], _ highs: [[Px]]) -> [Px] {
        var cur = low
        for h in highs.reversed() { cur = tJoin(h, cur) }
        return cur
    }

    // MARK: - Spatial half (per frame, per channel) — reuses RGBT4DLift.distill / synthesize

    private static func distillFrame(_ levels: Int, _ side: Int, _ frame: [Px]) -> ([Px], SpatialDetail) {
        let (lc, ld) = RGBT4DLift.distill(levels, side, frame.map { $0.0 })
        let (ac, ad) = RGBT4DLift.distill(levels, side, frame.map { $0.1 })
        let (bc, bd) = RGBT4DLift.distill(levels, side, frame.map { $0.2 })
        let coarse = (0..<lc.count).map { (lc[$0], ac[$0], bc[$0]) }
        return (coarse, SpatialDetail(l: ld, a: ad, b: bd))
    }

    private static func synthFrame(_ coarseSide: Int, _ coarse: [Px], _ d: SpatialDetail) -> [Px] {
        let ls = RGBT4DLift.synthesize(coarseSide, coarse.map { $0.0 }, d.l)
        let aS = RGBT4DLift.synthesize(coarseSide, coarse.map { $0.1 }, d.a)
        let bs = RGBT4DLift.synthesize(coarseSide, coarse.map { $0.2 }, d.b)
        return (0..<ls.count).map { (ls[$0], aS[$0], bs[$0]) }
    }

    // MARK: - The composed operator

    /// The reversible `64³ → 16³` reduction: spatially distil every frame, then temporally distil
    /// every reduced spatial position. All detail is carried so `expand` inverts exactly.
    static func reduce(_ levels: Int, _ side: Int, _ cube: [[Px]]) -> Reduced {
        var coarseFrames = [[Px]](), sdet = [SpatialDetail]()
        for frame in cube { let (c, d) = distillFrame(levels, side, frame); coarseFrames.append(c); sdet.append(d) }

        let nPos = coarseFrames.first?.count ?? 0
        var lowCols = [[Px]](), tdet = [[[Px]]]()
        for p in 0..<nPos {
            let col = coarseFrames.map { $0[p] }      // transpose: [position][frame]
            let (low, highs) = tDistill(levels, col)
            lowCols.append(low); tdet.append(highs)
        }

        let framesP = lowCols.first?.count ?? 0
        var substrate = [[Px]]()                       // transpose: [frame'][position]
        for f in 0..<framesP { substrate.append(lowCols.map { $0[f] }) }
        return Reduced(substrate: substrate, spatialDetail: sdet, temporalDetail: tdet)
    }

    /// Exact inverse of `reduce`: temporally rejoin every position, then spatially synthesise
    /// every frame. `expand(levels, side, reduce(levels, side, cube)) == cube`.
    static func expand(_ levels: Int, _ side: Int, _ r: Reduced) -> [[Px]] {
        let framesP = r.substrate.count
        let nPos = r.substrate.first?.count ?? 0

        var lowCols = [[Px]]()                          // transpose: [position][frame']
        for p in 0..<nPos { lowCols.append((0..<framesP).map { r.substrate[$0][p] }) }

        var cols = [[Px]]()                             // temporal expand each position → [frame]
        for p in 0..<nPos { cols.append(tExpand(lowCols[p], r.temporalDetail[p])) }

        let nFrames = cols.first?.count ?? 0
        var coarseFrames = [[Px]]()                     // transpose: [frame][position] @ side'
        for f in 0..<nFrames { coarseFrames.append((0..<nPos).map { cols[$0][f] }) }

        let cs = reducedSide(levels, side)
        var cube = [[Px]]()
        for f in 0..<nFrames { cube.append(synthFrame(cs, coarseFrames[f], r.spatialDetail[f])) }
        return cube
    }
}
