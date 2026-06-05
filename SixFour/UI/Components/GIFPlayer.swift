import SwiftUI
import UIKit
import ImageIO

/// The unified GIF player — the Review hero. The GIF renders and plays as **one
/// tool set** in 2D (`GIFCanvas`) or 3D (`VoxelCubeView`), switched by a GRID
/// `ModeToggleCell`, both reading the SAME `PlaybackClock` and driven by the same
/// 6 pt `PlayerTransport` (play/pause · scrub · counter). Switching 2D⟷3D never
/// changes the frame; at the flat pose the cube's front face is byte-identical to
/// the 2D GIF (RULE-CUBE-2D-IDENTITY). See docs/SIXFOUR-UNIFIED-PLAYER.md.
///
/// Replaces the old bare `GIFCanvas(output:)` hero, which owned a private `Timer`
/// that drifted against the status line and palette views. Now one clock feeds them
/// all.
struct GIFPlayer: View {
    let output: CaptureOutput
    @Bindable var clock: PlaybackClock
    var settings: AppSettings?
    /// Shared cross-view brush, threaded to the cube (tap-to-pick at the flat pose).
    @Binding var brushedIndex: Int?

    @State private var mode: PlayerMode = .flat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The 64³ index volume, when the per-pixel map is present. nil ⇒ legacy output:
    /// the CUBE segment is hidden and the player stays 2D-only.
    private var cubeData: VoxelCubeData? { VoxelCubeData(output: output) }

    var body: some View {
        VStack(spacing: SFTheme.gifCellPt * 2) {
            renderSurface
                .pixelFrame()
            PlayerTransport(clock: clock, mode: $mode, cubeAvailable: cubeData != nil)
        }
        .onAppear {
            clock.reduceMotion = reduceMotion
            if let s = settings, cubeData != nil { mode = s.playerMode }
            clock.start()
        }
        .onDisappear { clock.stop() }
        .onChange(of: mode) { _, m in settings?.playerMode = m }
        .onChange(of: reduceMotion) { _, rm in clock.reduceMotion = rm }
    }

    @ViewBuilder
    private var renderSurface: some View {
        switch mode {
        case .flat:
            GIFCanvas(output: output, frame: clock.frame)
        case .cube:
            if let data = cubeData {
                VoxelCubeView(data: data, clock: clock, settings: settings,
                              brushedIndex: $brushedIndex,
                              brushMode: BrushSet.mode(settings?.paletteBranching ?? .b16),
                              chrome: .heroMinimal)
            } else {
                GIFCanvas(output: output, frame: clock.frame)   // unreachable (toggle hidden)
            }
        }
    }
}

// MARK: - GIFCanvas (render-only)

/// The looping GIF as a nearest-neighbour-upscaled bitmap, showing the frame the
/// shared `PlaybackClock` is on. Render-only: it loads the 64 frames once and
/// displays `frames[frame]` — it owns NO timer (the old private `Timer` +
/// `frameIndex` + `startTimer` moved into `PlaybackClock`, the single clock).
struct GIFCanvas: View {
    let output: CaptureOutput
    /// The current frame, supplied by the shared clock.
    let frame: Int

    @State private var frames: [UIImage] = []

    var body: some View {
        GeometryReader { geo in
            let edge = SFTheme.canvasEdge(forAvailable: min(geo.size.width, geo.size.height), cells: 64)
            ZStack {
                if let img = currentImage {
                    PixelImage(image: img, edge: edge)
                        .accessibilityLabel("Rendered GIF, \(output.ditherMethod.label) dither, frame \(frame + 1) of 64")
                } else {
                    Rectangle().fill(.white.opacity(0.04))
                        .overlay(ProgressView().tint(.white))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { loadFrames() }
    }

    private var currentImage: UIImage? {
        guard !frames.isEmpty else { return nil }
        return frames[frame % frames.count]
    }

    private func loadFrames() {
        guard frames.isEmpty else { return }
        // ONE SOURCE OF TRUTH (#5): when the deterministic index cube is present,
        // FRONT-PROJECT each frame from the SAME `frameIndices·palette` the voxel cube
        // and palette views read — pixel(x,y,t) = palette[t][indices[t][y·64+x]] — the
        // cube's flat rest pose (VoxelCubeView header law). The hero, cube, and palette
        // are then literally the same data. ImageIO decode stays ONLY as the legacy /
        // GPU-fallback path (no index cube, or non-deterministic bytes).
        if output.deterministic, let projected = Self.frontProjectedFrames(output) {
            self.frames = projected
            return
        }
        guard let src = CGImageSourceCreateWithURL(output.gifURL as CFURL, nil) else { return }
        let count = CGImageSourceGetCount(src)
        var imgs: [UIImage] = []
        imgs.reserveCapacity(count)
        for i in 0..<count {
            if let cg = CGImageSourceCreateImageAtIndex(src, i, nil) {
                imgs.append(UIImage(cgImage: cg))
            }
        }
        self.frames = imgs
    }

    /// Reconstruct the 64 front slices from the deterministic index cube — the same
    /// law the voxel cube renders (`VoxelCubeView`), so 2D ≡ 3D-rest-pose ≡ palette.
    /// Returns nil on legacy outputs (no per-pixel index map). Pure; built once.
    static func frontProjectedFrames(_ o: CaptureOutput) -> [UIImage]? {
        guard let indices = o.frameIndicesForVoxels, !indices.isEmpty,
              o.palettesForDisplay.count == indices.count else { return nil }
        let side = SixFourShape.W
        let pixels = side * side
        var imgs: [UIImage] = []
        imgs.reserveCapacity(indices.count)
        for t in indices.indices {
            let idx = indices[t]
            let pal = o.palettesForDisplay[t]
            guard idx.count == pixels else { return nil }
            var bytes = [UInt8](repeating: 255, count: pixels * 4)
            for i in 0..<pixels {
                let c = pal[Int(idx[i])]
                let b = i * 4
                bytes[b] = c.x; bytes[b + 1] = c.y; bytes[b + 2] = c.z
            }
            guard let img = pixelImage(fromRGBA: bytes, side: side) else { return nil }
            imgs.append(img)
        }
        return imgs
    }

    /// Opaque sRGB `UIImage` from a `side×side` RGBA8 buffer, interpolation off (the
    /// 64×64 pixels stay hard under upscale). Mirrors the capture preview's builder.
    private static func pixelImage(fromRGBA bytes: [UInt8], side: Int) -> UIImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        let cs = CGColorSpaceCreateDeviceRGB()
        let info: CGBitmapInfo = [.byteOrder32Big, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)]
        guard let cg = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: side * 4, space: cs, bitmapInfo: info, provider: provider,
                               decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
