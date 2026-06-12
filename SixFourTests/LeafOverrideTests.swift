import Testing
import simd
@testable import SixFour

/// Byte-exact gate for the 2⁸ generator-space δ override (`BranchedPalette.projectQ16(_,
/// branching: .b2, override:)`), the Swift twin of `Spec.LeafOverride.applySigmaOverride`.
/// Mirrors every Haskell law, EXACT integer equality — no tolerance.
///
/// Key identity used throughout: the σ-pair genome interleaves `[c₀, σc₀, c₁, σc₁, …]`,
/// so `base[2i]` IS generator `cᵢ`. Hence "override adds to generators" is testable as
/// `overridden[2i] == base[2i] + δᵢ` without reaching into the native Haar.
struct LeafOverrideTests {

    /// A deterministic, in-range 256-leaf Q16 OKLab palette.
    private func palette() -> [SIMD3<Int32>] {
        (0 ..< 256).map { i in
            let l = Int32(i * 200)
            let a = Int32((i % 32) * 100 - 1600)
            let b = Int32((i % 16) * 120 - 960)
            return SIMD3<Int32>(l, a, b)
        }
    }

    private func sigma(_ c: SIMD3<Int32>) -> SIMD3<Int32> {
        SIMD3<Int32>(c.x, 0 &- c.y, 0 &- c.z)
    }

    private func base() -> [SIMD3<Int32>] {
        BranchedPalette.projectQ16(palette(), branching: .b2)
    }

    // MARK: identity (no-op)

    @Test func emptyAndZeroOverrideAreByteIdenticalNoOp() {
        let b = base()
        #expect(BranchedPalette.projectQ16(palette(), branching: .b2, override: []) == b)
        let zeros = [SIMD3<Int32>](repeating: .zero, count: 128)
        #expect(BranchedPalette.projectQ16(palette(), branching: .b2, override: zeros) == b)
        // A shorter all-zero override is still a no-op (zero-padded).
        let shortZeros = [SIMD3<Int32>](repeating: .zero, count: 40)
        #expect(BranchedPalette.projectQ16(palette(), branching: .b2, override: shortZeros) == b)
    }

    // MARK: σ-symmetry is unbreakable

    @Test func anyOverrideKeepsEveryPairSigmaMirrored() {
        let p = palette()
        // A dense, varied, deterministic override across all 128 generators.
        let dense: [SIMD3<Int32>] = (0 ..< 128).map { i in
            let l = Int32((i * 37) % 4000 - 2000)
            let a = Int32((i * 53) % 6000 - 3000)
            let b = Int32((i * 91) % 5000 - 2500)
            return SIMD3<Int32>(l, a, b)
        }
        let out = BranchedPalette.projectQ16(p, branching: .b2, override: dense)
        #expect(out.count == 256)
        for i in 0 ..< 128 {
            #expect(out[2 * i + 1] == sigma(out[2 * i]), "pair \(i) not σ-mirrored")
        }
    }

    // MARK: the override adds EXACTLY to the generators

    @Test func overrideAddsToGeneratorsExactly() {
        let p = palette()
        let b = base()
        let delta: [SIMD3<Int32>] = (0 ..< 128).map { i in
            let l = Int32(i - 64)
            let a = Int32(2 * i - 100)
            let b = Int32(64 - i)
            return SIMD3<Int32>(l, a, b)
        }
        let out = BranchedPalette.projectQ16(p, branching: .b2, override: delta)
        for i in 0 ..< 128 {
            #expect(out[2 * i] == b[2 * i] &+ delta[i], "generator \(i) δ not applied exactly")
            #expect(out[2 * i + 1] == sigma(b[2 * i] &+ delta[i]))
        }
    }

    // MARK: brush-scoped — one generator touches only its own pair

    @Test func singleGeneratorOverrideIsScopedToItsPair() {
        let p = palette()
        let b = base()
        let deltas: [SIMD3<Int32>] = [SIMD3<Int32>(500, -300, 200),
                                      SIMD3<Int32>(0, 4096, -4096)]
        for j in [0, 1, 7, 63, 64, 127] {
            for d in deltas {
                var o = [SIMD3<Int32>](repeating: .zero, count: 128)
                o[j] = d
                let out = BranchedPalette.projectQ16(p, branching: .b2, override: o)
                for k in 0 ..< 256 where k != 2 * j && k != 2 * j + 1 {
                    #expect(out[k] == b[k], "leaf \(k) changed by an override on generator \(j)")
                }
                // ...and the pair itself moved (nonzero δ) and stayed σ-mirrored.
                #expect(out[2 * j] == b[2 * j] &+ d)
                #expect(out[2 * j] != b[2 * j])
                #expect(out[2 * j + 1] == sigma(out[2 * j]))
            }
        }
    }

    // MARK: consistency with the brush partner rule (slot ^ 1)

    @Test func sigmaPartnerOfEveryLeafIsItsReflection() {
        let out = base()
        for k in 0 ..< 256 {
            #expect(out[k ^ 1] == sigma(out[k]), "partner of leaf \(k) is not its σ-reflection")
        }
    }
}
