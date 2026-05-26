import SwiftUI

struct CaptureView: View {
    /// Preview mode for the camera viewport. .fullRes shows the
    /// AVCaptureVideoPreviewLayer at sensor resolution (the framing
    /// reference). .pixelated shows the 64×64 OKLab tile rendered
    /// through the actual capture pipeline, upscaled with
    /// nearest-neighbour so the user sees exactly what the GIF will
    /// look like. Toggle button in the top bar switches between them.
    enum PreviewMode { case fullRes, pixelated }

    @State private var vm = CaptureViewModel()
    @State private var showSettings = false
    @State private var reticle: ReticleHit? = nil
    @State private var previewMode: PreviewMode = .fullRes
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

                // Square camera preview, centered. .resizeAspectFill in CameraPreview
                // means we see the central crop of the 4K sensor frame, which matches
                // (within 1%) the actual integer-multiple crop we ship to Metal.
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
                            .opacity(previewMode == .fullRes ? 1 : 0)
                            // The pixelated preview overlay rides on top
                            // when the user toggles to .pixelated. It's
                            // the same 64×64 OKLab tile the burst pipeline
                            // produces, rendered through CGImage with
                            // nearest-neighbour upscaling for the
                            // unmistakable 64×64 look.
                            if previewMode == .pixelated {
                                if let img = vm.previewTile {
                                    Image(uiImage: img)
                                        .interpolation(.none)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    // First-frame fallback — black until
                                    // the preview path delivers its
                                    // first tile (~100 ms after bootstrap).
                                    Color.black
                                }
                            }
                        } else {
                            Rectangle().fill(.black)
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
                // Preview toggle — swaps the full-res camera preview for
                // the live 64×64 downsampled tile (the actual GIF look,
                // upscaled with nearest-neighbour). Icon flips between a
                // sharp-edged camera and a pixel grid; the swap animates
                // via the symbol-replace transition baked into
                // GlassIconButton, driven by the withAnimation below.
                GlassIconButton(
                    systemImage: previewMode == .fullRes
                        ? "squareshape.split.2x2"
                        : "camera",
                    accessibilityLabel: previewMode == .fullRes
                        ? "Switch to 64×64 pixelated preview"
                        : "Switch to full-resolution preview",
                    tint: vm.sceneTint
                ) {
                    withAnimation(.snappy) {
                        previewMode = (previewMode == .fullRes) ? .pixelated : .fullRes
                    }
                }
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
        Text("◇ \(vm.scene.occupiedBins) colors")
            .font(SFTheme.captionMono)
            .foregroundStyle(SFTheme.dimText)
            .monospacedDigit()
            .contentTransition(.numericText())
            .accessibilityHidden(true)
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
