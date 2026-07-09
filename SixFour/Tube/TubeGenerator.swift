//  TubeGenerator.swift
//  THE SCROLL's slice materializer — one 4-frame 64² pour group per slice,
//  deterministic + random-access, from EXISTING kernels only.
//
//  PIPELINE (all integer, all pinned):
//    1. SEED   — `sliceSeed(tubeSeed, n)` (SplitMix64 mix, pinned constants)
//                → `s4_synth_burst` (deterministic camera-free OKLab Q16 burst,
//                4 frames × 64² — the pour group: four fine frames = one coarse).
//    2. SYNTAX — `S4WangTiling.sliceOpIndices(n)`: the theorem-fixed 4×16 op
//                field of the Jeandel–Rao tiling (never repeats, random access).
//    3. OPS    — per 2×2×2 block per channel: `s4_octant_lift` → 8 bands; the
//                block's tile op acts on its band kill-set, scaled by the gene's
//                attention weight (Q16); the section direction materializes back
//                through `s4_cube_expand_rung` at side 1 (ONE coarse voxel + 7
//                detail bands → its 2×2×2 block — the same operator the export
//                rung iterates; identity `I` blocks are untouched).
//    4. LOOK   — per frame: `s4_quantize_frame` (256-leaf palette + indices);
//                a non-floor gene warps the PALETTE (never the indices) through
//                the landed look transform (`s4_zone_profile_q16` →
//                `s4_look_transfer_q16`); `s4_palette_oklab_to_srgb8` realizes
//                the preview bytes. Zero gene ⇒ warp skipped: zero-gene == the
//                deterministic floor.
//  Frames come out as valid preview tiles: 64² palette indices + 768-byte sRGB
//  palette (the GIF-frame vocabulary — `s4_gif_assemble`-ready).
//
//  LAWS THE TESTS PIN (TubeGeneratorTests): determinism (same key ⇒ identical
//  bytes), slice independence (random access — no neighbour consulted),
//  schedule gene-invariance (the op field never reads the gene; a gene reaches
//  only weights + palette — `lawAttentionModulatesNotMutates` at the generator
//  seam), and cache/direct parity.
//
//  PINNED CHOICES OF THIS GENERATOR (not spec theorems; documented so they
//  cannot drift silently — each is testable and revisable in one place):
//    • Lane→band map: `s4_octant_lift` emits [coarse, g0,b0,t0, g1,b1,t1, dz];
//      lanes are read as bands {x},{y},{xy} (near face), {xt},{yt},{xyt}
//      (far face — the time-carrying details), {t} (dz). Axis-honest: K_t's
//      kill-set = every far-face lane + dz; K_x/K_y kill their face gradients.
//    • Op expression: band' = band − ⌊w·band/2¹⁶⌋ toward the op's target on its
//      kill-set (identity at w=0, the spec band action at w=2¹⁶) — attention
//      SCALES expression, exactly the BudgetHead discipline.
//    • Tile→block map: the 4×16 tile field tiles the 2×32×32 block lattice via
//      `tileIndexForBlock` (deterministic, exhaustive, documented there).
//    • Gene→look strength: strength_q16 = min(2¹⁶, Σ|word|) — zero gene ⇒ 0 ⇒
//      the warp short-circuits to the floor.
//
//  PERF: nothing here runs per-tick — a slice materializes ON DEMAND (scroll
//  lingering), and `TubeSliceCache` content-addresses the result, so repeated
//  reads are dictionary hits. UPGRADE PATH: the cache key is already a content
//  address `(tubeSeed, geneHash, slice)`, so swapping the in-memory LRU for an
//  mmap'd on-disk store (the .s4cr pattern) is storage-only — no key change.

import Foundation

/// One preview-ready frame of the tube: 64² palette indices + the 256-entry
/// sRGB palette — the same (indices, palette) vocabulary the GIF assembler and
/// the preview cells consume.
struct TubeFrame: Equatable, Sendable {
    let side: Int
    let indices: [UInt8]      // side² palette indices
    let paletteRGB: [UInt8]   // 256 × 3 sRGB bytes
}

