//  TubeGeneratorTests.swift
//  THE SCROLL's slice materializer, gated: determinism (same key ⇒ identical
//  bytes), random access (no slice consults a neighbour), schedule
//  gene-invariance (the generator consumes the theorem-fixed syntax — a gene
//  reaches only weights + palette), the zero-gene floor, and cache/direct
//  parity with LRU eviction.

import XCTest
@testable import SixFour

final class TubeGeneratorTests: XCTestCase {

    private static let seed: UInt64 = 0x5158_6F75_7254_7562  // arbitrary, pinned
    private static let zeroGene = [Int]()
    private static let witnessGene = [65536] + Array(repeating: 0, count: 20)

    // ── Determinism + shape ───────────────────────────────────────────────────

    /// Same (tubeSeed, gene, slice) ⇒ byte-identical frames, twice over — and
    /// the frames are valid preview tiles (4 × 64² indices + 768-byte palette).
    func testSliceIsDeterministicAndWellShaped() throws {
        let a = try XCTUnwrap(TubeSynth.generate(tubeSeed: Self.seed, gene: Self.zeroGene, slice: 2))
        let b = try XCTUnwrap(TubeSynth.generate(tubeSeed: Self.seed, gene: Self.zeroGene, slice: 2))
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, TubeSynth.framesPerSlice)
        for frame in a {
            XCTAssertEqual(frame.side, 64)
            XCTAssertEqual(frame.indices.count, 64 * 64)
            XCTAssertEqual(frame.paletteRGB.count, 256 * 3)
        }
        // Non-degenerate: the burst is not flat (many distinct indices).
        XCTAssertGreaterThan(Set(a[0].indices).count, 16)
    }

    /// Distinct slices and distinct tube seeds give distinct content (the
    /// never-repeating tube face at the generator seam).
    func testSlicesAndSeedsDiffer() throws {
        let s0 = try XCTUnwrap(TubeSynth.generate(tubeSeed: Self.seed, gene: Self.zeroGene, slice: 0))
        let s1 = try XCTUnwrap(TubeSynth.generate(tubeSeed: Self.seed, gene: Self.zeroGene, slice: 1))
        let other = try XCTUnwrap(TubeSynth.generate(tubeSeed: Self.seed ^ 1, gene: Self.zeroGene, slice: 0))
        XCTAssertNotEqual(s0, s1)
        XCTAssertNotEqual(s0, other)
    }

    /// RANDOM ACCESS: a slice's bytes are a pure function of its key — a far
    /// slice materializes without any neighbour having ever been computed
    /// (guaranteed by construction; pinned here against regression to stateful
    /// generation). Also: the seed derivation is context-free and pinned.
    func testSliceRandomAccess() throws {
        let direct = try XCTUnwrap(TubeSynth.generate(tubeSeed: Self.seed, gene: Self.zeroGene, slice: 1_000))
        _ = TubeSynth.generate(tubeSeed: Self.seed, gene: Self.zeroGene, slice: 999)
        let after = try XCTUnwrap(TubeSynth.generate(tubeSeed: Self.seed, gene: Self.zeroGene, slice: 1_000))
        XCTAssertEqual(direct, after)
        XCTAssertNotEqual(TubeSynth.sliceSeed(tubeSeed: Self.seed, slice: 0),
                          TubeSynth.sliceSeed(tubeSeed: Self.seed, slice: 1))
        XCTAssertEqual(TubeSynth.sliceSeed(tubeSeed: Self.seed, slice: -3),
                       TubeSynth.sliceSeed(tubeSeed: Self.seed, slice: -3))
    }

    // ── Gene seam: modulates, never mutates ──────────────────────────────────

    /// The op field is the tiling's theorem-fixed syntax: it takes NO gene and
    /// equals `S4WangTiling.sliceOpIndices` — `lawAttentionModulatesNotMutates`
    /// at the generator seam (the gene reaches only weights + palette).
    func testOpFieldIsGeneFreeSyntax() {
        for s in [0, 3, -7] {
            XCTAssertEqual(TubeSynth.opField(slice: s), S4WangTiling.sliceOpIndices(s))
        }
        // Every block has exactly one governing tile, and every tile governs
        // the same number of blocks (exhaustive, balanced).
        var counts = [Int](repeating: 0, count: 64)
        for bt in 0 ..< 2 {
            for br in 0 ..< 32 {
                for bc in 0 ..< 32 {
                    counts[TubeSynth.tileIndexForBlock(bt: bt, br: br, bc: bc)] += 1
                }
            }
        }
        XCTAssertTrue(counts.allSatisfy { $0 == 2 * 32 * 32 / 64 })
    }

    /// A gene changes expression (palette bytes move under the look warp) but
    /// the zero gene ships the floor (warp short-circuited: strength 0).
    func testGeneWarpsPaletteZeroGeneIsFloor() throws {
        XCTAssertEqual(TubeSynth.lookStrengthQ16(gene: Self.zeroGene), 0)
        XCTAssertEqual(TubeSynth.lookStrengthQ16(gene: [Int](repeating: 0, count: 21)), 0)
        XCTAssertEqual(TubeSynth.lookStrengthQ16(gene: Self.witnessGene), 65536)
        XCTAssertEqual(TubeSynth.lookStrengthQ16(gene: [100, -200]), 300)

        let floor = try XCTUnwrap(TubeSynth.generate(tubeSeed: Self.seed, gene: Self.zeroGene, slice: 0))
        let allZero = try XCTUnwrap(TubeSynth.generate(
            tubeSeed: Self.seed, gene: [Int](repeating: 0, count: 21), slice: 0))
        XCTAssertEqual(floor, allZero) // [] and 21 zeros are the SAME gene
        let expressed = try XCTUnwrap(TubeSynth.generate(
            tubeSeed: Self.seed, gene: Self.witnessGene, slice: 0))
        XCTAssertNotEqual(floor.map(\.paletteRGB), expressed.map(\.paletteRGB),
                          "a full-strength gene must move the palette")
    }

    // ── Cache: content-addressed, LRU, parity with direct generation ─────────

    func testCacheParityHitsAndEviction() throws {
        let cache = TubeSliceCache(capacity: 2)
        let direct = try XCTUnwrap(TubeSynth.generate(tubeSeed: Self.seed, gene: Self.witnessGene, slice: 4))
        let viaCache = try XCTUnwrap(cache.frames(tubeSeed: Self.seed, gene: Self.witnessGene, slice: 4))
        XCTAssertEqual(direct, viaCache)
        XCTAssertEqual(cache.misses, 1)

        // Hit: second read is served from the store.
        _ = cache.frames(tubeSeed: Self.seed, gene: Self.witnessGene, slice: 4)
        XCTAssertEqual(cache.hits, 1)

        // A different gene is a different content address (geneHash in the key).
        _ = cache.frames(tubeSeed: Self.seed, gene: Self.zeroGene, slice: 4)
        XCTAssertEqual(cache.misses, 2)

        // Capacity 2: a third distinct key evicts the LRU (slice 4 + witness,
        // which was touched before the zero-gene entry — so the zero-gene entry
        // survives and the witness entry, older by LRU order... verify by
        // recounting misses after re-reads).
        _ = cache.frames(tubeSeed: Self.seed, gene: Self.zeroGene, slice: 5)
        XCTAssertEqual(cache.misses, 3)
        _ = cache.frames(tubeSeed: Self.seed, gene: Self.zeroGene, slice: 4) // survived (recent)
        _ = cache.frames(tubeSeed: Self.seed, gene: Self.zeroGene, slice: 5) // survived (newest)
        XCTAssertEqual(cache.misses, 3, "recent keys must have survived eviction")
        _ = cache.frames(tubeSeed: Self.seed, gene: Self.witnessGene, slice: 4) // evicted → regenerate
        XCTAssertEqual(cache.misses, 4)
    }

    /// The gene hash is a pure content address: shape-padded genes collide
    /// exactly when their 21-word content matches.
    func testGeneHashIsContentAddress() {
        XCTAssertEqual(TubeSynth.geneHash([]), TubeSynth.geneHash([Int](repeating: 0, count: 21)))
        XCTAssertEqual(TubeSynth.geneHash([5, -9]), TubeSynth.geneHash([5, -9, 0, 0]))
        XCTAssertNotEqual(TubeSynth.geneHash([1]), TubeSynth.geneHash([2]))
    }
}
