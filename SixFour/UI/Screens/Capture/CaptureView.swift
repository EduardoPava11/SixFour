import SwiftUI

struct CaptureView: View {
    @State private var vm = CaptureViewModel()
    @State private var showSettings = false
    @State private var reticle: ReticleHit? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// GRID-FIRST capture (ADR-5): the screen is the GIF → palette → shutter cascade.
    /// Flip to `false` to restore the legacy HUD (title + diversity ring + readout +
    /// CellShutter), which is kept in-tree below.
    private let gridFirstCapture = true

    var body: some View {
        rootContent
            .task { await vm.bootstrap() }
            // Re-sync the live preview's dither when a Settings flip changes the sampler,
            // so a mid-session change isn't stale on the 384pt hero (#2).
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

    /// Switches between the bootstrap skeleton, unauthorized screen,
    /// failure screen, and the normal capture viewport based on `phase`.
    /// Routing here keeps `mainCaptureScene` focused on the happy path.
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
            mainCaptureScene
                .overlay(alignment: .top) { phaseBanner }
        }
    }

    /// The capture HUD is ONE centered column built around the preview anchor:
    /// wordmark (top) · the 64×64 live tile (centred) · shutter+ring · readout.
    /// Every direct child of the VStack is horizontally centred, so the preview
    /// sits dead-centre and the chrome bands above and below it.
    @ViewBuilder
    private var mainCaptureScene: some View {
        if gridFirstCapture { latticeScene } else { legacyScene }
    }

    /// The grid-first capture screen: ONE screen lattice (ScreenLattice), every region
    /// pinned to absolute cell coordinates inside the safe band — no VStack/Spacer, no
    /// second pitch, no bleed under the Dynamic Island. (Audit fix, 2026-06-05.)
    private var latticeScene: some View {
        ZStack(alignment: .topLeading) {
            CellFieldView(tint: vm.sceneGroundTint)   // ground cells fill the screen
                .ignoresSafeArea()
            previewBlock.latticeRegion(ScreenLattice.preview)       // GIF 64² — 384 pt
            livePaletteGrid.latticeRegion(ScreenLattice.palette)    // 256 — 192 pt
            captureShutter.latticeRegion(ScreenLattice.shutter)     // 4×4 Haar — 96 pt
            gearButton.latticeRegion(ScreenLattice.gear)            // settings — 24 pt
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        // Build stamp: the running commit + time, on-glass, so a stale build is
        // visible (SixFour gitignores the .xcodeproj — a pull without `xcodegen
        // generate` ships the old file set). Top-left, below the Dynamic Island.
        .overlay(alignment: .topLeading) {
            CellText("\(BuildStamp.gitSHA) \(BuildStamp.buildTime)", rows: 7,
                     ink: Color(srgb8: SIMD3<UInt8>(120, 120, 132)))
                .padding(.leading, GlobalLattice.pt(3))
                .padding(.top, GlobalLattice.pt(36))   // 72 pt — below the Dynamic Island
                .allowsHitTesting(false)
        }
    }

    /// Legacy floating-VStack HUD (pre-audit; kept behind `gridFirstCapture`).
    private var legacyScene: some View {
        ZStack {
            CellFieldView(tint: vm.sceneGroundTint)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, GlobalLattice.pt(4))
                Spacer(minLength: GlobalLattice.pt(6))
                previewBlock
                if let note = vm.previewSamplerNote {
                    CellText(note, rows: 7, ink: Color(srgb8: SIMD3(130, 130, 130)))
                        .padding(.top, GlobalLattice.pt(2))
                }
                Spacer(minLength: 0)
                if let summary = vm.lastTimingSummary {
                    CellText(summary, rows: 11, ink: .white)
                        .padding(.horizontal, GlobalLattice.pt(5))
                        .padding(.vertical, GlobalLattice.pt(3))
                        .background(Color(srgb8: SFTheme.ledGhost))
                        .padding(.bottom, GlobalLattice.pt(4))
                }
                bottomBar
                    .padding(.horizontal, GlobalLattice.pt(4))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.vertical, GlobalLattice.pt(6))
        }
    }

    /// The settings gear, placed on the lattice (top-right) in the grid-first scene.
    private var gearButton: some View {
        Button { showSettings = true } label: { CellGear() }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel("Open settings")
    }

    /// The canvas: ALWAYS the live 64×64 tile (nearest-neighbour upscaled), never
    /// the raw camera feed — you live inside the 64³ world. The
    /// AVCaptureVideoPreviewLayer rides underneath at opacity 0 purely as the
    /// tap-to-focus + session layer; the tile sits on top with hit-testing off.
    /// The focus reticle is overlaid in the preview's OWN coordinate space, so it
    /// needs no global-offset math (which is what previously skewed the layout).
    private var previewBlock: some View {
        // The 64×64 GIF at the gifPx ATOM — the full-width 384 pt hero (v2.0). Each GIF
        // pixel is 6 pt / 18 device-px: first-class, byte-and-size-identical to Review.
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
            } else {
                Color.black                    // first-frame fallback (~100 ms)
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

    /// The live 256-colour palette as a 16×16 grid (192 pt) — the GIF's first
    /// abstraction, recomputed ~3 fps from the preview tile.
    private var livePaletteGrid: some View {
        let pal = vm.livePalette
        // Frame is a cell-ring (added in the exact-geometry pass), not a vector stroke
        // (GRID: no raw primitives on the HUD).
        return CellSprite(cols: 16, rows: 16, cellPt: 12) { c, r in
            let i = r * 16 + c
            return i < pal.count ? pal[i] : SIMD3<UInt8>(20, 20, 24)
        }
        .accessibilityHidden(true)
    }

    /// The capture button = the 4×4 Haar level-4 abstraction of the live palette
    /// (the third rung of the cascade). Tap to shoot; inert while busy.
    private var captureShutter: some View {
        let busy = isCurrentlyBusy
        let disabled = vm.phase == .configuring || vm.phase == .unauthorized
        return HaarShutterView(
            palette: vm.livePalette.count == 256 ? vm.livePalette : [],
            onTap: (busy || disabled) ? nil : { Task { await vm.capture() } }
        )
    }

    private var topBar: some View {
        // NO TITLE (grid-first, ADR-5): the screen is the GIF + palette + shutter
        // cascade, nothing else. Only the settings gear rides the top-right corner.
        HStack(spacing: GlobalLattice.pt(5)) {
            Spacer()
            Button { showSettings = true } label: {
                CellGear()
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel("Open settings")
        }
    }

    private var bottomBar: some View {
        // The capture screen is holy: the shutter, ringed by the live diversity
        // gauge, with its readout. The shutter does double duty as the
        // instrument that shows how much colour the camera currently sees.
        VStack(spacing: GlobalLattice.pt(5)) {
            ZStack {
                CellDiversityRing(gauge: Double(vm.sceneGauge), tint: vm.sceneGroundTint)
                    .allowsHitTesting(false)
                shutterButton
            }
            diversityReadout
        }
        .padding(.bottom, GlobalLattice.pt(8))
    }

    /// The explicit "show the diversity" number — distinct colour-bins the
    /// camera sees right now, in the machine voice. Surfaced to VoiceOver via
    /// the shutter's `accessibilityValue`, so it's hidden here.
    private var diversityReadout: some View {
        VStack(spacing: GlobalLattice.pt(1)) {
            // The colour count: ◇ diamond icon + a FIXED 3-digit two-ink 7-segment
            // field (golden SixFourSevenSeg) + label. The 7-seg never reflows and the
            // ◇ is a real CellIcon — replacing the old reflowing single-ink CellText
            // with a Unicode glyph (§6.9). Opaque inks only (Law #2: no alpha on a cell).
            HStack(spacing: GlobalLattice.pt(2)) {
                CellIcon.diamond(box: 12, ink: SIMD3<UInt8>(153, 153, 153))
                CellDigits(value: vm.scene.occupiedBins, width: 3)
                CellText(" colors", rows: 13, ink: Color(srgb8: SIMD3<UInt8>(153, 153, 153)))
            }
            // The active sampler — updates the instant a Settings toggle flips
            // (the chrome shows the setting, never inert).
            CellText(samplerTag, rows: 8,
                     ink: Color(srgb8: SIMD3<UInt8>(130, 130, 130)))
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    /// Compact machine-voice description of the active residual sampler,
    /// derived live from `AppSettings`.
    private var samplerTag: String {
        let c = vm.settings.ditherConfig
        switch c.method {
        case .errorDiffusion:
            let k = c.kernel == .floydSteinberg ? "FS" : "Atkinson"
            return "diffusion · \(k) · \(c.serpentine ? "serpentine" : "raster")"
        case .blueNoise:
            return "blue · \(c.temporal == .spatiotemporal ? "3D" : "frozen")"
        }
    }

    @ViewBuilder
    private var shutterButton: some View {
        let isBusy = isCurrentlyBusy
        let isDisabled = vm.phase == .configuring || vm.phase == .unauthorized
        Button {
            Task { await vm.capture() }
        } label: {
            // The shutter as a 34-cell block (68pt) at the one 2pt pitch. Disabled =
            // 2×2 cell checker (Law #2: a state is a cell transform, never opacity).
            CellShutter(busy: isBusy, disabled: isDisabled)
        }
        .disabled(isBusy || isDisabled)
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
        // .unauthorized, .failed, and .configuring route to dedicated
        // full-screen views above; phaseBanner only handles overlays on
        // top of the live capture scene.
        //
        // The deterministic core surfaces its CURRENT stage (quantize → dither →
        // significance → palette → encode) — that granular banner takes priority
        // so the user watches the verified Zig pipeline run, stage by stage.
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
        // Cells, not glass (glass retired on the HUD per GRID): flat dark cell
        // strip behind the stage text at the one 2pt pitch.
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

/// A focus reticle at the user's tap location, drawn as an opaque CELL ring at the
/// 2 pt pitch (GRID §6.10 capture-HUD vocabulary: NO vector `Circle`, NO anti-aliased
/// `.stroke`, NO continuous `.opacity` fade). Its brief appearance is a discrete on→off:
/// stateless, the parent removes it via `.task` after a delay.
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
