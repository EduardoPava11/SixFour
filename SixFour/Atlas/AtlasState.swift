import Foundation
import Observation
import os
import simd

/// COLOR ATLAS — the curation session state (docs/COLOR-ATLAS.md §1–§4).
///
/// Swift mirror (UI-track stub) of the PLANNED spec module `SixFour.Spec.AtlasState`,
/// scoped to what the day-1 flywheel UI needs:
///
///   * the BOARD: base channels rebuilt from σ's committed GIFA (per-frame
///     palettes + index cube) through the one `AtlasBinIdx.bin(ofQ16:)` rule,
///     curation channels rebuilt by folding the persisted decision log
///     (`boardFromLog` — replay determinism by construction);
///   * the MOVES: all four `CurationMove` types applied through ONE `apply(_:)`
///     gate that logs, persists, and re-folds;
///   * the CANDIDATES: the `FarthestPointCollapse` baseline (the fidelity floor)
///     and one deterministic codebook-flavoured perturbation, surfaced for a
///     Compare decision (the MCTS gallery drops into this same pair seam later);
///   * the CURATED PALETTE: the Compare winner with pinned anchors substituted
///     verbatim, handed to `AtlasPaletteStore` for the render-path seam.
///
/// NOTE: the per-frame palettes reach review as display sRGB8; this stub
/// re-derives Q16 OKLab from them (`srgb8ToOKLab`, round-to-even ×2¹⁶ — the
/// `collapseForDisplay` precedent). The spec-track follow-up threads the TRUE
/// render-path Q16 centroids through `CaptureOutput` instead.
@MainActor
@Observable
final class AtlasState {

    /// What a board tap does — the UI's move selector (each is a real move type).
    enum EditMode: CaseIterable {
        case toggle      // ToggleBin (keep/kill)
        case weightUp    // WeightRegion +0.25 (Q8.8 = +64)
        case weightDown  // WeightRegion −0.25 (Q8.8 = −64)
        case pin         // PinAnchor (the bin-centre colour)
    }

    /// The two candidates of the current Compare pair.
    enum Candidate { case a, b }

    // MARK: session state

    /// True once a committed GIFA has been folded in.
    private(set) var loaded = false
    /// The live [16,16,16,6] board (base channels + folded curation channels).
    private(set) var board = AtlasBoard16.empty
    /// The append-only decision log (persisted on every move).
    private(set) var log = AtlasDecisionLog()
    /// Candidate A — the `FarthestPointCollapse` maximin baseline (Q16 leaves).
    private(set) var candidateA: [SIMD3<Int32>] = []
    /// Candidate B — a deterministic perturbation of A (Q16 leaves).
    private(set) var candidateB: [SIMD3<Int32>] = []
    /// Display twins of the candidates (256 sRGB8 each), cached at load.
    private(set) var candidateASRGB: [SIMD3<UInt8>] = []
    private(set) var candidateBSRGB: [SIMD3<UInt8>] = []
    /// The hash of the candidate the user last picked (nil before any Compare).
    private(set) var pickedHash: UInt32? = nil
    /// The per-device 770-D Bradley-Terry taste vector θ, folded on every pick and
    /// persisted across review sessions (the n=0 personalization state).
    private(set) var theta: [Double] = PersonalTaste.zeroTheta()

    /// Observability for the UI + tests (the flywheel made legible).
    /// Number of A/B Compares folded into θ (the Bradley-Terry `n`).
    var compareCount: Int { log.compareCount }
    /// ‖θ‖₂ — grows from 0 as taste is learned (the "taste strength" readout).
    var tasteNorm: Double { (theta.reduce(0) { $0 + $1 * $1 }).squareRoot() }

    /// Pick + taste telemetry — `log stream --predicate 'category == "atlas.taste"'`
    /// (or Console) to watch θ evolve on device. "To test we need logs."
    private static let tasteLog = Logger(subsystem: "com.sixfour", category: "atlas.taste")

    /// The L-slice the board view shows (0..15) — the scrubbed projection.
    var slice = 8
    /// The current tap mode.
    var mode: EditMode = .toggle

    /// The base (ch0–ch2) board, kept so move application is a pure re-fold.
    private var baseBoard = AtlasBoard16.empty
    /// The per-frame Q16 palettes the board was built from.
    private var perFrameQ16: [[SIMD3<Int32>]] = []
    private var indexCube: [UInt8] = []

