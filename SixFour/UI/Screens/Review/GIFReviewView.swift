import SwiftUI
import UIKit

/// Post-capture review — the output side of the I/O appliance. A clean vertical
/// stack (no overlap): the looping GIF, then the palette tool (the 256 colours
/// shown either as the median-cut `SplitTree` treemap or the user-assignable
/// coordinate grid — the verifier you can *see*; chosen via `RepresentationSelector`),
/// then a per-frame status line that proves `256/256 ✓` and surfaces the per-frame
/// numbers, then the actions. The sampler is a Settings decision, so there is no
/// re-render control — Retake re-shoots, Share exports.
struct GIFReviewView: View {
    let vm: CaptureViewModel
    // Reduce-motion is owned by the shared `PlaybackClock` (set in `GIFPlayer`), so
    // the screen no longer reads it directly.
    /// Shared brushed palette slot (IndexedColor.index) — links the cloud's pick
    /// to the other palette views (P1 brushing-and-linking, keyed by index).
    @State private var brushedIndex: Int? = nil
    /// THE single playback clock (docs/SIXFOUR-UNIFIED-PLAYER.md): one cursor drives
    /// the unified 2D/3D `GIFPlayer`, the status line, and every palette analyzer, so
    /// nothing drifts. `count` defaults to `SixFourShape.T` (= 64), the GIF length.
    @State private var clock = PlaybackClock()
    /// Brief "copied" flash after tapping the SHA badge to copy the full hash.
    @State private var shaCopied = false

