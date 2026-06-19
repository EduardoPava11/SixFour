import SwiftUI
import simd

/// Π for the `.captured` + `.picked` phases — the orthogonal A/B game, the PRIMARY surface
/// after the genome shift. Two competing candidate looks (A and B) play side-by-side as
/// REAL 64×64 looping GIFs on the ONE κ clock; tapping a hero IS the pick. Each pick folds
/// the learned taste θ (Bradley–Terry) and re-derives the next pair from the new θ — the
/// "infinite game" self-loop in `.picked`. An Export button advances to `.exporting`.
///
/// Modelled on the existing A/B logic in `ReviewPhaseField` (`abTheta` / `abPickCount` /
/// `recordABPick`) + `ABCandidates.fromPalette` (the `GenomePair.sampleOrthogonalPair`
/// orthogonal pair) + `CandidatePickView`. The difference: A and B here are not flat 16×16
/// swatches but two full per-frame GIFs read through `surface.indexCube` at `surface.cursor`,
/// so the user judges the LOOK in motion. Gated by `Feature.abCandidatePicker`.
///
/// Cells only (`CellSprite` / `CellText` / `CellActionButton`), routed through `GlobalLattice`
/// (the GRID design law). Reads σ for data; writes σ only via `.pickA` / `.pickB` /
/// `.exportFamily`. Tier-2 pure: SwiftUI + simd.
struct ABCandidatePhaseField: View {
    /// σ — read for the index cube + cursor; written via the FSM pick/export events.
    @Bindable var surface: Surface
    /// κ — advances `σ.cursor` (the Z₆₄ frame both heroes play on).
    let clock: SurfaceClock
    /// The shared AppSettings (matches the other PhaseField initializers).
    @Bindable var settings: AppSettings

    /// The learned taste vector (Bradley–Terry θ), loaded from the device store and folded
    /// on every pick — the SAME store `ReviewPhaseField` uses, so the loop is continuous.
    @State private var abTheta: [Double] = PersonalTasteStore.load()
    /// Picks so far — drives the converging A/B gap shown to the user.
    @State private var abPickCount = 0

    /// The per-frame candidate sRGB palettes (64 × 256), recomputed when θ or the per-frame
    /// palette series changes. Empty until the first compute; the heroes then fall through to
    /// the live ground (no crash). `candA[t]` is frame `t`'s palette for look A, likewise B.
    @State private var candA: [[SIMD3<UInt8>]] = []
    @State private var candB: [[SIMD3<UInt8>]] = []
    /// Always EMPTY under the delta-preserving move: A and B differ by a COHERENT isometry over
    /// the SAME index structure (recolour `surface.indexCube`), not a re-quantised cube — that is
    /// what keeps the relative deltas intact. (The hero recolours the base cube when these are empty.)
    @State private var candAIdx: [[UInt8]] = []
    @State private var candBIdx: [[UInt8]] = []
    /// Frame-0's candidate objects — their Q16 `.leaves` are the `btUpdate` embedding when a
    /// look wins/loses (matching `ReviewPhaseField`, which embeds from `palettesPerFrame.first`).
    @State private var frame0: (a: ABCandidates.Candidate, b: ABCandidates.Candidate)?

    /// The cumulative pick drift (Q16 OKLab), capped to the `MoveRadiusSchedule` L∞ ball: each pick
    /// nudges it toward the chosen direction, so the pair RE-CENTERS on your taste — but BOUNDED, so
    /// it can never drift into noise (the degradation the unbounded lossy re-center caused). θ is
    /// still folded for the future taste model; the drift is the visible steering for now.
    @State private var centerShift: SIMD3<Int32> = .zero

    private let side = GlobalLattice.previewCells   // 64
    /// Each hero is half the preview hero's pitch so the two GIFs sit side-by-side (2 pt/cell).
    private var heroCellPt: CGFloat { GlobalLattice.gif(GlobalLattice.previewCells) / CGFloat(side * 2) }

