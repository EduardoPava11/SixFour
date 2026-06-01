import SwiftUI

struct CaptureView: View {
    @State private var vm = CaptureViewModel()
    @State private var showSettings = false
    @State private var reticle: ReticleHit? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        rootContent
            .task { await vm.bootstrap() }
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

    private var mainCaptureScene: some View {
        GeometryReader { proxy in
            // Preview = 64 cells at the global lattice pitch = 128pt (the locked
            // small hero; the fine cell makes room for high-res cell widgets).
            let side = 64 * SFTheme.cellPt
            let previewYOffset = (proxy.size.height - side) / 2
            ZStack {
                // The whole screen tiled with cells on the 201×437 @2pt lattice,
                // tinted by the live camera (docs/cell-lattice-widget-spec.md).
                CellFieldView(tint: vm.sceneGroundTint)

                // The canvas: ALWAYS the live 64×64 tile (nearest-neighbour
                // upscaled), never the raw camera feed — you live inside the
                // 64³ world. The AVCaptureVideoPreviewLayer is kept at
                // opacity 0 purely as the tap-to-focus + session layer; the
                // tile rides on top with hit-testing off so taps reach it.
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ZStack {
                        if let session = vm.session?.session {
                            CameraPreview(session: session) { devicePoint, localPoint in
                                vm.focus(at: devicePoint)
                                let absolutePoint = CGPoint(
                                    x: localPoint.x + (proxy.size.width - side) / 2,
                                    y: localPoint.y + previewYOffset
                                )
                                reticle = ReticleHit(point: absolutePoint, id: UUID())
                            }
                            .opacity(0)
                        }
                        if let img = vm.previewTile {
                            PixelImage(image: img, edge: side)
                                .allowsHitTesting(false)   // taps fall through to focus layer
                        } else {
                            // First-frame fallback — black until the preview
                            // path delivers its first tile (~100 ms).
                            Color.black
                        }
                    }
                    .frame(width: side, height: side)
                    .clipped()
                    // No hard frame — the 64×64 canvas dissolves into the
                    // palette-washed background (the design-language blend).
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let hit = reticle {
                    FocusReticle(point: hit.point)
                        .id(hit.id)
                        .allowsHitTesting(false)
                        .task(id: hit.id) {
                            try? await Task.sleep(for: .milliseconds(1000))
                            await MainActor.run {
                                if reticle?.id == hit.id { reticle = nil }
                            }
                        }
                }

                VStack {
                    topBar
                    Spacer()
                    if let summary = vm.lastTimingSummary {
                        GlassInfoChip(cornerRadius: 6) {
                            Text(summary)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.horizontal)
                    }
                    bottomBar
                }
                .padding()
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            // Title as lattice cells — the SAME 2pt cell as the preview + field.
            CellText("SixFour", rows: 24, ink: .white.opacity(0.9))
            Spacer()
            // Settings — a 24-cell gear (48pt). Glass is retired on the capture
            // HUD per GRID; the gear is cells at the one 2pt pitch, like everything.
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
        VStack(spacing: 10) {
            ZStack {
                CellDiversityRing(gauge: Double(vm.sceneGauge), tint: vm.sceneGroundTint)
                    .allowsHitTesting(false)
                shutterButton
            }
            diversityReadout
        }
        .padding(.bottom, 16)
    }

    /// The explicit "show the diversity" number — distinct colour-bins the
    /// camera sees right now, in the machine voice. Surfaced to VoiceOver via
    /// the shutter's `accessibilityValue`, so it's hidden here.
    private var diversityReadout: some View {
        VStack(spacing: 2) {
            // Readout as lattice cells — same 2pt cell as everything else.
            CellText("◇ \(vm.scene.occupiedBins) colors", rows: 14, ink: SFTheme.dimText)
            // The active sampler — updates the instant a Settings toggle flips
            // (the chrome shows the setting, never inert).
            CellText(samplerTag, rows: 11, ink: SFTheme.dimText.opacity(0.85))
        }
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
        Button {
            Task { await vm.capture() }
        } label: {
            // The shutter as a 34-cell block (68pt) at the one 2pt pitch.
            CellShutter(busy: isBusy)
        }
        .disabled(isBusy || vm.phase == .configuring || vm.phase == .unauthorized)
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
            .padding(.horizontal, 5 * SFTheme.cellPt)
            .padding(.vertical, 3 * SFTheme.cellPt)
            .background(Color(srgb8: SFTheme.ledGhost))
            .padding(.top, 4 * SFTheme.cellPt)
    }

    private struct ReticleHit: Equatable {
        let point: CGPoint
        let id: UUID
    }
}

/// A small focus reticle that briefly animates at the user's tap location.
/// Stateless; the parent removes it via .task after a delay.
private struct FocusReticle: View {
    let point: CGPoint
    @State private var scale: CGFloat = 1.6
    @State private var opacity: Double = 1.0

    var body: some View {
        Circle()
            .stroke(Color.yellow, lineWidth: 2)
            .frame(width: 60, height: 60)
            .scaleEffect(scale)
            .opacity(opacity)
            .position(point)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25)) { scale = 1.0 }
                withAnimation(.easeOut(duration: 0.9).delay(0.1)) { opacity = 0.0 }
            }
    }
}