    /// GRID-FIRST UI/UX (ADR-5 / SIXFOUR-UIUX-DIMENSIONAL-MAP). While we move to the
    /// grid-first surface, the legacy palette-explorer widgets after capture — the
    /// RepresentationSelector and its treemap / cloud / voxel / AddressPicker / Quad4 /
    /// editor modes — are SUSPENDED (kept in-tree, not rendered). Post-capture shows the
    /// GIF hero + the 256-colour palette as the 16×16 grid (its first abstraction).
    /// Flip to `false` to restore the full explorer.
    private let gridFirstReview = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let primary = vm.primaryOutput {
                reviewLayout(primary: primary)
            } else {
                ProgressView().tint(.white)
            }
        }
    }

    private func reviewLayout(primary: CaptureOutput) -> some View {
        // Content scrolls (GIF + palette tool + status are together taller than a
        // 17 Pro screen); actions pin to the bottom so they're always reachable.
        // A plain stack — nothing floats over the GIF, so no overlap.
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: GlobalLattice.pt(7)) {
                    // The unified player: the GIF renders + plays in 2D and 3D as ONE
                    // tool set, on the shared clock, with a GRID transport. Replaces
                    // the old bare GIFCanvas (which owned a private drifting timer).
                    GIFPlayer(output: primary, clock: clock, settings: vm.settings,
                              brushedIndex: $brushedIndex)

                    if gridFirstReview {
                        // Grid-first cascade (ADR-5): GIF (above) → 16×16 palette → 4×4
                        // shutter, each a coarser Haar level of the one before.
                        // 256 = 16² leaves; the shutter is their level-4 parents.
                        PaletteGridView(palettes: primary.palettesForDisplay,
                                        xAxis: vm.settings.gridAxisX,
                                        yAxis: vm.settings.gridAxisY,
                                        frame: clock.frame,
                                        brushedIndex: brushedIndex)
                        let settled = primary.palettesForDisplay.isEmpty
                            ? []
                            : primary.palettesForDisplay[min(clock.settledFrame, primary.palettesForDisplay.count - 1)]
                        if settled.count == 256 {
                            HaarShutterView(palette: settled)   // 4×4 = Haar level-4 (16 colours)
                        }
                    } else if vm.settings.showPaletteTree {
                        paletteStructure(primary)   // SUSPENDED legacy explorer
                    }

                    perFrameStatus(primary)

                    if primary.deterministic, let sha = primary.sha256 {
                        determinismBadge(sha: sha, stageMillis: primary.stageMillis)
                    } else {
                        // Honesty: the SHA badge can't show on the GPU-fallback path, so
                        // make its ABSENCE explicit — a present/absent badge is otherwise a
                        // silent trust signal. Exactly one provenance chip always renders.
                        gpuFallbackChip()
                    }
                }
                .padding(.horizontal)
                .padding(.top)
            }
            actionRow(primary: primary)
                .padding()
        }
        // Self-heal a persisted .voxel3D selection (now retired as a peer, #5).
        .onAppear {
            if vm.settings.paletteRepresentation == .voxel3D {
                vm.settings.paletteRepresentation = .structure
            }
        }
    }

    /// The palette-structure tool, scope-driven:
    /// - `.perFrame` — the 64 per-frame palettes as an animated median-cut treemap (NN input).
    /// - `.global` — the collapsed global palette in the interactive multiresolution editor
    ///   (NN output; you "be the look-NN" by hand).
    /// The glass scope selector floats above; content (treemap/editor) sits beneath.
    @ViewBuilder
    private func paletteStructure(_ o: CaptureOutput) -> some View {
        let branching = Binding(
            get: { vm.settings.paletteBranching },
            set: { vm.settings.paletteBranching = $0 }
        )
        // The palette of the SETTLED frame — used by the median-cut rebuilders
        // (AddressPicker / Quad4), which re-sync only on pause/scrub, never at 20 fps
        // (docs/SIXFOUR-UNIFIED-PLAYER.md decision 2). Continuous analyzers below read
        // the live `clock.frame` instead.
        let settledPalette: [SIMD3<UInt8>] = o.palettesForDisplay.isEmpty
            ? []
            : o.palettesForDisplay[min(clock.settledFrame, o.palettesForDisplay.count - 1)]
        VStack(spacing: GlobalLattice.pt(5)) {
            // Full collapse (#5): voxel3D is no longer a palette-explorer PEER — the
            // 64³ cube is the hero's own 3D pose (GIFPlayer), so the selector offers only
            // the three palette analyzers. A persisted .voxel3D selection self-heals to
            // .structure below.
            RepresentationSelector(selection: Binding(
                get: { vm.settings.paletteRepresentation == .voxel3D ? .structure : vm.settings.paletteRepresentation },
                set: { vm.settings.paletteRepresentation = $0 }
            ), cases: [.structure, .grid, .cloud])
            switch vm.settings.paletteRepresentation {
            case .structure:
                // The median-cut nesting view: scope (per-frame / global) + branching.
                ScopeSelector(selection: Binding(
                    get: { vm.settings.paletteScope },
                    set: { vm.settings.paletteScope = $0 }
                ))
                switch vm.settings.paletteScope {
                case .perFrame:
                    // Synced to the player: the treemap shows the live clock frame.
                    PaletteTreeView(palettes: o.palettesForDisplay,
                                    branching: vm.settings.paletteBranching,
                                    frame: clock.frame)
                    BranchingSelector(selection: branching)
                    // Operable address for the SAME tree: N wheels = the 16²/4⁴/2⁸
                    // digits, each labelled with its real axis@pos split; turning one
                    // brushes that subtree across the views (shared brushedIndex). The
                    // tree rebuilds on the SETTLED frame (pause/scrub), not at 20 fps.
                    AddressPickerView(
                        splitTree: PaletteTreeView.tree(for: settledPalette),
                        branching: vm.settings.paletteBranching,
                        brushedIndex: $brushedIndex)
                case .global:
                    // 4⁴ gets its honest opponent-quadrant drill; 16²/2⁸ use the editor.
                    if vm.settings.paletteBranching == .b4 {
                        Quad4DrillView(palette: settledPalette,
                                       brushedIndex: $brushedIndex)
                    } else {
                        GlobalPaletteEditorView(palettes: o.palettesForDisplay, branching: branching)
                    }
                }
            case .grid:
                // The coordinate view: 256 colours on two user-assigned axes, synced
                // to the live clock frame.
                PaletteGridView(palettes: o.palettesForDisplay,
                                xAxis: vm.settings.gridAxisX,
                                yAxis: vm.settings.gridAxisY,
                                frame: clock.frame,
                                brushedIndex: brushedIndex)
                GridAxisSelector(
                    xAxis: Binding(get: { vm.settings.gridAxisX }, set: { vm.settings.gridAxisX = $0 }),
                    yAxis: Binding(get: { vm.settings.gridAxisY }, set: { vm.settings.gridAxisY = $0 })
                )
            case .cloud:
                // P4 — the OKLab Temporal Cloud: 256 colours at true OKLab coords,
                // orbited (3-D projection) + scrubbed (shared clock time projection).
                PaletteCloudView(palettes: o.palettesForDisplay,
                                 perFrameCells: o.perFrameCells,
                                 splitTree: nil,
                                 branching: vm.settings.paletteBranching,
                                 clock: clock,
                                 brushedIndex: $brushedIndex)
            case .voxel3D:
                // The 64³ (x,y,t) cube the global palette colours — the FULL study cube
                // (provenance / trail / luma / isolate), now sharing the player clock so
                // its front frame matches the 2D GIF. (The GIF hero above also offers a
                // quick 3D toggle; this is the deep-analysis cube.)
                if let data = VoxelCubeData(output: o) {
                    VoxelCubeView(data: data, clock: clock, settings: vm.settings,
                                  brushedIndex: $brushedIndex,
                                  brushMode: BrushSet.mode(vm.settings.paletteBranching),
                                  chrome: .full)
                }
            }
        }
    }

    /// Proves the guarantee and surfaces the per-frame numbers, in the machine voice,
    /// reading the SHARED clock — so the status line cycles in lockstep with the
    /// player and analyzers (no separate `TimelineView`; reduce-motion freeze is owned
    /// by the clock, which pins frame 0).
    private func perFrameStatus(_ o: CaptureOutput) -> some View {
        let n = max(o.palettesForDisplay.count, 1)
        return statusLine(o, frame: min(clock.frame, n - 1), n: n)
    }

    // Fully pixelated status: CellDigits count + CellIcon seal/warn + CellText detail
    // (two cell rows so the detail line fits the screen width). Green/yellow are opaque
    // inks, not opacity (GRID Law #2).
    private func statusLine(_ o: CaptureOutput, frame i: Int, n: Int) -> some View {
        let sig = o.perFrameSignificant.indices.contains(i) ? o.perFrameSignificant[i] : 0
        let cov = o.perFrameCoverage.indices.contains(i) ? o.perFrameCoverage[i] : 0
        let m   = o.perFrameMSE.indices.contains(i) ? o.perFrameMSE[i] : 0
        let full = sig >= 256
        let tint: SIMD3<UInt8> = full ? SIMD3(70, 200, 90) : SIMD3(225, 200, 70)
        let dim = SIMD3<UInt8>(140, 140, 140)
        return VStack(spacing: GlobalLattice.pt(2)) {
            HStack(spacing: GlobalLattice.pt(2)) {
                CellDigits(value: sig, width: 3, lit: tint)
                CellText("/256", rows: 7, ink: Color(srgb8: tint))
                if full { CellIcon.seal(box: 9, ink: tint) } else { CellIcon.warn(box: 9, ink: tint) }
            }
            CellText("frame \(i + 1)/\(n) · \(cov) bins · Q16 MSE \(String(format: "%.4f", m))",
                     rows: 7, ink: Color(srgb8: dim))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(sig) of 256 colours significant, frame \(i + 1) of \(n)")
    }

    /// The reproducibility proof: this GIF came out of the deterministic
    /// fixed-point Zig core, so its bytes are a pure function of the capture —
    /// the same scene + settings always yields this exact SHA-256. The five
    /// stage tags name the verified kernels the bytes flowed through.
    // Fully pixelated proof panel: flat ledGhost cell ground (NO glass), CellIcon.seal +
    // CellText lines. The long pipeline/sha strings use a smaller cell row so they fit
    // the 402pt width without the old minimumScaleFactor/lineLimit. sha stays copyable
    // via the accessibilityLabel (cells can't be text-selected).
    private func determinismBadge(sha: String, stageMillis: [Int]) -> some View {
        let stages = DeterministicRenderer.Stage.allCases
        let pipeline = stages.map(\.tag).joined(separator: " → ")
        let shaShort = sha.count > 16 ? "\(sha.prefix(10))…\(sha.suffix(4))" : sha
        let dim = SIMD3<UInt8>(140, 140, 140)
        let green = SIMD3<UInt8>(70, 200, 90)
        // Per-kernel wall-time: pair each stage tag with its measured ms (#3). Empty
        // until a render supplies it; subordinate to the SHA (timing isn't a proof).
        let timing: String? = stageMillis.count == stages.count
            ? zip(stages, stageMillis).map { "\($0.tag) \($1)ms" }.joined(separator: " · ")
            : nil
        // Tap to copy the FULL 64-char hash so reproducibility can be checked
        // off-device (UIPasteboard is an Apple framework — zero-dep). #4.
        return Button {
            UIPasteboard.general.string = sha
            shaCopied = true
            Task { try? await Task.sleep(for: .seconds(1.4)); shaCopied = false }
        } label: {
            VStack(spacing: GlobalLattice.pt(3)) {
                HStack(spacing: GlobalLattice.pt(2)) {
                    CellIcon.seal(box: 9, ink: green)
                    CellText("DETERMINISTIC CORE", rows: 7, ink: Color(srgb8: SIMD3(225, 225, 225)))
                }
                CellText(pipeline, rows: 6, ink: Color(srgb8: dim))
                if let timing { CellText(timing, rows: 6, ink: Color(srgb8: dim)) }
                CellText(shaCopied ? "sha256 copied ✓" : "sha256 \(shaShort) · tap to copy",
                         rows: 6, ink: Color(srgb8: shaCopied ? green : dim))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, GlobalLattice.pt(5))
            .padding(.horizontal, GlobalLattice.pt(6))
            .background(Color(srgb8: SFTheme.ledGhost))   // flat opaque panel, no glass
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Deterministic core, byte reproducible, SHA-256 \(sha). Double tap to copy the full hash.")
    }

    /// The GPU-fallback provenance chip — shown when a deterministic kernel threw and
    /// the silent GPU path produced the GIF. A valid GIF, but NOT byte-reproducible, so
    /// the absence of the SHA badge is made explicit rather than left as a silent gap.
    private func gpuFallbackChip() -> some View {
        let amber = SIMD3<UInt8>(225, 200, 70)
        let dim = SIMD3<UInt8>(140, 140, 140)
        return VStack(spacing: GlobalLattice.pt(3)) {
            HStack(spacing: GlobalLattice.pt(2)) {
                CellIcon.warn(box: 9, ink: amber)
                CellText("GPU FALLBACK", rows: 7, ink: Color(srgb8: SIMD3(225, 225, 225)))
            }
            CellText("not byte-reproducible · no SHA-256", rows: 6, ink: Color(srgb8: dim))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, GlobalLattice.pt(5))
        .padding(.horizontal, GlobalLattice.pt(6))
        .background(Color(srgb8: SFTheme.ledGhost))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("GPU fallback render, not byte reproducible, no SHA-256")
    }

    // Pixelated action row: flat cell buttons (CellActionButton) instead of glass
    // pills. Share = filled light ground; contact = icon-only; Retake = ledGhost.
    private func actionRow(primary: CaptureOutput) -> some View {
        HStack(spacing: GlobalLattice.pt(GlobalLattice.gutterCells)) {
            ShareLink(item: primary.gifURL) {
                CellActionButton(icon: .share, title: "Share", prominent: true)
            }
            .accessibilityLabel("Share GIF")

            if let contact = primary.contactURL {
                ShareLink(item: contact) {
                    CellActionButton(icon: .grid3x3, fillWidth: false)
                }
                .accessibilityLabel("Share contact sheet")
            }

            Button { vm.reset() } label: {
                CellActionButton(icon: .retake, title: "Retake")
            }
            .accessibilityLabel("Retake")
        }
        .buttonStyle(.plain)
    }
}
