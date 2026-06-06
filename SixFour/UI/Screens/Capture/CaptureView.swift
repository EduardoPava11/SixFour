import SwiftUI

struct CaptureView: View {
    @State private var vm = CaptureViewModel()
    @State private var reticle: ReticleHit? = nil
    @State private var heartbeat = GridHeartbeatClock()
    /// THE playback clock for the in-lattice Review hero, owned here (not by the
    /// player) so one surface persists across capture→loading→review without the
    /// player's onAppear/onDisappear churning the clock.
    @State private var playbackClock = PlaybackClock()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        rootContent
            .task { await vm.bootstrap() }
            // Re-sync the live preview's dither when a Settings flip changes the sampler,
            // so a mid-session change isn't stale on the hero.
            .onChange(of: vm.settings.ditherConfig) { _, _ in vm.syncPreviewDither() }
            .onChange(of: vm.settings.useDeterministicCore) { _, _ in vm.syncPreviewDither() }
            // Clock lifecycle owned here (not in the player): run while the in-lattice
            // Review hero is shown, stop on retake — so one persistent surface spans
            // capture→loading→review with no modal swap.
            .onChange(of: vm.primaryOutput == nil) { _, isNil in
                if isNil {
                    playbackClock.stop()
                } else {
                    playbackClock.reduceMotion = reduceMotion
                    playbackClock.start()
                }
            }
    }

    /// Routes the bootstrap skeleton / unauthorized / failure screens, else either the
    /// live capture scene or — once a GIFA exists — the in-lattice Review (no modal
    /// `fullScreenCover` swap, so the 64×64 surface persists capture→loading→review).
    @ViewBuilder
    private var rootContent: some View {
        switch vm.phase {
        case .configuring:
            BootstrapSkeleton()
        case .unauthorized:
            UnauthorizedView()
        case .failed(let msg):
            FailureView(message: msg) {
                Task { await vm.bootstrap() }
            }
        default:
            if vm.primaryOutput != nil {
                ReviewScene(vm: vm, clock: playbackClock)
            } else {
                latticeScene
                    .overlay(alignment: .top) { phaseBanner }
            }
        }
    }

    /// The capture screen is exactly TWO elements on ONE uniform grid (`CaptureGrid`,
    /// 4 pt cell): the 64-cell preview hero (256 pt) and the 16-cell live palette (64 pt)
    /// — which IS the capture button — floating on the live checker. Every cell (preview
    /// pixel, palette swatch, background checker) is the SAME size. No `VStack`/`Spacer`;
    /// each element is `.position`-placed on the cell grid. Settings/other widgets are
    /// deferred (brief: "nothing else"); there is no chrome here but the two heroes.
    private var latticeScene: some View {
        ZStack(alignment: .topLeading) {
            // The black ground IS the live grid: a full B/W checkerboard of the ONE 4 pt
            // capture cell that inverts at 20 fps, proving the canvas is live. The opaque
            // heroes draw ON TOP, so the checker simply tiles the whole screen behind them.
            GridRefreshFieldView(phase: heartbeat.phase)
                .ignoresSafeArea()
            previewBlock.position(CaptureGrid.previewCenter)     // 64 cells = 256 pt
            paletteButton.position(CaptureGrid.paletteCenter)    // 16 cells = 64 pt = THE capture button
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        // The heartbeat clock: copy PlaybackClock's reduce-motion + lifecycle contract.
        // Under reduce-motion the clock never starts → a STATIC opaque B/W checker (grid
        // visibly rendered, no flashing). scenePhase != .active pauses it for zero idle
        // battery.
        .onAppear {
            heartbeat.reduceMotion = reduceMotion
            if scenePhase == .active { heartbeat.start() }
        }
        .onDisappear { heartbeat.stop() }
        .onChange(of: reduceMotion) { _, newValue in
            heartbeat.reduceMotion = newValue
            if !newValue, scenePhase == .active { heartbeat.start() }
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active { heartbeat.start() } else { heartbeat.stop() }
        }
        // Build stamp: the running commit + time, so a stale build is visible (SixFour
        // gitignores the .xcodeproj — a pull without `xcodegen generate` ships the old
        // file set). Top-left, below the Dynamic Island.
        .overlay(alignment: .topLeading) {
            CellText("\(BuildStamp.gitSHA) \(BuildStamp.buildTime)", rows: 7,
                     ink: Color(srgb8: SIMD3<UInt8>(120, 120, 132)))
                .padding(.leading, GlobalLattice.pt(3))
                .padding(.top, GlobalLattice.pt(36))   // 72 pt — below the Dynamic Island
                .allowsHitTesting(false)
        }
    }

    /// The canvas: ALWAYS the live 64×64 tile (nearest-neighbour upscaled), never the raw
    /// camera feed — you live inside the 64³ world. The AVCaptureVideoPreviewLayer rides
    /// underneath at opacity 0 purely as the tap-to-focus + session layer; the tile sits
    /// on top with hit-testing off. The focus reticle is overlaid in the preview's OWN
    /// coordinate space, so it needs no global-offset math.
    ///
    /// The 64² hero renders at the uniform capture cell (4 pt/pixel = 256 pt) — small
    /// enough to clear the rounded corners and to rotate into the 64³ cube for analysis.
    /// Every pixel is the SAME 4 pt cell as a palette swatch and a checker cell.
    private var previewBlock: some View {
        let side = CaptureGrid.pt(CaptureGrid.previewCells)   // 64 × 4 = 256 pt
        return ZStack {
            if let session = vm.session?.session {
                CameraPreview(session: session) { devicePoint, localPoint in
                    vm.focus(at: devicePoint)
                    reticle = ReticleHit(point: localPoint, id: UUID())
                }
                .opacity(0)
            }
            if let img = vm.previewTile {
                PixelImage(image: img, edge: side)
                    .allowsHitTesting(false)   // taps fall through to the focus layer
            }
            // The GIFA build is an on-grid serpentine RESOLVE SWEEP over this surface —
            // not a spinner. As the verified kernels complete, the front advances and
            // reveals the GIFA-in-progress underneath. Continuous at the cell level.
            if isRendering, vm.previewTile != nil {
                GIFAResolveOverlay(progress: vm.loadingProgress, edge: side)
            }
            if let hit = reticle {
                FocusReticle(point: hit.point)
                    .id(hit.id)
                    .allowsHitTesting(false)
                    .task(id: hit.id) {
                        try? await Task.sleep(for: .milliseconds(1000))
                        if reticle?.id == hit.id { reticle = nil }
                    }
            }
        }
        .frame(width: side, height: side)
        .clipped()
    }

    /// The 256-colour live palette as a 16×16 grid (64 pt, 4 pt/cell — the uniform capture cell) — the GIF's first abstraction
    /// AND the capture button itself: tap the palette to shoot the 64-frame burst. Colour
    /// + position ARE the button; there is no separate shutter glyph. Inert while the
    /// pipeline is busy or the camera is unavailable (a state is a cell transform, never
    /// opacity — here the grid simply stops being a `Button`).
    private var paletteButton: some View {
        let pal = vm.livePalette
        let busy = isCurrentlyBusy
        let disabled = vm.phase == .configuring || vm.phase == .unauthorized
        let ghost = SIMD3<UInt8>(20, 20, 24)
        // Place the 256 colours through the centralized GridScript (capture =
        // row-major / identity order, no per-frame re-sort jitter). Pad to a full 256
        // so the order is a total permutation. Both render backends resolve a cell via
        // this one `surfaceColors`, so the layout can't diverge (Spec.GridScript).
        let padded: [SIMD3<UInt8>] = (0 ..< 256).map { $0 < pal.count ? pal[$0] : ghost }
        let ordered = GridScript.capture(side: 16).surfaceColors(palette: padded)
        // During the burst the shutter IS the progress bar: fill the captured fraction
        // of the 256 cells in rank order (a cell transform, not a fade); the rest dim.
        let captured: Int = {
            if case let .capturing(progress) = vm.phase { return Int((progress * 256).rounded()) }
            return 256
        }()
        let grid = CellSprite(cols: 16, rows: 16, cellPt: CaptureGrid.cell) { c, r in
            let rank = r * 16 + c
            guard rank < ordered.count else { return ghost }
            return rank < captured ? ordered[rank] : ghost
        }
        return Group {
            if busy || disabled {
                grid
            } else {
                Button { Task { await vm.capture() } } label: { grid }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
            }
        }
        .accessibilityLabel("Capture 64-frame burst")
        .accessibilityValue("Scene diversity \(Int((vm.sceneGauge * 100).rounded())) percent")
        .accessibilityHint("Holds focus and exposure, captures sixty-four frames at twenty fps")
    }

    private var isCurrentlyBusy: Bool {
        switch vm.phase {
        case .locking, .capturing, .renderingStageA, .renderingEncode:
            return true
        default:
            return false
        }
    }

    /// True while the GIFA is being built (after the burst) — the window the on-grid
    /// serpentine resolve sweep is shown over the preview surface.
    private var isRendering: Bool {
        switch vm.phase {
        case .renderingStageA, .renderingEncode: return true
        default: return false
        }
    }

    @ViewBuilder
    private var phaseBanner: some View {
        // .unauthorized, .failed, and .configuring route to dedicated full-screen views
        // above; phaseBanner only handles overlays on top of the live capture scene.
        //
        // The deterministic core surfaces its CURRENT stage (quantize → dither →
        // significance → palette → encode) — that granular banner takes priority so the
        // user watches the verified Zig pipeline run, stage by stage.
        if let stage = vm.deterministicStage {
            bannerText(stage)
        } else {
            switch vm.phase {
            case .locking:
                bannerText("Locking exposure, focus, white balance…")
            case .renderingStageA:
                bannerText("Building per-frame palettes…")
            case .renderingEncode:
                bannerText("Encoding GIF…")
            default:
                EmptyView()
            }
        }
    }

    private func bannerText(_ s: String) -> some View {
        // Cells, not glass (glass retired on the HUD per GRID): flat dark cell strip
        // behind the stage text at the one pitch.
        CellText(s, rows: 11, ink: .white)
            .padding(.horizontal, GlobalLattice.pt(5))
            .padding(.vertical, GlobalLattice.pt(3))
            .background(Color(srgb8: SFTheme.ledGhost))
            .padding(.top, GlobalLattice.pt(4))
    }

    private struct ReticleHit: Equatable {
        let point: CGPoint
        let id: UUID
    }
}

