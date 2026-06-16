import Foundation

/// Hand-written Swift port of the RGBT-4D reversible integer lifting and cube ladder.
///
/// Bit-exact mirror of the Haskell spec (`SixFour.Spec.RGBTLift` and
/// `SixFour.Spec.CubeLadder`), verified against the spec's golden vectors in
/// `RGBT4DGoldenTests`. Pure integer math (Q16), zero dependencies — the Tier-2
/// contract. The Metal `simd_shuffle` kernel (the on-device hot path) is an
/// optimisation of THIS reference, not a replacement.
///
/// The one cross-language hazard is division: Haskell's `div` floors toward −∞,
/// while Swift's `/` truncates toward zero. `floorDiv` restores the flooring, so
/// the S-transform is reversible for negative deltas exactly as in the spec.
///
/// Dormant until a consumer is wired and `AppSettings.rgbt4dEnabled` is on; the
/// shipped render path is byte-identical while the flag is false.
enum RGBT4DLift {

    /// Floor division (rounds toward −∞), matching Haskell `div`. Swift's `/`
    /// truncates toward zero, which would break the reversible S-transform on
    /// negative values.
    @inline(__always) static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b, r = a % b
        return (r != 0 && ((r < 0) != (b < 0))) ? q - 1 : q
    }

    @inline(__always) static func floorHalf(_ n: Int) -> Int { floorDiv(n, 2) }

    // MARK: - Scalar S-transform (mirrors PairTreeFixed / RGBTLift)

    /// `(x, y) ↦ (low, high)` with `low = y + ⌊(x−y)/2⌋`, `high = x − y`.
    @inline(__always) static func sLift(_ x: Int, _ y: Int) -> (Int, Int) {
        let d = x - y; return (y + floorHalf(d), d)
    }
    /// Exact inverse of `sLift`.
    @inline(__always) static func sUnlift(_ lo: Int, _ hi: Int) -> (Int, Int) {
        let y = lo - floorHalf(hi); return (y + hi, y)
    }

    // MARK: - 2×2 ↔ RGBT (the (2×2)↔1 bijection)

    /// Lift a 2×2 block `(a,b,c,d)` to its sub-bands `(R,G,B,T) = (LL,LH,HL,HH)`.
    static func liftQuad(_ q: (Int, Int, Int, Int)) -> (Int, Int, Int, Int) {
        let (la, ha) = sLift(q.0, q.1)
        let (lc, hc) = sLift(q.2, q.3)
        let (ll, lh) = sLift(la, lc)
        let (hl, hh) = sLift(ha, hc)
        return (ll, lh, hl, hh)
    }
    /// Exact inverse of `liftQuad`.
    static func unliftQuad(_ r: (Int, Int, Int, Int)) -> (Int, Int, Int, Int) {
        let (la, lc) = sUnlift(r.0, r.1)
        let (ha, hc) = sUnlift(r.2, r.3)
        let (a, b) = sUnlift(la, ha)
        let (c, d) = sUnlift(lc, hc)
        return (a, b, c, d)
    }

    // MARK: - One reversible 2-D-Haar level over a side×side grid (row-major)

    /// `side×side` grid → coarse `(side/2)²` R plane + `(side/2)²` detail triples.
    static func liftLevel(_ side: Int, _ g: [Int]) -> (coarse: [Int], details: [(Int, Int, Int)]) {
        let h = side / 2
        func at(_ x: Int, _ y: Int) -> Int { g[y * side + x] }
        var coarse = [Int](); coarse.reserveCapacity(h * h)
        var details = [(Int, Int, Int)](); details.reserveCapacity(h * h)
        for by in 0..<h {
            for bx in 0..<h {
                let (r, gg, bb, tt) = liftQuad((at(2*bx, 2*by), at(2*bx+1, 2*by),
                                                at(2*bx, 2*by+1), at(2*bx+1, 2*by+1)))
                coarse.append(r); details.append((gg, bb, tt))
            }
        }
        return (coarse, details)
    }

    /// Exact inverse of `liftLevel`: rebuild the `2h×2h` grid.
    static func unliftLevel(_ h: Int, _ coarse: [Int], _ details: [(Int, Int, Int)]) -> [Int] {
        let side = 2 * h
        var quads = [(Int, Int, Int, Int)](); quads.reserveCapacity(coarse.count)
        for i in 0..<coarse.count {
            let (gg, bb, tt) = details[i]
            quads.append(unliftQuad((coarse[i], gg, bb, tt)))
        }
        var out = [Int](repeating: 0, count: side * side)
        for y in 0..<side {
            for x in 0..<side {
                let (a, b, c, d) = quads[(y / 2) * h + (x / 2)]
                out[y * side + x] = (y % 2 == 0) ? (x % 2 == 0 ? a : b) : (x % 2 == 0 ? c : d)
            }
        }
        return out
    }

    // MARK: - The captured ladder (lossless) and synthesis beyond capture

    /// Distil `levels` ×2 steps; returns the coarse plane + detail planes (finest first).
    static func distill(_ levels: Int, _ side: Int, _ g: [Int]) -> (coarse: [Int], details: [[(Int, Int, Int)]]) {
        var cur = g, s = side
        var acc = [[(Int, Int, Int)]]()
        for _ in 0..<levels { let (c, d) = liftLevel(s, cur); cur = c; acc.append(d); s /= 2 }
        return (cur, acc)
    }

    /// Exact inverse of `distill`.
    static func synthesize(_ coarseSide: Int, _ coarse: [Int], _ dets: [[(Int, Int, Int)]]) -> [Int] {
        var cur = coarse, s = coarseSide
        for d in dets.reversed() { cur = unliftLevel(s, cur, d); s *= 2 }
        return cur
    }

    /// Synthesise up `levels` ×2 steps with zeroed detail — the deterministic floor
    /// (nearest-neighbour block replication). The NN super-res replaces this floor
    /// with predicted detail strictly above captured resolution.
    static func synthBeyond(_ coarseSide: Int, _ levels: Int, _ coarse: [Int]) -> [Int] {
        var cur = coarse, s = coarseSide
        for _ in 0..<levels {
            cur = unliftLevel(s, cur, [(Int, Int, Int)](repeating: (0, 0, 0), count: s * s))
            s *= 2
        }
        return cur
    }
}
