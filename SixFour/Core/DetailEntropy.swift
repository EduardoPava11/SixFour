import Foundation

/// Integer-coefficient histogram Shannon entropy over octant detail bands —
/// the "bits = compressible surplus" primitive, hand-written twin of
/// `SixFour.Spec.DetailEntropy` (promoted by the 2026-07-11 link ledger,
/// wave 2). The octant lift is the whitening operator (detail = data −
/// prediction; a flat octant has ZERO detail), so the entropy of the detail
/// coefficients IS the spendable bit budget — this makes adaptive rung deltas
/// a MEASURED saving instead of a dimension count. Twin + laws today; the
/// curate/telemetry consumer is the follow-on.
enum DetailEntropy {

    /// Multiset histogram of integer coefficients.
    static func histogram(_ xs: [Int]) -> [Int: Int] {
        var h = [Int: Int]()
        for x in xs { h[x, default: 0] += 1 }
        return h
    }

    /// Distinct symbols in the multiset.
    static func alphabetSize(_ xs: [Int]) -> Int { histogram(xs).count }

    /// Empirical Shannon entropy in BITS per symbol (0 for the empty multiset).
    static func shannonBits(_ xs: [Int]) -> Double {
        let h = histogram(xs)
        let n = Double(xs.count)
        guard n > 0 else { return 0 }
        return -h.values.reduce(0.0) { acc, c in
            let p = Double(c) / n
            return acc + p * log2(p)
        }
    }

    /// Total coded size of the multiset at its empirical entropy: n · H.
    static func codedBits(_ xs: [Int]) -> Double {
        Double(xs.count) * shannonBits(xs)
    }

    /// One detail band across a set of octant details (each detail = the 7
    /// invented bands of one `s4_octant_lift`, i.e. lift output indices 1…7).
    static func detailColumn(_ j: Int, _ details: [[Int]]) -> [Int] {
        details.map { $0[j] }
    }

    /// The 7 per-band columns — bands stay separate because their statistics
    /// differ (the per-band vs pooled gap is a law, not an implementation
    /// choice: pooling forgets which band a coefficient came from).
    static func detailBands7(_ details: [[Int]]) -> [[Int]] {
        (0..<7).map { detailColumn($0, details) }
    }

    /// The bit budget of a detail set: Σ over bands of that band's coded bits.
    static func detailEntropyBits(_ details: [[Int]]) -> Double {
        detailBands7(details).reduce(0.0) { $0 + codedBits($1) }
    }

    /// All coefficients pooled into one multiset (the comparison the per-band
    /// reading strictly refines).
    static func pooledCoeffs(_ details: [[Int]]) -> [Int] {
        detailBands7(details).flatMap { $0 }
    }
}
