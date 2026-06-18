import Foundation
import simd

/// COLOR ATLAS — the on-device personal taste vector θ (the n=0 personalization
/// core of `docs/SIXFOUR-CANONICAL-PATH.md` §2).
///
/// One 770-D Bradley–Terry utility, folded by `btUpdate` on every A/B pick (a
/// byte-faithful port of `SixFour.Spec.PreferenceUpdate`, golden-gated). θ then
/// drives a **leaf-space taste tint** on the curated palette so the
/// personalization is VISIBLE, and every pick is logged so device testing is
/// observable (there is no camera/sim here — logs are how we test).
///
/// Why a *leaf-space* tint (not the σ-pair `ThetaToDelta`/`s4_leaf_override`):
/// the shipped candidates are the **maximin floor** (256 free leaves), which is
/// NOT a σ-pair genome, so the generator-space tint doesn't apply to it. The
/// embedding IS the leaves, so δ_leaf = clamp(gain·θ_leaf) is the taste-ascent
/// gradient that applies to any flat palette. The σ-pair path activates when
/// candidates become learned genomes (canonical path step 3+).
enum PersonalTaste {

    /// θ dimension (= `Spec.PreferenceUpdate.thetaDim`): 256 leaves × 3 ++ [coverage, beauty].
    static let thetaDim = 770
    /// Learning rate η and L2 decay λ (= the spec defaults).
    static let eta = 0.05
    static let lambda = 1.0e-3
    /// Leaf-tint gain + clamp (Q16). The tint can recolour but never escape far.
    static let tintGain = 4096.0
    static let tintMaxQ16: Int32 = 8192

    static func zeroTheta() -> [Double] { [Double](repeating: 0, count: thetaDim) }

    private static func sigmoid(_ x: Double) -> Double { 1 / (1 + exp(-x)) }

    /// One SGD step on a Compare (port of `Spec.PreferenceUpdate.btUpdate`):
    /// `θᵢ ← θᵢ + η·(1 − σ(θ·d))·dᵢ − η·λ·θᵢ`, `d = w − l`. Golden vs Haskell.
    static func btUpdate(theta: [Double], winner w: [Double], loser l: [Double]) -> [Double] {
        let n = min(theta.count, min(w.count, l.count))
        var d = [Double](repeating: 0, count: n)
        var dot = 0.0
        for i in 0 ..< n { d[i] = w[i] - l[i]; dot += theta[i] * d[i] }
        let g = 1 - sigmoid(dot)
        var out = theta
        for i in 0 ..< n { out[i] = theta[i] + eta * g * d[i] - eta * lambda * theta[i] }
        return out
    }

    /// The 770-D `atlasEmbedding` of a 256-leaf palette: leaves flattened (768,
    /// Q16→Double) ++ [coverage, beauty]. coverage = occupied-16³-bin fraction;
    /// beauty = Ou-Luo pair-beauty loss (`PaletteValue.beautyLossLeaves`). This is
    /// the `btUpdate` input, frozen into the CMPE log record at pick time.
    static func embedding(leaves: [SIMD3<Int32>]) -> [Double] {
        let dbl = leaves.map {
            SIMD3<Double>(Double($0.x) / 65536, Double($0.y) / 65536, Double($0.z) / 65536)
        }
        var e = [Double](); e.reserveCapacity(thetaDim)
        for c in dbl { e.append(c.x); e.append(c.y); e.append(c.z) }
        if e.count < 768 { e += [Double](repeating: 0, count: 768 - e.count) }
        else if e.count > 768 { e = Array(e.prefix(768)) }
        var bins = Set<Int>()
        for c in leaves { bins.insert(AtlasBinIdx.bin(ofQ16: c).flat) }
        let coverage = leaves.isEmpty ? 0 : Double(bins.count) / Double(leaves.count)
        e.append(coverage)
        e.append(PaletteValue.beautyLossLeaves(dbl))
        return e
    }

    /// The leaf-space taste tint: `δ_leafₖ = clamp(round(gain·θ[3k:3k+3]), ±tintMaxQ16)`,
    /// added to leaf k. δ is the gradient of `θ·leaves` w.r.t. the leaves — moving
    /// the palette toward the user's learned taste. Round-half-to-even (matches the
    /// spec rounding). Identity at θ = 0.
    static func leafTint(_ leaves: [SIMD3<Int32>], theta: [Double], gain: Double = tintGain) -> [SIMD3<Int32>] {
        let lo = Double(-tintMaxQ16), hi = Double(tintMaxQ16)
        func q(_ x: Double) -> Int32 { Int32(min(hi, max(lo, (gain * x).rounded(.toNearestOrEven)))) }
        return leaves.enumerated().map { k, c in
            let base = 3 * k
            guard base + 2 < theta.count else { return c }
            return SIMD3<Int32>(c.x &+ q(theta[base]), c.y &+ q(theta[base + 1]), c.z &+ q(theta[base + 2]))
        }
    }
}

/// Persists the ONE per-device taste vector θ (JSON in Application Support — like
/// the decision log; data never leaves the device). A missing/corrupt file yields
/// the zero θ (a fresh taste), never blocking curation.
enum PersonalTasteStore {
    private static let fileName = "sixfour-personal-taste-v1.json"

    static func url() -> URL? {
        guard let dir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    static func load() -> [Double] {
        guard let url = url(), let data = try? Data(contentsOf: url),
              let theta = try? JSONDecoder().decode([Double].self, from: data),
              theta.count == PersonalTaste.thetaDim else {
            return PersonalTaste.zeroTheta()
        }
        return theta
    }

    static func save(_ theta: [Double]) {
        guard let url = url(), let data = try? JSONEncoder().encode(theta) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
