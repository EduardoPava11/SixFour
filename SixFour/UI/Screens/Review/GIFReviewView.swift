import SwiftUI
import UIKit
import ImageIO

/// Post-capture review — the output side of the I/O appliance. A clean vertical
/// stack (no overlap): the looping GIF, then the palette globe (the 256 colours
/// as rotatable circles — the verifier you can *see*), then a per-frame status
/// line that proves `256/256 ✓` and surfaces the per-frame numbers, then the
/// actions. The sampler is a Settings decision, so there is no re-render
/// control — Retake re-shoots, Share exports.
struct GIFReviewView: View {
    let vm: CaptureViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        // Content scrolls (GIF + globe + status are together taller than a
        // 17 Pro screen); actions pin to the bottom so they're always reachable.
        // A plain stack — nothing floats over the GIF, so no overlap.
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    // The looping GIF, square, same 64×64 look as the preview.
                    GIFCanvas(output: primary)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: SFTheme.cardCorner))
                        .overlay(
                            RoundedRectangle(cornerRadius: SFTheme.cardCorner)
                                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                        )

                    perFrameStatus(primary)

                    // The palette globe: 256 colours as circles on a rotatable
                    // sphere, breathing through the 64 frames — the verifier you
                    // can see, and the moving-parts look.
                    PaletteSphereView(palettes: primary.palettesForDisplay)
                }
                .padding(.horizontal)
                .padding(.top)
            }
            actionRow(primary: primary)
                .padding()
        }
    }

    /// Proves the guarantee and surfaces the per-frame numbers, in the machine
    /// voice, cycling with the loop (frozen on frame 0 under reduce-motion).
    @ViewBuilder
    private func perFrameStatus(_ o: CaptureOutput) -> some View {
        let n = max(o.palettesForDisplay.count, 1)
        if reduceMotion {
            statusLine(o, frame: 0, n: n)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
                let i = Int((ctx.date.timeIntervalSinceReferenceDate * 20).rounded(.down)) % n
                statusLine(o, frame: i, n: n)
            }
        }
    }

    private func statusLine(_ o: CaptureOutput, frame i: Int, n: Int) -> some View {
        let sig = o.perFrameSignificant.indices.contains(i) ? o.perFrameSignificant[i] : 0
        let cov = o.perFrameCoverage.indices.contains(i) ? o.perFrameCoverage[i] : 0
        let m   = o.perFrameMSE.indices.contains(i) ? o.perFrameMSE[i] : 0
        let full = sig >= 256
        return HStack(spacing: 8) {
            HStack(spacing: 3) {
                Text("\(sig)/256")
                Image(systemName: full ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
            }
            .foregroundStyle(full ? Color.green : Color.yellow)
            Text("·").foregroundStyle(SFTheme.dimText)
            Text("frame \(i + 1)/\(n) · \(cov) bins · mse \(String(format: "%.4f", m))")
                .foregroundStyle(SFTheme.dimText)
        }
        .font(SFTheme.captionMono)
        .monospacedDigit()
        .accessibilityLabel("\(sig) of 256 colours significant, frame \(i + 1) of \(n)")
    }

    private func actionRow(primary: CaptureOutput) -> some View {
        HStack(spacing: 12) {
            ShareLink(item: primary.gifURL) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.glassProminent)

            if let contact = primary.contactURL {
                ShareLink(item: contact) {
                    Image(systemName: "square.grid.3x3")
                        .accessibilityLabel("Share contact sheet")
                }
                .buttonStyle(.glass)
            }

            Button("Retake") { vm.reset() }
                .buttonStyle(.glass)
        }
        .lineLimit(1)
        .controlSize(.large)
        .tint(.white)
    }
}

// MARK: - GIFCanvas

/// The looping GIF, played frame-by-frame at 20 fps. Nearest-neighbour
/// upscaled so the 64×64 pixels stay hard. Freezes on frame 0 under reduce-motion.
private struct GIFCanvas: View {
    let output: CaptureOutput

    @State private var frames: [UIImage] = []
    @State private var frameIndex: Int = 0
    @State private var timer: Timer? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let img = currentImage {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("Rendered GIF, \(output.ditherMethod.label) dither, sixty-four frames at twenty fps")
            } else {
                Rectangle().fill(.white.opacity(0.04))
                    .overlay(ProgressView().tint(.white))
            }
        }
        .task { loadFrames() }
        .onDisappear { timer?.invalidate(); timer = nil }
    }

    private var currentImage: UIImage? {
        guard !frames.isEmpty else { return nil }
        return frames[frameIndex % frames.count]
    }

    private func loadFrames() {
        guard frames.isEmpty,
              let src = CGImageSourceCreateWithURL(output.gifURL as CFURL, nil) else { return }
        let count = CGImageSourceGetCount(src)
        var imgs: [UIImage] = []
        imgs.reserveCapacity(count)
        for i in 0..<count {
            if let cg = CGImageSourceCreateImageAtIndex(src, i, nil) {
                imgs.append(UIImage(cgImage: cg))
            }
        }
        self.frames = imgs
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        guard !reduceMotion else {
            frameIndex = 0
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { _ in
            Task { @MainActor in
                frameIndex = (frameIndex + 1) % max(1, frames.count)
            }
        }
    }
}
