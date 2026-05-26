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
            let side = min(proxy.size.width, proxy.size.height)
            let previewYOffset = (proxy.size.height - side) / 2
            ZStack {
                Color.black.ignoresSafeArea()

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
                            Image(uiImage: img)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFill()
                                .allowsHitTesting(false)   // taps fall through to focus layer
                        } else {
                            // First-frame fallback — black until the preview
                            // path delivers its first tile (~100 ms).
                            Color.black
                        }
                    }
                    .frame(width: side, height: side)
                    .clipped()
                    .overlay(
                        Rectangle()
                            .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                    )
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
            Text("SixFour")
                .font(.system(.title2, design: .monospaced, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            // Floating glass control cluster. The two buttons share one
            // GlassEffectContainer sampling region (no glass-on-glass
            // artifacts). To add a future control — e.g. a Settings gear —
            // append one more GlassIconButton here; no extra glass plumbing.
            GlassToolbarCluster {
                // Settings is the only chrome control: the canvas is always
                // the 64×64 tile (no preview mode to toggle), and the sampler
                // lives in Settings. The button tint reflects the live scene.
                GlassIconButton(
                    systemImage: "gearshape",
                    accessibilityLabel: "Open settings",
                    tint: vm.sceneTint
                ) {
                    showSettings = true
                }
            }
        }
    }

    private var bottomBar: some View {
        // The capture screen is holy: the shutter, ringed by the live diversity
        // gauge, with its readout. The shutter does double duty as the
        // instrument that shows how much colour the camera currently sees.
        VStack(spacing: 10) {
            ZStack {
                DiversityRing(gauge: vm.sceneGauge, tint: vm.sceneTint, reduceMotion: reduceMotion)
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
            Text("◇ \(vm.scene.occupiedBins) colors")
                .font(SFTheme.captionMono)
                .foregroundStyle(SFTheme.dimText)
                .monospacedDigit()
                .contentTransition(.numericText())
            // The active sampler — updates the instant a Settings toggle flips
            // (the chrome shows the setting, never inert).
            Text(samplerTag)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(SFTheme.dimText.opacity(0.85))
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
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 84, height: 84)
                Circle()
                    .fill(isBusy ? Color.red.opacity(0.7) : .white)
                    .frame(width: 70, height: 70)
                if vm.phase == .locking || isCurrentlyRendering {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
            }
        }
        .disabled(isBusy || vm.phase == .configuring || vm.phase == .unauthorized)
        .accessibilityLabel("Capture 64-frame burst")
        .accessibilityValue("Scene diversity \(Int((vm.sceneGauge * 100).rounded())) percent")
        .accessibilityHint("Holds focus and exposure, captures sixty-four frames at twenty fps")
    }

    /// The live diversity gauge that rings the shutter: 64 ticks (the form's
    /// frame count), lit clockwise from the top in proportion to how much
    /// distinct colour the camera currently sees, glowing the scene's dominant
    /// hue. Decorative — never captures taps.
    private struct DiversityRing: View {
        let gauge: Float      // 0…1
        let tint: Color
        let reduceMotion: Bool

        var body: some View {
            let total = SFTheme.diversityTickCount
            let lit = max(0, min(total, Int((gauge * Float(total)).rounded())))
            let radius = SFTheme.diversityRingDiameter / 2 + SFTheme.diversityTickLength / 2 + 4
            ZStack {
                ForEach(0..<total, id: \.self) { i in
                    Capsule()
                        .fill(i < lit ? tint : SFTheme.hairline)
                        .frame(width: SFTheme.diversityTickWidth, height: SFTheme.diversityTickLength)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(Double(i) / Double(total) * 360))
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: lit)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: tint)
        }
    }

    private var isCurrentlyBusy: Bool {
        switch vm.phase {
        case .locking, .capturing, .renderingStageA, .renderingEncode:
            return true
        default:
            return false
        }
    }

    private var isCurrentlyRendering: Bool {
        switch vm.phase {
        case .renderingStageA, .renderingEncode: return true
        default: return false
        }
    }

    @ViewBuilder
    private var phaseBanner: some View {
        // .unauthorized, .failed, and .configuring route to dedicated
        // full-screen views above; phaseBanner only handles overlays on
        // top of the live capture scene.
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

    private func bannerText(_ s: String) -> some View {
        Text(s)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: Capsule())
            .padding(.top, 8)
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
