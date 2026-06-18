import Foundation

/// Hand-written Swift port of `SixFour.Spec.GenomePair.sampleOrthogonalPair` — the KEYSTONE that
/// proposes two distinct, σ-valid, EXACTLY-orthogonal candidate displacements `(δ_A, δ_B)` from a
/// capture's base genome.
///
/// Orthogonality is by **disjoint generator-band support**, not Gram–Schmidt: δ_A nudges band S_A,
/// δ_B the disjoint band S_B, so every term of `genomeInner` has a zero factor and the dot product
/// is *exactly* 0 on the Q16 lattice. Pure integer list ops over `SIMD3<Int32>` (the generators are
/// reconstructed once by the caller via `SixFourNative.haarReconstruct`). Mirrors the spec
/// bit-for-bit; gated by `GenomePairGoldenTests` against `Codegen.GenomePair`.
///
/// See `spec/src/SixFour/Spec/GenomePair.hs` (10 laws, CI-proven) and
/// `docs/SIXFOUR-PER-FRAME-GENOME-AB-MIGRATION-WORKFLOW.md` Pillar B.
enum GenomePair {
    typealias Px = SIMD3<Int32>          // Q16 OKLab generator / displacement

    /// Generators each candidate nudges (top `2·pairBudget` ranked split into two disjoint bands).
    static let pairBudget = 8
    /// The cold-start nudge magnitude per OKLab channel, Q16 (≈ 0.0156 OKLab units).
    static let stepQ16: Int32 = 1024
    /// The minimum W-norm a candidate must reach to count as a real choice.
    static let minGenomeStep = 1024.0

    // MARK: - The inner product (uniform unit weights ⇒ positive-definite)

    /// `⟨δ_A, δ_B⟩ = Σ_i (l·l' + a·a' + b·b')`. Shorter displacements are zero-padded. With disjoint
    /// support every term has a zero factor ⇒ exactly `0` (Int64 math, exact for Q16 magnitudes).
    static func genomeInner(_ a: [Px], _ b: [Px]) -> Double {
        let n = max(a.count, b.count)
        var s = 0
        for i in 0..<n {
            let x = i < a.count ? a[i] : Px(0, 0, 0)
            let y = i < b.count ? b[i] : Px(0, 0, 0)
            s += Int(x.x) * Int(y.x) + Int(x.y) * Int(y.y) + Int(x.z) * Int(y.z)
        }
        return Double(s)
    }

    /// `‖δ‖_W = sqrt(⟨δ, δ⟩)`.
    static func genomeNorm(_ d: [Px]) -> Double { genomeInner(d, d).squareRoot() }

    /// The generator indices a displacement touches (nonzero entries).
    static func support(_ d: [Px]) -> [Int] { (0..<d.count).filter { d[$0] != Px(0, 0, 0) } }

    // MARK: - Proposing the pair

    /// The θ-independent cold-start ranking: each generator's Q16 colour energy `l² + a² + b²`.
    static func captureMeasureRanking(_ generators: [Px]) -> [Double] {
        generators.map { g in Double(Int(g.x) * Int(g.x) + Int(g.y) * Int(g.y) + Int(g.z) * Int(g.z)) }
    }

    /// Generator indices sorted by score (descending), ties broken by ascending index — a
    /// deterministic total order. Rankings shorter than `g` are zero-padded.
    static func rankedIndices(_ scores: [Double], _ g: Int) -> [Int] {
        let tagged = (0..<g).map { i in (i, i < scores.count ? scores[i] : 0.0) }
        return tagged.sorted { l, r in l.1 != r.1 ? l.1 > r.1 : l.0 < r.0 }.map { $0.0 }
    }

    /// Split the top `2·pairBudget` ranked generators into two DISJOINT bands by rank parity
    /// (rank 0,2,4… → S_A; 1,3,5… → S_B). Each index appears in exactly one band.
    static func chooseDisjointBands(_ scores: [Double], _ g: Int) -> (sA: [Int], sB: [Int]) {
        let ranked = Array(rankedIndices(scores, g).prefix(min(2 * pairBudget, g)))
        var sA = [Int](), sB = [Int]()
        for (k, i) in ranked.enumerated() { if k % 2 == 0 { sA.append(i) } else { sB.append(i) } }
        return (sA, sB)
    }

    /// The cold-start nudge for generator `i`: fixed magnitude `stepQ16`, sign following the
    /// generator's own lean (push each channel further from neutral). Out-of-range ⇒ identity.
    static func stepFor(_ generators: [Px], _ i: Int) -> Px {
        guard i >= 0 && i < generators.count else { return Px(0, 0, 0) }
        let g = generators[i]
        func s(_ v: Int32) -> Int32 { v >= 0 ? stepQ16 : -stepQ16 }
        return Px(s(g.x), s(g.y), s(g.z))
    }

    /// Build the override that nudges exactly the generators in `idxs` (and no others).
    static func overrideOn(_ generators: [Px], _ idxs: [Int]) -> [Px] {
        let set = Set(idxs)
        return (0..<generators.count).map { set.contains($0) ? stepFor(generators, $0) : Px(0, 0, 0) }
    }

    /// Propose the competing pair `(δ_A, δ_B)` from the base genome's reconstructed `generators`
    /// and a `ranking`. δ_A nudges band S_A, δ_B the disjoint S_B — orthogonal, valid, distinct by
    /// construction. A ranking shorter than the generator count falls back to the deterministic
    /// `captureMeasureRanking` (the θ-untrained cold-start path).
    static func sampleOrthogonalPair(generators: [Px], ranking: [Double]) -> (a: [Px], b: [Px]) {
        let g = generators.count
        let rank = ranking.count >= g ? ranking : captureMeasureRanking(generators)
        let (sA, sB) = chooseDisjointBands(rank, g)
        return (overrideOn(generators, sA), overrideOn(generators, sB))
    }
}