/// The pure slice factory (stateless — all state is in the arguments).
enum TubeSynth {

    /// Frames per slice = the pour group (`S4WangTiling.sliceRows` = 4).
    static let framesPerSlice = S4WangTiling.sliceRows
    /// Fine frame side (the 64² rung).
    static let side = 64
    /// Palette size (the 256-leaf GIF colour table).
    static let paletteK = 256
    /// Lloyd refinement passes after maximin seeding (pinned).
    static let lloydIters = 1
    /// Luminance zones of the gene look warp (the landed look-transfer default).
    static let lookZones = 8

    // ── Seed derivation (pinned) ──────────────────────────────────────────────

    /// SplitMix64 (Steele/Lea/Flood — the same constants as the synth kernel's
    /// PRNG; replicated privately because the kernel helper is file-private).
    private static func splitmix64(_ state: inout UInt64) -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// The per-slice synth seed: one SplitMix64 step over the tube seed offset
    /// by the slice index times the golden-ratio increment. Deterministic,
    /// context-free (slice n never reads slice n−1 — random access), and
    /// well-spread for adjacent n.
    static func sliceSeed(tubeSeed: UInt64, slice: Int) -> UInt64 {
        var state = tubeSeed ^ (UInt64(bitPattern: Int64(slice)) &* 0x9E37_79B9_7F4A_7C15)
        return splitmix64(&state)
    }

    /// FNV-1a 64 over the gene's 21 words (little-endian Int64 bytes) — the
    /// CACHE KEY component only (content addressing), never a semantic surface
    /// (the semantic gene identity is `Spec.GeneHash`'s canonical preimage).
    static func geneHash(_ gene: [Int]) -> UInt64 {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        var i = 0
        while i < 21 {
            var w = UInt64(bitPattern: Int64(i < gene.count ? gene[i] : 0))
            var b = 0
            while b < 8 {
                h = (h ^ (w & 0xFF)) &* 0x0000_0100_0000_01B3
                w >>= 8
                b += 1
            }
            i += 1
        }
        return h
    }

    // ── The op field ──────────────────────────────────────────────────────────

    /// The slice's theorem-fixed op field (4×16 indices into
    /// `S4WangTiling.opsCanonical`, row-major). Takes NO gene: the schedule is
    /// SYNTAX — `lawAttentionModulatesNotMutates` at the generator seam.
    static func opField(slice: Int) -> [Int] {
        S4WangTiling.sliceOpIndices(slice)
    }

    /// Which tile governs block `(bt, br, bc)` of the 2×32×32 block lattice
    /// (the 4×64×64 slab in 2×2×2 blocks): tile row = bt·2 + br/16 (each tile
    /// row owns one time-block × 16 row-blocks), tile col = bc/2 (each tile col
    /// owns 2 col-blocks). Exhaustive and deterministic: every block has
    /// exactly one governing tile.
    static func tileIndexForBlock(bt: Int, br: Int, bc: Int) -> Int {
        (bt * 2 + br / 16) * S4WangTiling.sliceWidth + bc / 2
    }

    // Per-op kill-lane table over the octant-lift lanes 1..7, in
    // `opsCanonical` order. Lane→band map (PINNED, see header): 1→{x} 2→{y}
    // 3→{xy} 4→{xt} 5→{yt} 6→{xyt} 7→{t}. K_a kills every a-containing lane;
    // S_A rewrites exactly its lane (zero-detail floor); I touches nothing.
    private static let killLanes: [[Int]] = {
        let laneBand: [S4WangTiling.AxisSet] = [
            .x, .y, [.x, .y], [.x, .t], [.y, .t], [.x, .y, .t], .t,
        ]
        return S4WangTiling.opsCanonical.map { op in
            switch op {
            case .i:
                return []
            case .k(let a):
                return (0 ..< 7).compactMap { laneBand[$0].contains(a) ? $0 + 1 : nil }
            case .s(let bandSet):
                return (0 ..< 7).compactMap { laneBand[$0] == bandSet ? $0 + 1 : nil }
            }
        }
    }()

    // ── The slice materializer ────────────────────────────────────────────────

