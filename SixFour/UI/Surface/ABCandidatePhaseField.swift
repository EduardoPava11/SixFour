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
                        hero(palettes: candA, label: "A") { pick(a: true) }
                        hero(palettes: candB, label: "B") { pick(a: false) }
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
        .onAppear(perform: recompute)
        // Recompute the pair when the committed palette series changes (a fresh capture).
        .onChange(of: surface.palettesPerFrame.count) { _, _ in recompute() }
    }

    /// "PICK A LOOK · ROUND n" — the game progress.
    private var headerText: String { "PICK A LOOK · ROUND \(abPickCount + 1)" }

    // MARK: - The two GIF heroes (each a 64×64 cell loop at σ.cursor)

    /// One candidate hero: the GIF playing as a flat 64×64 cell loop at the κ cursor, read
    /// through THIS candidate's per-frame palette via `surface.indexCube`. Tapping it IS the
    /// pick. `nil` cells (out-of-range cursor / palette) fall through to the live ground.
    private func hero(palettes: [[SIMD3<UInt8>]], label: String, _ onPick: @escaping () -> Void) -> some View {
        let t = surface.cursor
        let base = t * side * side
        let pal = (t >= 0 && t < palettes.count) ? palettes[t] : []
        return Button(action: onPick) {
            VStack(spacing: GlobalLattice.pt(1)) {
                CellSprite(cols: side, rows: side, cellPt: heroCellPt) { c, r in
                    let offset = base + r * side + c
                    guard offset >= 0, offset < surface.indexCube.count else { return nil }
                    let i = Int(surface.indexCube[offset])
                    guard i >= 0, i < pal.count else { return nil }
                    return pal[i]
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
        abPickCount += 1
        recompute()
        surface.step(pickedA ? .pickA : .pickB)
    }

    /// Recompute the per-frame candidate palettes from the committed per-frame series tinted
    /// by the current θ — A and B are the orthogonal `GenomePair` pair for each frame. Cheap
    /// enough to run all 64 frames on every pick. Stores frame-0's candidates for the embedding.
    private func recompute() {
        guard Feature.abCandidatePicker else { candA = []; candB = []; frame0 = nil; return }
        let frames = surface.palettesPerFrame
        guard !frames.isEmpty else { candA = []; candB = []; frame0 = nil; return }

        var a = [[SIMD3<UInt8>]](); a.reserveCapacity(frames.count)
        var b = [[SIMD3<UInt8>]](); b.reserveCapacity(frames.count)
        var first: (a: ABCandidates.Candidate, b: ABCandidates.Candidate)?
        for (t, pal) in frames.enumerated() {
            guard let pair = ABCandidates.fromPalette(pal, theta: abTheta) else {
                // FFI failure on this frame: empty palettes ⇒ this frame falls through to ground.
                a.append([]); b.append([])
                continue
            }
            a.append(pair.a.rgb)
            b.append(pair.b.rgb)
            if t == 0 { first = pair }
        }
        candA = a
        candB = b
        frame0 = first
    }
}
