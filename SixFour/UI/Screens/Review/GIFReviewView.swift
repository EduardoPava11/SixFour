import SwiftUI
import UIKit
import ImageIO

/// Post-capture review — the output side of the I/O appliance. Layout:
///   [ Looping GIF ]
///   [ PaletteStripView ]
///   [ StatsFooterView ]
///   [ Share · Retake ]
///
/// The dither sampler is configured in Settings before capture (it is a
/// statistical property of the form, not a per-shot review choice), so there
/// is no re-render control here — Retake re-shoots, Share exports the GIF.
struct GIFReviewView: View {
    let vm: CaptureViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let primary = vm.primaryOutput {
                singlePanelLayout(primary: primary)
            } else {
                ProgressView().tint(.white)
            }
        }
    }

    @ViewBuilder
    private func singlePanelLayout(primary: CaptureOutput) -> some View {
        VStack(spacing: 14) {
            RenderPanel(output: primary)
                .padding(.horizontal)
            Spacer()
            actionRow(primary: primary)
        }
        .padding(.vertical)
    }

    private func actionRow(primary: CaptureOutput) -> some View {
        HStack(spacing: 14) {
            ShareLink(item: primary.gifURL) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.glassProminent)

            if let contact = primary.contactURL {
                ShareLink(item: contact) {
                    Label("Sheet", systemImage: "square.grid.3x3")
                }
                .buttonStyle(.glass)
                .tint(.cyan)
            }

            Button("Retake") { vm.reset() }
                .buttonStyle(.glass)
                .tint(.white)
        }
        .padding(.horizontal)
    }
}

// MARK: - RenderPanel

/// One GIF + strip + stats group.
private struct RenderPanel: View {
    let output: CaptureOutput

    @State private var frames: [UIImage] = []
    @State private var frameIndex: Int = 0
    @State private var timer: Timer? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            gifImage
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)

            PaletteStripView(palettes: output.palettesForDisplay)
                .padding(.horizontal, 2)

            // ⚠️ EXPERIMENTAL / PARKED spike — the palette-visualization product
            // is the standalone Rust tool (~/Desktop/sixfour-studio), not this.
            // Left wired as a reference; remove if it gets in the way.
            PaletteSphereView(palettes: output.palettesForDisplay)
                .padding(.horizontal, 2)

            StatsFooterView(output: output)
        }
        .task { loadFrames() }
        .onDisappear { timer?.invalidate(); timer = nil }
    }

    @ViewBuilder
    private var gifImage: some View {
        if let img = currentImage {
            Image(uiImage: img)
                .interpolation(.none)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .accessibilityLabel("Rendered GIF, \(output.ditherMethod.label) dither, sixty-four frames at twenty fps")
        } else {
            Rectangle().fill(.white.opacity(0.04))
                .overlay(ProgressView().tint(.white))
        }
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
