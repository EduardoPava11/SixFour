import SwiftUI

struct CaptureView: View {
    @State private var vm = CaptureViewModel()
    @State private var showCompose = false
    @State private var reticle: ReticleHit? = nil

    var body: some View {
        rootContent
            .task { await vm.bootstrap() }
            .sheet(isPresented: $showCompose) {
                if let store = vm.store {
                    ComposeView(store: store, composition: $vm.composition)
                }
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
                    if let session = vm.session?.session {
                        CameraPreview(session: session) { devicePoint, localPoint in
                            vm.focus(at: devicePoint)
                            let absolutePoint = CGPoint(
                                x: localPoint.x + (proxy.size.width - side) / 2,
                                y: localPoint.y + previewYOffset
                            )
                            reticle = ReticleHit(point: absolutePoint, id: UUID())
                        }
                        .frame(width: side, height: side)
                        .clipped()
                        .overlay(
                            Rectangle()
                                .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                        )
                    } else {
                        Rectangle()
                            .fill(.black)
                            .frame(width: side, height: side)
                    }
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
                        Text(summary)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(8)
                            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                            .padding(.horizontal)
                    }
                    bottomBar
                }
                .padding()
            }
        }
    }

    private var topBar: some View {
        HStack {
            Text("SixFour")
                .font(.system(.title2, design: .monospaced, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            Button {
                showCompose = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Open advanced composition settings")
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            // The mode selector is the primary creative control. Three honest
            // endpoints of the Sinkhorn spectrum — Per-frame (θ=0), Shared
            // (θ≈0.05), Global (θ→∞ via log-domain). See spec/MATH.md
            // Theorems 1, §3.bis, 2.
            ModeSelector(selection: vm.paletteModeBinding)
                .frame(maxWidth: 320)

            HStack {
                Spacer()
                shutterButton
                Spacer()
            }
        }
        .padding(.bottom, 16)
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
        .accessibilityHint("Holds focus and exposure, captures sixty-four frames at twenty fps")
    }

    private var isCurrentlyBusy: Bool {
        switch vm.phase {
        case .locking, .capturing, .renderingStageA, .renderingStageB, .renderingEncode:
            return true
        default:
            return false
        }
    }

    private var isCurrentlyRendering: Bool {
        switch vm.phase {
        case .renderingStageA, .renderingStageB, .renderingEncode: return true
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
            bannerText("Locking exposure, focus, white balance…", tint: .black)
        case .renderingStageA:
            bannerText("Stage A: per-frame palettes…", tint: .black)
        case .renderingStageB:
            bannerText("Stage B: Sinkhorn merge…", tint: .black)
        case .renderingEncode:
            bannerText("Encoding GIF…", tint: .black)
        default:
            EmptyView()
        }
    }

    private func bannerText(_ s: String, tint: Color) -> some View {
        Text(s)
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(tint.opacity(0.6), in: Capsule())
            .foregroundStyle(.white)
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