    // MARK: load

    /// Fold a committed GIFA into the session: convert the display palettes to
    /// Q16, build the candidates, rebuild the board base, reload + re-fold the
    /// persisted log. Idempotent per review entry (`loaded` latch; `reset()` to re-arm).
    func loadIfNeeded(palettesPerFrame: [[SIMD3<UInt8>]], indexCube: [UInt8]) {
        guard !loaded, !palettesPerFrame.isEmpty else { return }
        loaded = true

        perFrameQ16 = palettesPerFrame.map { frame in
            frame.map { c in
                let lab = ColorScience.srgb8ToOKLab(c.x, c.y, c.z).simd
                return SIMD3<Int32>(
                    Int32((lab.x * 65536).rounded(.toNearestOrEven)),
                    Int32((lab.y * 65536).rounded(.toNearestOrEven)),
                    Int32((lab.z * 65536).rounded(.toNearestOrEven))
                )
            }
        }
        self.indexCube = indexCube

        // Candidate A: the deterministic maximin floor (the same collapse the
        // render path's first run roots at). Candidate B: a σ-paired-flavoured
        // perturbation — the stand-in for the searched gallery's second entry.
        candidateA = FarthestPointCollapse()
            .collapse(perFramePalettes: perFrameQ16, k: SixFourShape.K).leaves
        candidateB = Self.perturb(candidateA)
        candidateASRGB = candidateA.map(Self.srgb8)
        candidateBSRGB = candidateB.map(Self.srgb8)

        baseBoard = AtlasBoard16.base(
            perFramePalettesQ16: perFrameQ16,
            indexCube: indexCube,
            candidateLeavesQ16: candidateA
        )
        log = AtlasDecisionLogStore.load()
        board = boardFromLog(base: baseBoard, records: log.entries)
        theta = PersonalTasteStore.load()   // cross-session learned taste (kept across reset)
        Self.tasteLog.info("atlas loaded: compares=\(self.log.compareCount, privacy: .public) tasteNorm=\(self.tasteNorm, format: .fixed(precision: 4), privacy: .public)")
    }

    /// Drop the session so the next review entry re-folds fresh σ data.
    func reset() {
        loaded = false
        board = .empty
        baseBoard = .empty
        perFrameQ16 = []
        indexCube = []
        candidateA = []; candidateB = []
        candidateASRGB = []; candidateBSRGB = []
        pickedHash = nil
    }

    // MARK: moves (the ONE mutation gate)

    /// Play one curation move: append its record to the log, persist, and
    /// re-fold the board from base (replay determinism is the implementation,
    /// not just a law). Compare additionally publishes the curated palette.
    func apply(_ move: CurationMove) {
        appendAndRefold(AtlasDecisionRecord(move))
    }

    /// Append ONE record (carrying any CMPE embeddings), persist, and re-fold the
    /// board from base. The single log-mutation seam (replay determinism).
    private func appendAndRefold(_ record: AtlasDecisionRecord) {
        log.entries.append(record)
        AtlasDecisionLogStore.save(log)
        board = boardFromLog(base: baseBoard, records: log.entries)
    }

    /// A board tap at `bin`, interpreted by the current `mode`. Weight deltas
    /// are ±0.25 in Q8.8 (= ±64); Pin pins the bin-centre colour.
    func tap(bin: AtlasBinIdx) {
        guard bin.inRange else { return }
        switch mode {
        case .toggle:     apply(.toggleBin(bin))
        case .weightUp:   apply(.weightRegion(bin, 64))
        case .weightDown: apply(.weightRegion(bin, -64))
        case .pin:        apply(.pinAnchor(bin, bin.centerQ16))
        }
    }