    var body: some View {
        ZStack {
            // The influence-field ground is the ONE persistent surface (behind every phase).
            // This phase renders only the two heroes + chrome on a clear background.
            Color.clear

            if surface.palettesPerFrame.isEmpty || candA.isEmpty || candB.isEmpty {
                // No committed per-frame palette yet (or compute pending): show nothing —
                // the live ground shows through (no flat fill, no crash).
                Color.clear
            } else {
                VStack(spacing: GlobalLattice.pt(3)) {
                    CellText(headerText, rows: 8, ink: Color(srgb8: SIMD3(200, 200, 200)))

                    HStack(spacing: GlobalLattice.pt(9)) {    // symmetric A | B gutter
                        hero(palettes: candA, indices: candAIdx, label: "A") { pick(a: true) }
                        hero(palettes: candB, indices: candBIdx, label: "B") { pick(a: false) }
                    }

                    Button { surface.step(.exportFamily) } label: {
                        CellActionButton(icon: .none, title: "EXPORT ▸",
                                         prominent: true, fillWidth: false)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, GlobalLattice.pt(2))
                    .accessibilityLabel("Export the cube-ladder family")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        // Recompute OFF the main actor whenever the capture or the pick count changes (the
        // heavy 64×(palette + 2 dither) FFI would hitch the κ clock if run on `pick`). `.task`
        // cancels + restarts on `recomputeKey` change, so a rapid pick supersedes the prior round.
        .task(id: recomputeKey) { await recomputeAsync() }
    }

    /// The recompute trigger: a fresh capture (palette/pixel series changed) or a new pick.
    private var recomputeKey: String {
        "\(surface.palettesPerFrame.count)·\(surface.framePixelsQ16.count)·\(abPickCount)"
    }

    /// "PICK A LOOK · ROUND n" — the game progress.
    private var headerText: String { "PICK A LOOK · ROUND \(abPickCount + 1)" }

    // MARK: - The two GIF heroes (each a 64×64 cell loop at σ.cursor)

    /// One candidate hero: the GIF playing as a flat 64×64 cell loop at the κ cursor, read
    /// through THIS candidate's per-frame palette via `surface.indexCube`. Tapping it IS the
    /// pick. `nil` cells (out-of-range cursor / palette) fall through to the live ground.
    private func hero(palettes: [[SIMD3<UInt8>]], indices: [[UInt8]], label: String, _ onPick: @escaping () -> Void) -> some View {
        let t = surface.cursor
        let pal = (t >= 0 && t < palettes.count) ? palettes[t] : []
        let idxFrame = (t >= 0 && t < indices.count) ? indices[t] : []
        return Button(action: onPick) {
            VStack(spacing: GlobalLattice.pt(1)) {
                CellSprite(cols: side, rows: side, cellPt: heroCellPt) { c, r in
                    // THE one cube reader (`Surface.gifCell`): the candidate's re-quantized
                    // index frame (P3 — A and B are different cubes) through its per-frame
                    // palette, falling back to the shared `indexCube` when no candidate cube.
                    surface.gifCell(c, r, t, palette: pal, indexFrame: idxFrame)
                }
                CellText(label, rows: 8, ink: .white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Candidate \(label)")
        .accessibilityHint("Tap to choose this look; the next pair tracks your taste")
    }

    // MARK: - The game loop

    /// Fold the A/B pick into θ (Bradley–Terry, the built `PersonalTaste` loop), persist,
    /// recompute the re-proposed pair, and advance the FSM. The candidate cache recompute on
    /// the new θ IS the next round (the infinite game). `pickA` / `pickB` both self-loop in
    /// `.picked` per the spec; from `.captured` they enter `.picked`.
    private func pick(a pickedA: Bool) {
        // The two candidates' isometry shifts THIS round — MUST match `computeCandidates` exactly.
        let sepV = SIMD3<Int32>(0, MoveRadiusSchedule.radius(abPickCount) / 2, 0)
        let shiftA = MoveRadiusSchedule.clampToCap(centerShift &+ sepV)
        let shiftB = MoveRadiusSchedule.clampToCap(centerShift &- sepV)

        if let cands = frame0 {
            let winner = pickedA ? cands.a : cands.b
            let loser  = pickedA ? cands.b : cands.a
            let winEmb = PersonalTaste.embedding(leaves: winner.leaves)
            let loseEmb = PersonalTaste.embedding(leaves: loser.leaves)
            abTheta = PersonalTaste.btUpdate(theta: abTheta, winner: winEmb, loser: loseEmb)
            PersonalTasteStore.save(abTheta)
            logPick(pickedA: pickedA, winner: winner, loser: loser,
                    winEmb: winEmb, loseEmb: loseEmb, shiftA: shiftA, shiftB: shiftB)
        }
        // Drift the (bounded) center to the WINNING candidate's shift — re-center on taste, capped.
        centerShift = pickedA ? shiftA : shiftB
        // Carry the chosen look's per-frame palettes so the export re-encodes the base cube
        // through THEM (ships the chosen look's colours, not the base auto-render).
        surface.chosenLookPalettes = pickedA ? candA : candB
        abPickCount += 1   // bumps `recomputeKey` → `.task` re-fires the next round off-main
        surface.step(pickedA ? .pickA : .pickB)
    }

    /// Append this A/B round to the replay-deterministic decision log (REUSING the existing
    /// `AtlasDecisionLog` spine; Compare is state-identity so no board re-fold is needed). Records
    /// the winner/loser leaf hashes + 770-D embeddings (the taste model) PLUS the honest A/B gene:
    /// the round, which side won, both candidates' Q16 shifts, and the chosen gene
    /// (`abCenterShift` = the winner's shift) + its join hash for the self-describing GIF.
    private func logPick(pickedA: Bool, winner: ABCandidates.Candidate, loser: ABCandidates.Candidate,
                         winEmb: [Double], loseEmb: [Double],
                         shiftA: SIMD3<Int32>, shiftB: SIMD3<Int32>) {
        let winShift = pickedA ? shiftA : shiftB
        let loseShift = pickedA ? shiftB : shiftA
        let winHash = AtlasState.fnv1a32(winner.leaves)
        var rec = AtlasDecisionRecord(.compare(winner: winHash, loser: AtlasState.fnv1a32(loser.leaves)))
        rec.winEmbedding = winEmb.map { Float($0) }   // the record stores the frozen embedding as Float
        rec.loseEmbedding = loseEmb.map { Float($0) }
        rec.abRound = abPickCount
        rec.abPickedA = pickedA
        rec.abWinnerShift = [winShift.x, winShift.y, winShift.z]
        rec.abLoserShift = [loseShift.x, loseShift.y, loseShift.z]
        rec.abCenterShift = [winShift.x, winShift.y, winShift.z]   // the chosen gene
        rec.abChosenGeneHash = winHash
        var log = AtlasDecisionLogStore.load()
        log.entries.append(rec)
        AtlasDecisionLogStore.save(log)
    }

    /// The off-actor compute result — A and B per-frame palettes + frame-0's candidates for the θ
    /// embedding. `Sendable` so it crosses the actor hop. No index cubes: the delta-preserving move
    /// recolours the SAME base cube (coherent shift), so A/B share the structure by design.
    private struct CandidateSet: Sendable {
        let a: [[SIMD3<UInt8>]]; let b: [[SIMD3<UInt8>]]
        let frame0A: ABCandidates.Candidate?; let frame0B: ABCandidates.Candidate?
    }

    /// Snapshot σ on the main actor, run the per-frame isometry-move OFF it, then apply the result.
    /// Cancellation (a rapid pick) is checked before the @State write so a superseded round is
    /// dropped. Always proposes from the FIXED original capture; the round number + the capped
    /// `centerShift` parameterise the bounded, delta-preserving move (no lossy re-centering).
    private func recomputeAsync() async {
        guard Feature.abCandidatePicker, !surface.palettesPerFrame.isEmpty else {
            candA = []; candB = []; candAIdx = []; candBIdx = []; frame0 = nil; return
        }
        let frames = surface.palettesPerFrame
        let n = abPickCount
        let center = centerShift
        let set = await Task.detached(priority: .userInitiated) {
            Self.computeCandidates(frames: frames, pickCount: n, center: center)
        }.value
        guard !Task.isCancelled else { return }
        candA = set.a; candB = set.b
        candAIdx = []; candBIdx = []      // delta-preserving: recolour the base cube, no re-quant
        if let fa = set.frame0A, let fb = set.frame0B { frame0 = (a: fa, b: fb) } else { frame0 = nil }
    }

    /// Per-frame candidate compute (nonisolated — safe off the main actor; pure FFI on value types).
    /// A and B are two SCHEDULED isometry moves off the capture: A nudges +a chroma, B −a chroma, by
    /// the annealed radius (`MoveRadiusSchedule`, wide early → JND floor), both offset by the capped
    /// cumulative `center`. Each move is an exact isometry, so every relative colour delta is
    /// preserved — the same move to all 64 frames keeps the inter-frame deltas too. No degradation.
    nonisolated private static func computeCandidates(frames: [[SIMD3<UInt8>]], pickCount: Int,
                                                      center: SIMD3<Int32>) -> CandidateSet {
        let sep = MoveRadiusSchedule.radius(pickCount) / 2
        let sepV = SIMD3<Int32>(0, sep, 0)
        let moveA = IsoMove.translate(MoveRadiusSchedule.clampToCap(center &+ sepV))
        let moveB = IsoMove.translate(MoveRadiusSchedule.clampToCap(center &- sepV))

        var a = [[SIMD3<UInt8>]](); a.reserveCapacity(frames.count)
        var b = [[SIMD3<UInt8>]](); b.reserveCapacity(frames.count)
        var f0a: ABCandidates.Candidate?; var f0b: ABCandidates.Candidate?
        for (t, pal) in frames.enumerated() {
            guard let pair = ABCandidates.deltaPreservingPair(pal, moveA: moveA, moveB: moveB) else {
                a.append([]); b.append([])
                continue
            }
            a.append(pair.a.rgb)
            b.append(pair.b.rgb)
            if t == 0 { f0a = pair.a; f0b = pair.b }
        }
        return CandidateSet(a: a, b: b, frame0A: f0a, frame0B: f0b)
    }
}
