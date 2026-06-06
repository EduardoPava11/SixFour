import SwiftUI

struct CaptureView: View {
    @State private var vm = CaptureViewModel()
    @State private var showSettings = false
    @State private var reticle: ReticleHit? = nil
    @State private var heartbeat = GridHeartbeatClock()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        rootContent
            .task { await vm.bootstrap() }
            // Re-sync the live preview's dither when a Settings flip changes the sampler,
            // so a mid-session change isn't stale on the hero.
            .onChange(of: vm.settings.ditherConfig) { _, _ in vm.syncPreviewDither() }
            .onChange(of: vm.settings.useDeterministicCore) { _, _ in vm.syncPreviewDither() }
            .sheet(isPresented: $showSettings) {
                SettingsView(settings: vm.settings)
            }
            .fullScreenCover(item: Binding(
                get: { vm.primaryOutput },
                set: { newValue in if newValue == nil { vm.primaryOutput = nil } }
            )) { _ in
                GIFReviewView(vm: vm)
            }
    }

    /// Routes the bootstrap skeleton / unauthorized / failure screens, else the live
    /// capture scene with its phase banner overlaid on top.
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
            latticeScene
                .overlay(alignment: .top) { phaseBanner }
        }
    }

    /// The capture screen is ONE screen-grid (`ScreenLattice`): the whole iPhone is a
    /// lattice of `gifPx` cells and every region is pinned to absolute cell coordinates —
    /// no floating `VStack`/`Spacer`, no second pitch. The scene is the GIFA projected:
    /// the 64×64 hero, and the 16×16 live palette — which IS the capture button.
    private var latticeScene: some View {
        ZStack(alignment: .topLeading) {
            // The black ground IS the live grid: a B/W checkerboard of the ONE atom (6 pt
            // — the same cell as a preview pixel and a palette swatch) that inverts at
            // 20 fps, proving the canvas is live. The heroes are EXCLUDED, so the checker
            // frames them without ever crossing; they draw on top via `.latticeRegion`.
            GridRefreshFieldView(phase: heartbeat.phase,
                                 exclude: [ScreenLattice.preview,
                                           ScreenLattice.palette,
                                           ScreenLattice.gear])
                .ignoresSafeArea()
            previewBlock.latticeRegion(ScreenLattice.preview)    // GIF 64² hero (1 atom/cell)
            paletteButton.latticeRegion(ScreenLattice.palette)   // 16×16 @ 1 atom = THE capture button
            gearButton.latticeRegion(ScreenLattice.gear)         // settings — 48 pt
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

    /// The settings gear (top-right of the lattice).
    private var gearButton: some View {
        Button { showSettings = true } label: { CellGear() }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel("Open settings")
    }

    /// The canvas: ALWAYS the live 64×64 tile (nearest-neighbour upscaled), never the raw
    /// camera feed — you live inside the 64³ world. The AVCaptureVideoPreviewLayer rides
    /// underneath at opacity 0 purely as the tap-to-focus + session layer; the tile sits
    /// on top with hit-testing off. The focus reticle is overlaid in the preview's OWN
    /// coordinate space, so it needs no global-offset math.
    ///
    /// FUTURE (UI/UX direction 2026-06-05): the 64² hero must shrink off full-width so it
    /// can rotate to reveal the 64³ cube. Sizing is deferred to its own geometry pass —
    /// it collides with the cube law (1 GIF px = 1 atom = 6 pt) and needs a real decision.
    private var previewBlock: some View {
        // The 64×64 GIF at the gifPx ATOM — the full-width 384 pt hero. Each GIF pixel is
        // 6 pt / 18 device-px: first-class, byte-and-size-identical to Review.
        let side = GlobalLattice.gif(SFTheme.gifSideCells)   // 64 × 6 = 384 pt
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

    /// The 256-colour live palette as a 16×16 grid (96 pt, 1 atom/cell) — the GIF's first abstraction
    /// AND the capture button itself: tap the palette to shoot the 64-frame burst. Colour
    /// + position ARE the button; there is no separate shutter glyph. Inert while the
    /// pipeline is busy or the camera is unavailable (a state is a cell transform, never
    /// opacity — here the grid simply stops being a `Button`).
    private var paletteButton: some View {
        let pal = vm.livePalette
        let busy = isCurrentlyBusy
        let disabled = vm.phase == .configuring || vm.phase == .unauthorized
        let grid = CellSprite(cols: 16, rows: 16, cellPt: GlobalLattice.gif(1)) { c, r in
            let i = r * 16 + c
            return i < pal.count ? pal[i] : SIMD3<UInt8>(20, 20, 24)
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
