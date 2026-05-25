import SwiftUI
import UIKit
import ImageIO

/// Post-capture review. Single-render layout:
///   [ Looping GIF ]
///   [ PaletteStripView ]
///   [ StatsFooterView ]
///   [ Optional fallback banner ]
///   [ Save · Share · Retake ]
///
/// To compare algorithms (K-means / Wu / Octree) on the same scene, use the
/// in-place re-extract path (`CaptureViewModel.reExtract`) — the cached burst
/// is re-quantized without re-shooting.
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
            // Edit affordance: re-extract from the cached bundle
            // using a different algorithm family. No re-capture
            // needed; the raw OKLab tiles are kept in
            // `vm.currentBundle`. Disabled during in-flight
            // re-extraction so the user can't queue multiple.
            ditherEditPicker(primary: primary)
            actionRow(primary: primary)
        }
        .padding(.vertical)
    }

    /// Segmented picker bound to the current output's dither method.
    /// On change → `vm.reExtract` re-renders the cached `currentBundle.tiles`
    /// with the new dither (no re-capture). Lets the user A/B the two looks
    /// on the same scene; the extraction algorithm is fixed at Wu+KM.
    @ViewBuilder
    private func ditherEditPicker(primary: CaptureOutput) -> some View {
        VStack(spacing: 4) {
            Text("Edit · Dither")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
            Picker("Re-render dither", selection: Binding(
                get: { primary.ditherMethod },
                set: { newMethod in
                    Task { await vm.reExtract(with: newMethod) }
                }
            )) {
                ForEach(DitherMethod.allCases, id: \.self) { method in
                    Text(method.label).tag(method)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isReRendering)
            .frame(maxWidth: 320)
        }
        .padding(.horizontal)
    }

    /// Whether a re-extraction is currently in flight. We watch
    /// `vm.phase` because `reExtract` uses the same render-stage
    /// enum as the initial capture path.
    private var isReRendering: Bool {
        switch vm.phase {
        case .renderingStageA, .renderingEncode: return true
        default: return false
        }
    }

    private func actionRow(primary: CaptureOutput) -> some View {
        HStack(spacing: 14) {
            // Undo button — appears whenever the user has at least
            // one edit on top of the initial render. Disabled when
            // vm.canUndo is false; tap restores the previous render.
            Button {
                vm.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.glass)
            .tint(.white)
            .disabled(!vm.canUndo || isReRendering)
            .accessibilityLabel("Undo edit (\(vm.editCount - 1) edit\(vm.editCount == 2 ? "" : "s") in history)")

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