    /// Materialize slice `slice` of tube `tubeSeed` under `gene` (θ_up 21-word
    /// layout; `[]` or all-zero = the deterministic floor). Returns the 4
    /// preview frames, or nil if a kernel refuses (out-of-domain — impossible
    /// for synth input, but the refusal is propagated, never wrapped).
    static func generate(tubeSeed: UInt64, gene: [Int], slice: Int) -> [TubeFrame]? {
        let s = side
        let p = s * s
        let fc = framesPerSlice

        // 1. The deterministic burst (camera-free visual substrate).
        guard var vol = SixFourNative.synthBurst(
            seed: sliceSeed(tubeSeed: tubeSeed, slice: slice),
            mode: S4_SYNTH_COLOR, frameCount: Int32(fc), side: Int32(s))
        else { return nil }

        // 2 + 3. The op field, expressed through the gene's attention weights.
        let ops = opField(slice: slice)
        let row = S4WangTiling.attentionQ16(gene: gene)
        guard applyOps(volume: &vol, ops: ops, weightsQ16: row) else { return nil }

        // 4. Per-frame palette + indices, gene-warped palette, preview bytes.
        let strength = lookStrengthQ16(gene: gene)
        var frames: [TubeFrame] = []
        frames.reserveCapacity(fc)
        for f in 0 ..< fc {
            let frameOKLab = Array(vol[f * p * 3 ..< (f + 1) * p * 3])
            guard let quant = SixFourNative.quantizeFrame(
                oklabQ16: frameOKLab, k: paletteK, lloydIters: lloydIters)
            else { return nil }
            var palette = quant.centroids
            if strength > 0 {
                // The gene warps the PALETTE (never the indices): retrieve the
                // palette's own zone profile, transfer toward it — the RAG seam
                // (today: the gene's energy drives ONE landed look transform).
                guard let profile = SixFourNative.lookZoneProfile(
                    paletteOklabQ16: palette, numZones: lookZones)
                else { return nil }
                var params = SixFourNative.LookParams()
                params.strength = strength
                guard let warped = SixFourNative.lookTransfer(
                    oklabQ16: palette, profile: profile, params: params)
                else { return nil }
                palette = warped
            }
            var rgb = [UInt8](repeating: 0, count: paletteK * 3)
            let rc = palette.withUnsafeBufferPointer { c in
                rgb.withUnsafeMutableBufferPointer { o in
                    s4_palette_oklab_to_srgb8(c.baseAddress, Int32(paletteK),
                                              o.baseAddress, nil, 0)
                }
            }
            guard rc == S4_RC_OK else { return nil }
            frames.append(TubeFrame(side: s, indices: quant.indices, paletteRGB: rgb))
        }
        return frames
    }

    /// The gene's look-warp strength (Q16, PINNED): min(2¹⁶, Σ|word|). The
    /// zero gene yields 0 — the warp short-circuits and the floor ships.
    static func lookStrengthQ16(gene: [Int]) -> Int32 {
        var total = 0
        for (i, w) in gene.enumerated() where i < 21 {
            total += abs(w)
            if total >= S4WangTiling.q16One { return Int32(S4WangTiling.q16One) }
        }
        return Int32(total)
    }