/// The GIFA-build loading state: an on-grid serpentine "resolve sweep" over the
/// 64×64 preview. Unresolved cells are covered by an opaque ghost; as `progress`
/// 0→1 the front advances in serpentine (boustrophedon) order — the centralized
/// `Order.serpentine` (`Spec.Order`, golden-pinned) — revealing the resolving image
/// underneath. No spinner, no fade: a cell transform, continuous at the cell level.
private struct GIFAResolveOverlay: View {
    let progress: Double
    let edge: CGFloat
    /// slot (row-major) → serpentine sweep rank, computed once.
    private static let sweepRank = Order.serpentine(64).ranks

    var body: some View {
        let resolved = Int((max(0, min(1, progress)) * 4096).rounded())
        let ghost = SIMD3<UInt8>(12, 12, 14)
        CellSprite(cols: 64, rows: 64, cellPt: edge / 64) { c, r in
            // Cover not-yet-resolved cells; resolved cells are transparent so the
            // preview/GIFA underneath shows through.
            Self.sweepRank[r * 64 + c] < resolved ? nil : ghost
        }
        .allowsHitTesting(false)
    }
}

/// A focus reticle at the user's tap location, drawn as an opaque CELL ring at the pitch
/// (GRID §6.10 capture-HUD vocabulary: NO vector `Circle`, NO anti-aliased `.stroke`, NO
/// continuous `.opacity` fade). Its brief appearance is a discrete on→off: stateless, the
/// parent removes it via `.task` after a delay.
private struct FocusReticle: View {
    let point: CGPoint
    private let n = 30   // 30 cells = 60 pt, matching the old reticle diameter

    var body: some View {
        let cx = Double(n) / 2, cy = Double(n) / 2
        CellSprite(cols: n, rows: n) { c, r in
            let d = CellGeom.dist(c, r, cx, cy)
            return (d >= 12 && d <= 14) ? SIMD3<UInt8>(255, 204, 0) : nil   // opaque yellow ring band
        }
        .position(point)
        .accessibilityHidden(true)
    }
}
