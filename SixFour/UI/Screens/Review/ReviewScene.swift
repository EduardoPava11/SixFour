import SwiftUI
import UIKit

/// The lean post-capture Review (brief: "the GIFA + slider X + slider Y + share +
/// retake, nothing else yet"). Replaces the rich `GIFReviewView` (palette explorer,
/// status line, toggles) on the capture→GIFA flow. It is mounted IN-LATTICE by
/// `CaptureView` (no `fullScreenCover` modal swap) and driven by a clock owned ONE
/// level up, so a single 64×64 surface persists across capture→loading→review.
///
/// Phase 4 ships the flat GIF hero — which IS the cube's rest face
/// (`GIFCanvas.frontProjectedFrames`, RULE-CUBE-2D-IDENTITY). Phase 5 swaps it for
/// the rotatable `VoxelCubeView` and wires the X/Y sliders to yaw/pitch.
struct ReviewScene: View {
    let vm: CaptureViewModel
    /// THE playback clock — owned by `CaptureView` and injected, so this view never
    /// starts/stops it on appear/disappear (the persistent-surface contract).
    @Bindable var clock: PlaybackClock

    @State private var shaCopied = false
    /// Drives the "cube coming forward" entrance: the hero scales up from the capture
    /// preview's footprint (256 pt) to the review hero (384 pt) = 256/384 → 1.
    @State private var settled = false
    /// Cube orientation, owned here and driven by the X/Y sliders (radians). Rest pose
    /// (0,0) is the flat 2D GIF — RULE-CUBE-2D-IDENTITY — so Review opens looking exactly
    /// like the GIFA that was building; sliding rotates it into the 8-bit isometric cube.
    @State private var yaw: Double = 0
    @State private var pitch: Double = 0

    private let heroEdge = CGFloat(SFTheme.gifCanvasPt)   // 384 = 64 × 6 pt

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let primary = vm.primaryOutput {
                let cube = VoxelCubeData(output: primary)
                let cubeOK = cube?.isWellFormed ?? false
                VStack(spacing: SFTheme.gifCellPt) {
                    Spacer(minLength: 0)
                    heroSurface(primary, cube: cubeOK ? cube : nil)
                    if cubeOK { poseSliders }
                    shaFooter(primary)
                    Spacer(minLength: 0)
                    actionRow(primary)
                }
                .padding(.horizontal, SFTheme.gifCellPt)
                .padding(.bottom, SFTheme.gifCellPt)
            } else {
                ProgressView().tint(.white)
            }
        }
        .onAppear {
            // Continuous handoff from the loading sweep: grow the surface forward.
            withAnimation(.easeOut(duration: 0.28)) { settled = true }
        }
    }

    /// The hero surface. With an index cube present it's the rotatable 64³ voxel cube
    /// (posed by the sliders); at rest (0,0) its front face is byte-identical to the 2D
    /// GIF (RULE-CUBE-2D-IDENTITY). Legacy outputs (no index map) fall back to the flat
    /// `GIFCanvas`. Raw `VoxelMetalView` — no glass chrome (brief: "nothing else").
    @ViewBuilder
    private func heroSurface(_ primary: CaptureOutput, cube: VoxelCubeData?) -> some View {
        Group {
            if let cube {
                CubeSurface(data: cube, yaw: Float(yaw), pitch: Float(pitch), frame: clock.frame)
                    .frame(width: heroEdge, height: heroEdge)
                    .background(Color.black)
                    .pixelFrame()
            } else {
                GIFCanvas(output: primary, frame: clock.frame)
                    .frame(width: heroEdge, height: heroEdge)
                    .pixelFrame()
            }
        }
        // 256/384 ≈ 0.667 → 1: the "cube coming forward" entrance (both crisp; 256 and
        // 384 are integer multiples of 64).
        .scaleEffect(settled ? 1 : CGFloat(256.0 / Double(SFTheme.gifCanvasPt)))
    }

    /// The slider-driven orientation passed to the cube renderer.
    private var posedState: VoxelCubeState {
        var s = VoxelCubeState()
        s.yaw = Float(yaw)
        s.pitch = Float(pitch)
        return s
    }

    /// The brief's two controls: slider X → yaw, slider Y → pitch. Pitch is clamped to
    /// ±1.5 rad (matching the cube's orbit limit). Degrees shown for legibility.
    private var poseSliders: some View {
        let dim = SIMD3<UInt8>(170, 170, 170)
        return VStack(alignment: .leading, spacing: GlobalLattice.pt(2)) {
            CellText("rotate X · yaw \(Int((yaw * 180 / .pi).rounded()))°", rows: 6, ink: Color(srgb8: dim))
            CellSlider(value: $yaw, range: -Double.pi ... Double.pi)
            CellText("rotate Y · pitch \(Int((pitch * 180 / .pi).rounded()))°", rows: 6, ink: Color(srgb8: dim))
            CellSlider(value: $pitch, range: -1.5 ... 1.5)
        }
        .frame(maxWidth: heroEdge)
    }

    /// The single preserved trust line: the deterministic SHA-256 (tap to copy), or an
    /// explicit GPU-fallback note. The full status line / palette explorer is deferred.
    @ViewBuilder
    private func shaFooter(_ o: CaptureOutput) -> some View {
        let dim = SIMD3<UInt8>(140, 140, 140)
        let green = SIMD3<UInt8>(70, 200, 90)
        if o.deterministic, let sha = o.sha256 {
            let shaShort = sha.count > 16 ? "\(sha.prefix(10))…\(sha.suffix(4))" : sha
            Button {
                UIPasteboard.general.string = sha
                shaCopied = true
                Task { try? await Task.sleep(for: .seconds(1.4)); shaCopied = false }
            } label: {
                CellText(shaCopied ? "sha256 copied ✓" : "deterministic · sha256 \(shaShort)",
                         rows: 6, ink: Color(srgb8: shaCopied ? green : dim))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Deterministic core, SHA-256 \(sha). Double tap to copy.")
        } else {
            CellText("GPU fallback · not byte-reproducible",
                     rows: 6, ink: Color(srgb8: SIMD3<UInt8>(225, 200, 70)))
                .accessibilityLabel("GPU fallback render, not byte reproducible")
        }
    }

    /// Share + Retake (the brief's two actions). Flat cell buttons, no glass.
    private func actionRow(_ primary: CaptureOutput) -> some View {
        HStack(spacing: GlobalLattice.pt(GlobalLattice.gutterCells)) {
            ShareLink(item: primary.gifURL) {
                CellActionButton(icon: .share, title: "Share", prominent: true)
            }
            .accessibilityLabel("Share GIF")

            Button { vm.reset() } label: {
                CellActionButton(icon: .retake, title: "Retake")
            }
            .accessibilityLabel("Retake")
        }
        .buttonStyle(.plain)
    }
}