    /// Express the op field on the volume: per channel, per 2×2×2 block —
    /// `s4_octant_lift` → weighted band action → `s4_cube_expand_rung(side: 1)`
    /// (the section/materialize direction through the export-rung operator).
    /// Returns false iff a kernel refuses (propagated, never wrapped).
    private static func applyOps(volume: inout [Int32], ops: [Int],
                                 weightsQ16: [Int32]) -> Bool {
        let s = side
        var cells = [Int32](repeating: 0, count: 8)  // gathered 2×2×2 block
        var bands = [Int32](repeating: 0, count: 8)  // [coarse, 7 details]
        var block = [Int32](repeating: 0, count: 8)  // materialized block
        return volume.withUnsafeMutableBufferPointer { vol -> Bool in
            let v = vol.baseAddress!
            for ch in 0 ..< 3 {
                for bt in 0 ..< framesPerSlice / 2 {
                    for br in 0 ..< s / 2 {
                        for bc in 0 ..< s / 2 {
                            let opIdx = ops[tileIndexForBlock(bt: bt, br: br, bc: bc)]
                            let lanes = killLanes[opIdx]
                            if lanes.isEmpty { continue } // I: work 0, untouched
                            let w = Int64(weightsQ16[opIdx])
                            if w == 0 { continue }        // zero expression
                            // Gather (lane dt·4+dr·2+dc — the octant layout).
                            for dt in 0 ..< 2 {
                                for dr in 0 ..< 2 {
                                    for dc in 0 ..< 2 {
                                        let t = 2 * bt + dt, r = 2 * br + dr, c = 2 * bc + dc
                                        cells[dt * 4 + dr * 2 + dc] =
                                            v[((t * s + r) * s + c) * 3 + ch]
                                    }
                                }
                            }
                            let rcL = cells.withUnsafeBufferPointer { i8 in
                                bands.withUnsafeMutableBufferPointer { o8 in
                                    s4_octant_lift(i8.baseAddress, o8.baseAddress)
                                }
                            }
                            guard rcL == S4_RC_OK else { return false }
                            // The op's band action, scaled by attention:
                            // band' = band − ⌊w·band/2¹⁶⌋ (target 0 on the
                            // kill-set; identity at w=0, spec action at w=2¹⁶).
                            for lane in lanes {
                                let b = Int64(bands[lane])
                                bands[lane] = Int32(b - ((w * b) >> 16))
                            }
                            // Materialize: ONE coarse voxel + 7 detail bands →
                            // the 2×2×2 block via the export-rung operator.
                            let rcE = bands.withUnsafeBufferPointer { b8 in
                                block.withUnsafeMutableBufferPointer { o8 in
                                    s4_cube_expand_rung(b8.baseAddress, 1,
                                                        b8.baseAddress! + 1,
                                                        o8.baseAddress)
                                }
                            }
                            guard rcE == S4_RC_OK else { return false }
                            for dt in 0 ..< 2 {
                                for dr in 0 ..< 2 {
                                    for dc in 0 ..< 2 {
                                        let t = 2 * bt + dt, r = 2 * br + dr, c = 2 * bc + dc
                                        v[((t * s + r) * s + c) * 3 + ch] =
                                            block[dt * 4 + dr * 2 + dc]
                                    }
                                }
                            }
                        }
                    }
                }
            }
            return true
        }
    }
}

/// Content-addressed slice cache: key = (tubeSeed, geneHash, slice), small LRU.
/// Single-owner by design (not Sendable) — the scroll surface owns one.
/// UPGRADE PATH: swap the dictionary for an mmap'd on-disk store keyed by the
/// SAME content address when the tube outgrows RAM; nothing else changes.
final class TubeSliceCache {

    struct Key: Hashable, Sendable {
        let tubeSeed: UInt64
        let geneHash: UInt64
        let slice: Int
    }

    private var store: [Key: [TubeFrame]] = [:]
    private var order: [Key] = []  // LRU order, most recent last
    private let capacity: Int

    /// Aggregate telemetry (never logged per-tick; read at burst boundaries).
    private(set) var hits = 0
    private(set) var misses = 0

    init(capacity: Int = 16) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    /// The slice's frames — cache hit or `TubeSynth.generate` on miss (then
    /// content-addressed for reuse). Returns nil only if generation refuses.
    func frames(tubeSeed: UInt64, gene: [Int], slice: Int) -> [TubeFrame]? {
        let key = Key(tubeSeed: tubeSeed, geneHash: TubeSynth.geneHash(gene), slice: slice)
        if let cached = store[key] {
            hits += 1
            touch(key)
            return cached
        }
        misses += 1
        guard let made = TubeSynth.generate(tubeSeed: tubeSeed, gene: gene, slice: slice)
        else { return nil }
        store[key] = made
        order.append(key)
        if order.count > capacity {
            let evicted = order.removeFirst()
            store.removeValue(forKey: evicted)
        }
        return made
    }

    private func touch(_ key: Key) {
        if let i = order.firstIndex(of: key) {
            order.remove(at: i)
            order.append(key)
        }
    }
}