    /// A Compare decision: record the Bradley-Terry pair, remember the pick, and
    /// publish the winner (with anchors substituted verbatim) as the curated
    /// global palette at the `PaletteCollapse` seam (`AtlasPaletteStore`).
    func choose(_ which: Candidate) {
        guard loaded else { return }
        let winner = which == .a ? candidateA : candidateB
        let loser = which == .a ? candidateB : candidateA
        let winHash = Self.fnv1a32(winner)
        let loseHash = Self.fnv1a32(loser)

        // The n=0 taste loop (canonical path §2): freeze the winner/loser 770-D
        // embeddings into the CMPE record → fold θ via btUpdate → persist → tint
        // the curated palette by θ → log. Both halves of the A/B nudge: the
        // TRAINING signal (θ moves) and the INFERENCE effect (palette recolours).
        let winEmb = PersonalTaste.embedding(leaves: winner)
        let loseEmb = PersonalTaste.embedding(leaves: loser)
        var record = AtlasDecisionRecord(.compare(winner: winHash, loser: loseHash))
        record.winEmbedding = winEmb.map(Float.init)
        record.loseEmbedding = loseEmb.map(Float.init)
        appendAndRefold(record)

        let normBefore = tasteNorm
        theta = PersonalTaste.btUpdate(theta: theta, winner: winEmb, loser: loseEmb)
        PersonalTasteStore.save(theta)
        pickedHash = winHash

        let curated = curatedPalette(from: winner)
        let tinted = PersonalTaste.leafTint(curated, theta: theta)
        AtlasPaletteStore.shared.curatedLeavesQ16 = tinted

        let tintMaxQ16 = zip(tinted, curated).map { t, c in
            max(abs(Int(t.x - c.x)), abs(Int(t.y - c.y)), abs(Int(t.z - c.z)))
        }.max() ?? 0
        Self.tasteLog.info(
            "pick=\(which == .a ? "A" : "B", privacy: .public) compareN=\(self.compareCount, privacy: .public) tasteNorm \(normBefore, format: .fixed(precision: 4), privacy: .public)→\(self.tasteNorm, format: .fixed(precision: 4), privacy: .public) tintMaxQ16=\(tintMaxQ16, privacy: .public)")
    }

    /// The chosen leaves with every pinned anchor substituted EXACTLY (each
    /// anchor replaces its nearest leaf, ties→lowest — the user contract that
    /// pins survive to the output palette; bins iterated in ascending flat order
    /// so the substitution is deterministic).
    func curatedPalette(from leaves: [SIMD3<Int32>]) -> [SIMD3<Int32>] {
        var out = leaves
        for flat in board.anchorColors.keys.sorted() {
            guard let color = board.anchorColors[flat], !out.isEmpty else { continue }
            out[FarthestPointCollapse.nearestQ16(color, out)] = color
        }
        return out
    }

    // MARK: deterministic helpers

    /// Candidate B: a fixed σ-paired-flavoured chroma perturbation of A —
    /// ±0.04 OKLab (Q16 2621) on `a`, sign alternating across slot pairs (the
    /// 12-entry delta codebook's largest chroma rung; rows 2i/2i+1 swap under σ).
    /// Deterministic, integer-exact, and visibly distinct — exactly enough for a
    /// day-1 Compare. The MCTS gallery replaces this producer behind the same pair.
    static func perturb(_ leaves: [SIMD3<Int32>]) -> [SIMD3<Int32>] {
        let delta: Int32 = 2621   // 0.04 × 2¹⁶
        return leaves.enumerated().map { i, c in
            SIMD3<Int32>(c.x, c.y &+ (i % 2 == 0 ? delta : -delta), c.z)
        }
    }

    /// FNV-1a 32 over the leaves' little-endian Q16 bytes — the stub's stand-in
    /// for the spec's genome hash (stable across runs; identifies a candidate in
    /// Compare records).
    static func fnv1a32(_ leaves: [SIMD3<Int32>]) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for c in leaves {
            for v in [c.x, c.y, c.z] {
                let u = UInt32(bitPattern: v)
                for shift in stride(from: 0, to: 32, by: 8) {
                    h = (h ^ ((u >> UInt32(shift)) & 0xFF)) &* 16_777_619
                }
            }
        }
        return h
    }

    /// Q16 OKLab → display sRGB8 (the gallery swatches; display-only, never the
    /// render path — the render path converts through the owned Zig kernel).
    static func srgb8(_ c: SIMD3<Int32>) -> SIMD3<UInt8> {
        ColorScience.okLabToSRGB8(OKLab(
            Float(c.x) / 65536, Float(c.y) / 65536, Float(c.z) / 65536
        ))
    }
}
