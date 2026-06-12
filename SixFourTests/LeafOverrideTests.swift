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

    // MARK: override LONGER than the generator count — extras are ignored

    /// `sigmaPairProjectQ16` reads `override[idx]` only for `idx < ci.count` (= 128). A
    /// 256-entry override must produce the SAME table as its first-128 prefix — entries
    /// 128..255 are inert. Pins the "extras ignored" branch the Swift suite never hit.
    @Test func overrideLongerThanGeneratorCountIgnoresTail() {
        let p = palette()
        let prefix: [SIMD3<Int32>] = (0 ..< 128).map { (i: Int) -> SIMD3<Int32> in
            let x: Int32 = Int32(i - 50)
            let y: Int32 = Int32(3 * i - 200)
            let z: Int32 = Int32(100 - i)
            return SIMD3<Int32>(x, y, z)
        }
        // Append 128 arbitrary (large) extra entries that MUST be ignored.
        let tail: [SIMD3<Int32>] = (0 ..< 128).map { (i: Int) -> SIMD3<Int32> in
            let x: Int32 = Int32(1_000_000 + i)
            let y: Int32 = Int32(-2_000_000 - i)
            let z: Int32 = Int32(3_000_000 + i)
            return SIMD3<Int32>(x, y, z)
        }
        let long = prefix + tail
        let outLong = BranchedPalette.projectQ16(p, branching: .b2, override: long)
        let outPrefix = BranchedPalette.projectQ16(p, branching: .b2, override: prefix)
        #expect(outLong == outPrefix, "override entries past generator 127 were not ignored")
        #expect(outLong.count == 256)
    }

    // MARK: multi-generator superposition — independence + additivity

    /// Two DIFFERENT generators overridden in the same call must each equal their
    /// single-generator result — no cross-talk (the Haskell
    /// `lawSigmaOverrideGeneratorsIndependent` twin).
    @Test func differentGeneratorsAreIndependent() {
        let p = palette()
        let pairs: [(Int, Int)] = [(0, 1), (3, 64), (10, 127), (63, 64)]
        let di = SIMD3<Int32>(700, -400, 250)
        let dj = SIMD3<Int32>(-300, 1500, -1200)
        for (a, b) in pairs {
            var oi = [SIMD3<Int32>](repeating: .zero, count: 128); oi[a] = di
            var oj = [SIMD3<Int32>](repeating: .zero, count: 128); oj[b] = dj
            var oBoth = [SIMD3<Int32>](repeating: .zero, count: 128); oBoth[a] = di; oBoth[b] = dj
            let soloI = BranchedPalette.projectQ16(p, branching: .b2, override: oi)
            let soloJ = BranchedPalette.projectQ16(p, branching: .b2, override: oj)
            let both = BranchedPalette.projectQ16(p, branching: .b2, override: oBoth)
            #expect(both[2 * a] == soloI[2 * a] && both[2 * a + 1] == soloI[2 * a + 1],
                    "generator \(a) bled when \(b) was also edited")
            #expect(both[2 * b] == soloJ[2 * b] && both[2 * b + 1] == soloJ[2 * b + 1],
                    "generator \(b) bled when \(a) was also edited")
        }
    }

    /// δ is additive in generator space: projecting with (δ₁+δ₂) equals adding both
    /// (Haskell `lawSigmaOverrideAdditive` twin). Uses `&+` to match the genome's wrap.
    @Test func overrideIsAdditiveInGeneratorSpace() {
        let p = palette()
        let b = base()
        let d1: [SIMD3<Int32>] = (0 ..< 128).map { (i: Int) -> SIMD3<Int32> in
            SIMD3<Int32>(Int32(i), Int32(-i), Int32(2 * i))
        }
        let d2: [SIMD3<Int32>] = (0 ..< 128).map { (i: Int) -> SIMD3<Int32> in
            let x: Int32 = Int32(5 * i - 100)
            let y: Int32 = Int32(i + 7)
            let z: Int32 = Int32(-3 * i)
            return SIMD3<Int32>(x, y, z)
        }
        let summed: [SIMD3<Int32>] = (0 ..< 128).map { d1[$0] &+ d2[$0] }
        let out = BranchedPalette.projectQ16(p, branching: .b2, override: summed)
        for i in 0 ..< 128 {
            #expect(out[2 * i] == b[2 * i] &+ d1[i] &+ d2[i], "δ not additive at generator \(i)")
            #expect(out[2 * i + 1] == sigma(out[2 * i]))
        }
    }

    // MARK: OVERFLOW / extreme-δ probe — wrapping math, σ-symmetry STILL holds

    /// Adversarial extreme-δ probe. The genome uses wrapping ops (`c &+ override`,
    /// `0 &- g.y`). Even with δ near `Int32.max` (FAR outside the shipped ±8192 slider
    /// domain), the per-pair σ-symmetry is STRUCTURALLY preserved: `out[2i+1]` is computed
    /// from the WRAPPED `out[2i]` with the same wrapping negate, so `out[2i+1] == σ(out[2i])`
    /// bit-for-bit. This documents that the value silently WRAPS off-domain (a Haskell↔Swift
    /// VALUE divergence is reachable only here, never in production), but the SYMMETRY
    /// contract cannot be broken by any override value.
    @Test func extremeOverrideWrapsButKeepsSigmaSymmetry() {
        let p = palette()
        let extreme: [SIMD3<Int32>] = [
            SIMD3<Int32>(Int32.max, Int32.max, Int32.max),
            SIMD3<Int32>(Int32.min, Int32.min, Int32.min),
            SIMD3<Int32>(Int32.max, Int32.min, 0),
            SIMD3<Int32>(2_147_483_647, -2_147_483_648, 1)
        ]
        for d in extreme {
            var o = [SIMD3<Int32>](repeating: .zero, count: 128)
            // Hit several generators including ones whose chroma is already nonzero.
            for j in [0, 1, 31, 64, 127] { o[j] = d }
            let out = BranchedPalette.projectQ16(p, branching: .b2, override: o)
            #expect(out.count == 256)
            // σ-symmetry holds for EVERY pair regardless of wraparound.
            for i in 0 ..< 128 {
                #expect(out[2 * i + 1] == sigma(out[2 * i]),
                        "extreme δ \(d) broke σ-symmetry at pair \(i)")
            }
            // And the partner-index rule (k^1) still equals σ.
            for k in 0 ..< 256 {
                #expect(out[k ^ 1] == sigma(out[k]))
            }
        }
    }

    /// `0 &- Int32.min == Int32.min`: the two's-complement fixed point of σ-negate. This
    /// pins the documented theoretical asymmetry — a chroma of exactly `Int32.min` mirrors
    /// to ITSELF, not its negation — and confirms the pairwise σ helper wraps identically,
    /// so the σ-pair equality law still holds. Unreachable in the real Q16 domain (chroma
    /// magnitudes ~±34406 with δ at the slider bound), pure two's-complement documentation.
    @Test func sigmaNegateIsFixedPointAtInt32Min() {
        let g = SIMD3<Int32>(123, Int32.min, Int32.min)
        let s = sigma(g)
        #expect(s.y == Int32.min, "0 &- Int32.min should wrap to Int32.min")
        #expect(s.z == Int32.min)
        #expect(s.x == g.x)
        // Involution under wrapping negate: σ(σ g) == g still holds bit-for-bit.
        #expect(sigma(s) == g)
    }

    // MARK: PREVIEW ≡ SHIP — the override-bearing global table is shared

    /// The single most important missing invariant (adversary-flagged): the PREVIEW leaf
    /// source `LadderExport.flatGlobalLeaves(P)` is byte-identical to the leaves
    /// `LadderExport.makeURL` collapses internally, so
    /// `projectQ16(flatGlobalLeaves(P), branching, override)` IS the exact global colour
    /// table `makeURL` ships. A future edit that diverged the two duplicated collapse
    /// expressions (e.g. changed `k` on one site) would fail HERE with no UI involved.
    @Test func previewLeafSourceMatchesShipCollapseForEveryBranchingAndOverride() {
        // A small deterministic stand-in for the 64 per-frame palettes (sRGB8).
        let perFrame: [[SIMD3<UInt8>]] = (0 ..< 8).map { (f: Int) -> [SIMD3<UInt8>] in
            (0 ..< 64).map { (i: Int) -> SIMD3<UInt8> in
                let x: UInt8 = UInt8((i * 4 + f) & 0xFF)
                let y: UInt8 = UInt8((i * 7 + 2 * f) & 0xFF)
                let z: UInt8 = UInt8((i * 11 + 3 * f) & 0xFF)
                return SIMD3<UInt8>(x, y, z)
            }
        }
        // Preview path: flatGlobalLeaves (the cached, branching-independent maximin).
        let previewLeaves = LadderExport.flatGlobalLeaves(palettesPerFrame: perFrame)
        // Ship path: makeURL collapses `toQ16(P)` the SAME way before projectQ16.
        let shipLeaves = FarthestPointCollapse()
            .collapse(perFramePalettes: LadderExport.toQ16(perFrame), k: SixFourShape.K).leaves
        #expect(previewLeaves == shipLeaves,
                "preview leaf source diverged from the ship collapse — preview ≢ ship")

        // And the projected, override-bearing global tables (what each side actually
        // hands the encoder / the preview surface) are byte-identical for every radix.
        let override: [SIMD3<Int32>] = (0 ..< 128).map { (i: Int) -> SIMD3<Int32> in
            SIMD3<Int32>(Int32(i - 64), Int32(2 * i), Int32(-i))
        }
        for branching in PaletteBranching.allCases {
            let previewGlobal = BranchedPalette.projectQ16(previewLeaves, branching: branching, override: override)
            let shipGlobal = BranchedPalette.projectQ16(shipLeaves, branching: branching, override: override)
            #expect(previewGlobal == shipGlobal,
                    "preview ≢ ship global table for branching \(branching.rawValue)")
        }
    }
}
