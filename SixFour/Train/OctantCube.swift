import Foundation

/// Hand-written Swift port of the OCTANT cube rung (`OctreeCell.liftOct` /
/// `unliftOct` — 2×2×2 ↔ 1 coarse + 7 detail) plus the V3.0 INVENTED expansion:
/// the 16³ proposal up-rung'd to 64³ with the somatic θ_up predicting detail
/// (`DetailPredictor.predictDetail`) or the zero-detail deterministic floor.
///
/// Owns no scalar math: the S-transform is `RGBT4DLift.sLift`/`sUnlift` (the
/// same floor-division convention as the spec, Zig, and the Metal twins). Lane
/// order is the capture convention throughout: (t, row, col), col fastest —
/// near-t face first, so the octant z axis IS the time axis. Gated in
/// `OctantCubeTests` against the Zig oracle (`s4_octant_lift` round-trip) and
/// the nearest-neighbour floor identity.
///
/// This is the DECIDE preview's engine: `expand` is exactly what the shipped
/// build will do at these two rungs, so what the user sees IS the floor / the
/// gene's invention — never a faked image.
enum OctantCube {

    /// 2×2×2 (lanes (dt,dr,dc), col fastest) → [coarse, g0,b0,t0, g1,b1,t1, dz].
    static func lift(_ b: [Int]) -> [Int] {
        let (r0, g0, b0, t0) = liftQuad(b[0], b[1], b[2], b[3])   // near-t face
        let (r1, g1, b1, t1) = liftQuad(b[4], b[5], b[6], b[7])   // far-t face
        let (rr, dz) = RGBT4DLift.sLift(r0, r1)                    // Haar along t
        return [rr, g0, b0, t0, g1, b1, t1, dz]
    }

    /// Exact inverse: (coarse, 7 detail bands) → the 8 fine lanes.
    static func unlift(coarse: Int, detail: [Int]) -> [Int] {
        let (r0, r1) = RGBT4DLift.sUnlift(coarse, detail[6])
        let (a, b, c, d) = unliftQuad(r0, detail[0], detail[1], detail[2])
        let (e, f, g, h) = unliftQuad(r1, detail[3], detail[4], detail[5])
        return [a, b, c, d, e, f, g, h]
    }

    private static func liftQuad(_ a: Int, _ b: Int, _ c: Int, _ d: Int)
        -> (Int, Int, Int, Int) {
        let (la, ha) = RGBT4DLift.sLift(a, b)
        let (lc, hc) = RGBT4DLift.sLift(c, d)
        let (ll, lh) = RGBT4DLift.sLift(la, lc)
        let (hl, hh) = RGBT4DLift.sLift(ha, hc)
        return (ll, lh, hl, hh)
    }

    private static func unliftQuad(_ r: Int, _ g: Int, _ bb: Int, _ t: Int)
        -> (Int, Int, Int, Int) {
        let (la, lc) = RGBT4DLift.sUnlift(r, g)
        let (ha, hc) = RGBT4DLift.sUnlift(bb, t)
        let (a, b) = RGBT4DLift.sUnlift(la, ha)
        let (c, d) = RGBT4DLift.sUnlift(lc, hc)
        return (a, b, c, d)
    }

    // MARK: - The invented up-rung (one scalar cube, one octant level: side → 2·side)

    /// One up-rung of a scalar cube (flat (t·side + row)·side + col): every voxel
    /// becomes a 2×2×2 block. `theta` nil (or the zero gene) yields the
    /// deterministic zero-detail floor = nearest-neighbour; a trained θ_up
    /// invents the seven bands from the coarse value (`predictCommitted` — the
    /// same committed integers the trainer gated).
    static func upRung(_ vol: [Int], side: Int, theta: [Double]?) -> [Int] {
        let s2 = side * 2
        var out = [Int](repeating: 0, count: s2 * s2 * s2)
        let zero = [Int](repeating: 0, count: 7)
        for t in 0 ..< side {
            for r in 0 ..< side {
                for c in 0 ..< side {
                    let v = vol[(t * side + r) * side + c]
                    let detail = theta.map { DeviceTrainStepCPU.predictCommitted(theta: $0, coarse: v) } ?? zero
                    let block = unlift(coarse: v, detail: detail)
                    var lane = 0
                    for dt in 0 ... 1 {
                        for dr in 0 ... 1 {
                            for dc in 0 ... 1 {
                                out[((2 * t + dt) * s2 + (2 * r + dr)) * s2 + (2 * c + dc)] = block[lane]
                                lane += 1
                            }
                        }
                    }
                }
            }
        }
        return out
    }

    /// THE DECIDE PREVIEW BUILD: the 16³ proposal (`Surface.coarseSubstrate`,
    /// 16 frames × 16² OKLab Q16) expanded two octant rungs to 64³, per channel.
    /// The gene invents on its trained channel only (L today); the other
    /// channels ride the deterministic floor. Returns the interleaved
    /// `((t·64 + row)·64 + col)·3 + ch` Q16 volume, or nil for a malformed
    /// substrate. `theta` nil == the pure floor (zero-gene == floor).
    static func expandProposal(substrate: [[VoxelReduce.Px]],
                               theta: [Double]?, geneChannel: Int = 0) -> [Int32]? {
        let side = 16
        guard substrate.count == side,
              substrate.allSatisfy({ $0.count == side * side }) else { return nil }
        var out = [Int32](repeating: 0, count: 64 * 64 * 64 * 3)
        for ch in 0 ..< 3 {
            var vol = [Int](repeating: 0, count: side * side * side)
            for t in 0 ..< side {
                for p in 0 ..< side * side {
                    let px = substrate[t][p]
                    vol[t * side * side + p] = ch == 0 ? px.0 : (ch == 1 ? px.1 : px.2)
                }
            }
            let th = ch == geneChannel ? theta : nil
            let v64 = upRung(upRung(vol, side: side, theta: th), side: side * 2, theta: th)
            for i in 0 ..< v64.count {
                out[i * 3 + ch] = Int32(v64[i])
            }
        }
        return out
    }
}
