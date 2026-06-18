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
    /// The per-frame candidate INDEX cubes (64 × 4096), re-quantized from the original pixels
    /// against each candidate's displaced palette (P3 — genome shapes the bytes, so A and B are
    /// genuinely different cubes). Empty ⇒ the hero falls back to recolouring `surface.indexCube`.
    @State private var candAIdx: [[UInt8]] = []
    @State private var candBIdx: [[UInt8]] = []
    /// Frame-0's candidate objects — their Q16 `.leaves` are the `btUpdate` embedding when a
    /// look wins/loses (matching `ReviewPhaseField`, which embeds from `palettesPerFrame.first`).
    @State private var frame0: (a: ABCandidates.Candidate, b: ABCandidates.Candidate)?

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
        if let cands = frame0 {
            let winner = pickedA ? cands.a : cands.b
            let loser  = pickedA ? cands.b : cands.a
            abTheta = PersonalTaste.btUpdate(
                theta: abTheta,
                winner: PersonalTaste.embedding(leaves: winner.leaves),
                loser:  PersonalTaste.embedding(leaves: loser.leaves))
            PersonalTasteStore.save(abTheta)
        }
        // Carry the chosen look's per-frame palettes so the export re-encodes the base cube
        // through THEM (ships the chosen genome's colours, not the base auto-render).
        surface.chosenLookPalettes = pickedA ? candA : candB
        abPickCount += 1   // bumps `recomputeKey` → `.task` re-fires the next round off-main
        surface.step(pickedA ? .pickA : .pickB)
    }

    /// The off-actor compute result — A and B per-frame palettes + re-quantized index cubes,
    /// plus frame-0's candidates for the θ embedding. `Sendable` so it crosses the actor hop.
    private struct CandidateSet: Sendable {
        let a: [[SIMD3<UInt8>]]; let b: [[SIMD3<UInt8>]]
        let ai: [[UInt8]]; let bi: [[UInt8]]
        let frame0A: ABCandidates.Candidate?; let frame0B: ABCandidates.Candidate?
    }

    /// Snapshot σ on the main actor, run the heavy per-frame FFI OFF it, then apply the result.
    /// Cancellation (a rapid pick) is checked before the @State write so a superseded round is
    /// dropped. Empty inputs / the gate off ⇒ clears the caches (the hero shows the ground).
    private func recomputeAsync() async {
        guard Feature.abCandidatePicker, !surface.palettesPerFrame.isEmpty else {
            candA = []; candB = []; candAIdx = []; candBIdx = []; frame0 = nil; return
        }
        let frames = surface.palettesPerFrame
        let pixels = surface.framePixelsQ16
        let theta = abTheta
        let set = await Task.detached(priority: .userInitiated) {
            Self.computeCandidates(frames: frames, pixels: pixels, theta: theta)
        }.value
        guard !Task.isCancelled else { return }
        candA = set.a; candB = set.b
        candAIdx = set.ai; candBIdx = set.bi
        if let fa = set.frame0A, let fb = set.frame0B { frame0 = (a: fa, b: fb) } else { frame0 = nil }
    }

    /// Per-frame candidate compute (nonisolated — safe off the main actor; pure FFI on value
    /// types). For each frame: the orthogonal `GenomePair` pair tinted by θ → A/B palettes, then
    /// RE-QUANTIZE the original pixels against each candidate's leaves (`s4_dither_frame`) so A
    /// and B are genuinely different index cubes (P3). No retained pixels ⇒ empty index frame
    /// (the hero recolours the shared base cube).
    nonisolated private static func computeCandidates(frames: [[SIMD3<UInt8>]], pixels: [[Int32]],
                                                      theta: [Double]) -> CandidateSet {
        var a = [[SIMD3<UInt8>]](); a.reserveCapacity(frames.count)
        var b = [[SIMD3<UInt8>]](); b.reserveCapacity(frames.count)
        var ai = [[UInt8]](); ai.reserveCapacity(frames.count)
        var bi = [[UInt8]](); bi.reserveCapacity(frames.count)
        var f0a: ABCandidates.Candidate?; var f0b: ABCandidates.Candidate?
        for (t, pal) in frames.enumerated() {
            guard let pair = ABCandidates.fromPalette(pal, theta: theta) else {
                a.append([]); b.append([]); ai.append([]); bi.append([])
                continue
            }
            a.append(pair.a.rgb)
            b.append(pair.b.rgb)
            if t < pixels.count, !pixels[t].isEmpty {
                let cA = pair.a.leaves.flatMap { [$0.x, $0.y, $0.z] }
                let cB = pair.b.leaves.flatMap { [$0.x, $0.y, $0.z] }
                ai.append(SixFourNative.ditherFrame(oklabQ16: pixels[t], centroids: cA, k: 256,
                                                    mode: 0, serpentine: false, stbnSlice: nil) ?? [])
                bi.append(SixFourNative.ditherFrame(oklabQ16: pixels[t], centroids: cB, k: 256,
                                                    mode: 0, serpentine: false, stbnSlice: nil) ?? [])
            } else {
                ai.append([]); bi.append([])
            }
            if t == 0 { f0a = pair.a; f0b = pair.b }
        }
        return CandidateSet(a: a, b: b, ai: ai, bi: bi, frame0A: f0a, frame0B: f0b)
    }
}
