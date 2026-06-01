import SwiftUI
import UIKit
import ImageIO

/// Post-capture review — the output side of the I/O appliance. A clean vertical
/// stack (no overlap): the looping GIF, then the palette tool (the 256 colours
/// shown either as the median-cut `SplitTree` treemap or the user-assignable
/// coordinate grid — the verifier you can *see*; chosen via `RepresentationSelector`),
/// then a per-frame status line that proves `256/256 ✓` and surfaces the per-frame
/// numbers, then the actions. The sampler is a Settings decision, so there is no
/// re-render control — Retake re-shoots, Share exports.
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
        // Content scrolls (GIF + palette tool + status are together taller than a
        // 17 Pro screen); actions pin to the bottom so they're always reachable.
        // A plain stack — nothing floats over the GIF, so no overlap.
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    // The looping GIF, square, same 64×64 look as the preview.
                    GIFCanvas(output: primary)
                        .pixelFrame()

                    if vm.settings.showPaletteTree {
                        paletteStructure(primary)
                    }

                    perFrameStatus(primary)

                    if primary.deterministic, let sha = primary.sha256 {
                        determinismBadge(sha: sha)
                    }
                }
                .padding(.horizontal)
                .padding(.top)
            }
            actionRow(primary: primary)
                .padding()
        }
    }

    /// The palette-structure tool, scope-driven:
    /// - `.perFrame` — the 64 per-frame palettes as an animated median-cut treemap (NN input).
    /// - `.global` — the collapsed global palette in the interactive multiresolution editor
    ///   (NN output; you "be the look-NN" by hand).
    /// The glass scope selector floats above; content (treemap/editor) sits beneath.
    @ViewBuilder
    private func paletteStructure(_ o: CaptureOutput) -> some View {
        let branching = Binding(
            get: { vm.settings.paletteBranching },
            set: { vm.settings.paletteBranching = $0 }
        )
        VStack(spacing: 10) {
            RepresentationSelector(selection: Binding(
                get: { vm.settings.paletteRepresentation },
                set: { vm.settings.paletteRepresentation = $0 }
            ))
            switch vm.settings.paletteRepresentation {
            case .structure:
                // The median-cut nesting view: scope (per-frame / global) + branching.
                ScopeSelector(selection: Binding(
                    get: { vm.settings.paletteScope },
                    set: { vm.settings.paletteScope = $0 }
                ))
                switch vm.settings.paletteScope {
                case .perFrame:
                    PaletteTreeView(palettes: o.palettesForDisplay, branching: vm.settings.paletteBranching)
                    BranchingSelector(selection: branching)
                case .global:
                    GlobalPaletteEditorView(palettes: o.palettesForDisplay, branching: branching)
                }
            case .grid:
                // The coordinate view: 256 colours on two user-assigned axes.
                PaletteGridView(palettes: o.palettesForDisplay,
                                xAxis: vm.settings.gridAxisX,
                                yAxis: vm.settings.gridAxisY)
                GridAxisSelector(
                    xAxis: Binding(get: { vm.settings.gridAxisX }, set: { vm.settings.gridAxisX = $0 }),
                    yAxis: Binding(get: { vm.settings.gridAxisY }, set: { vm.settings.gridAxisY = $0 })
                )
            }
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
                let i = frameIndex(at: ctx.date.timeIntervalSinceReferenceDate, rate: 20, count: n)
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

    /// The reproducibility proof: this GIF came out of the deterministic
    /// fixed-point Zig core, so its bytes are a pure function of the capture —
    /// the same scene + settings always yields this exact SHA-256. The five
    /// stage tags name the verified kernels the bytes flowed through.
    private func determinismBadge(sha: String) -> some View {
        let pipeline = DeterministicRenderer.Stage.allCases.map(\.tag).joined(separator: " → ")
        let shaShort = sha.count > 16 ? "\(sha.prefix(10))…\(sha.suffix(4))" : sha
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.green)
                Text("Deterministic core").foregroundStyle(.white.opacity(0.9))
                Text("· byte-reproducible").foregroundStyle(SFTheme.dimText)
            }
            .font(SFTheme.captionMono)
            Text(pipeline)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(SFTheme.dimText.opacity(0.85))
                .lineLimit(1).minimumScaleFactor(0.7)
            Text("sha256 \(shaShort)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(SFTheme.dimText)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: SFTheme.cardCorner))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Deterministic core, byte reproducible, SHA-256 \(shaShort)")
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
        GeometryReader { geo in
            let edge = SFTheme.canvasEdge(forAvailable: min(geo.size.width, geo.size.height), cells: 64)
            ZStack {
                if let img = currentImage {
                    PixelImage(image: img, edge: edge)
                        .accessibilityLabel("Rendered GIF, \(output.ditherMethod.label) dither, sixty-four frames at twenty fps")
                } else {
                    Rectangle().fill(.white.opacity(0.04))
                        .overlay(ProgressView().tint(.white))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
