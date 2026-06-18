import Testing
@testable import SixFour

/// Byte-exact gate for the GenomePair Swift port.
///
/// `GenomePair.sampleOrthogonalPair` is the hand-written Swift port of
/// `SixFour.Spec.GenomePair` (CI-proven, 10 laws). `GenomePairGolden` is GENERATED from the spec
/// by `cabal run spec-codegen` (`SixFour.Codegen.GenomePair`), so the port rides the same drift
/// gate as `RGBT4DGolden` / `VoxelReduceGolden`. Pure integer (Q16) ⇒ `(δ_A, δ_B)` must match
/// EXACTLY; the orthogonality (`genomeInner == 0`) and band-disjointness are also re-checked here.
struct GenomePairGoldenTests {

    private func unflat(_ xs: [Int]) -> [SIMD3<Int32>] {
        stride(from: 0, to: xs.count, by: 3).map {
            SIMD3<Int32>(Int32(xs[$0]), Int32(xs[$0 + 1]), Int32(xs[$0 + 2]))
        }
    }
    private func flat(_ ps: [SIMD3<Int32>]) -> [Int] {
        ps.flatMap { [Int($0.x), Int($0.y), Int($0.z)] }
    }

    /// The proposed pair matches the spec golden byte-exact (cold-start path).
    @Test func pairMatchesGeneratedGolden() {
        let gens = unflat(GenomePairGolden.generators)
        let (a, b) = GenomePair.sampleOrthogonalPair(generators: gens, ranking: [])
        #expect(flat(a) == GenomePairGolden.deltaA)
        #expect(flat(b) == GenomePairGolden.deltaB)
    }

    /// The pair is EXACTLY orthogonal (the keystone guarantee, on device).
    @Test func pairIsExactlyOrthogonal() {
        let gens = unflat(GenomePairGolden.generators)
        let (a, b) = GenomePair.sampleOrthogonalPair(generators: gens, ranking: [])
        #expect(GenomePair.genomeInner(a, b) == 0)
    }

    /// The two candidates touch disjoint generator bands.
    @Test func bandsAreDisjoint() {
        let gens = unflat(GenomePairGolden.generators)
        let (a, b) = GenomePair.sampleOrthogonalPair(generators: gens, ranking: [])
        #expect(Set(GenomePair.support(a)).isDisjoint(with: Set(GenomePair.support(b))))
    }

    /// Both candidates are real, distinct looks (norm ≥ floor, A ≠ B).
    @Test func candidatesAreDistinct() {
        let gens = unflat(GenomePairGolden.generators)
        let (a, b) = GenomePair.sampleOrthogonalPair(generators: gens, ranking: [])
        #expect(GenomePair.genomeNorm(a) >= GenomePair.minGenomeStep)
        #expect(GenomePair.genomeNorm(b) >= GenomePair.minGenomeStep)
        #expect(a != b)
    }
}
