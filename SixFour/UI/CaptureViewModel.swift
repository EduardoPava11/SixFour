import Foundation
import SwiftUI
import UIKit
import simd
import os

/// Value type for one completed capture-and-render. The StatsFooterView
/// reads every field directly.
struct CaptureOutput: Sendable, Hashable, Identifiable {
    let gifURL: URL
    let contactURL: URL?
    let mode: PaletteGenerator.Mode
    let renderMillis: Int
    let stageAMillis: Int
    let stageBMillis: Int?
    let encodeMillis: Int
    let fileSize: Int
    /// θ Stage B settled on (only meaningful when Stage B ran).
    let achievedTheta: Double?
    /// Number of adaptive-θ attempts Stage B made.
    let attempts: Int?
    let timingSummary: String
    /// sRGB UInt8 palettes for the PaletteStripView — either 1 (Shared/Global)
    /// or 64 (Per-frame) entries of 256 colours each.
    let palettesForDisplay: [[SIMD3<UInt8>]]

    var id: URL { gifURL }
}

@MainActor
@Observable
final class CaptureViewModel {
    nonisolated static let logger = Logger(subsystem: "com.sixfour.SixFour", category: "viewmodel")

    /// Capture-and-render lifecycle. The three rendering sub-cases let the
    /// banner show *which* stage is running so the user understands the delay.
    enum Phase: Equatable {
        case unauthorized
        case configuring
        case idle
        case locking
        case capturing(progress: Double)
        case renderingStageA              // CPU refine + dither (Stage A is GPU)
        case renderingStageB              // Sinkhorn-balanced global merge
        case renderingEncode              // GIF89a emit
        case done
        case failed(String)
    }

    var phase: Phase = .configuring
    var composition: Composition = .classicalBaseline
    var lastTimingSummary: String? = nil

    /// Persisted last-used mode. Versioned `String` so adding modes later
    /// won't require an Int↔enum lookup table. Legacy `Int 0/1` files
    /// decode as `.perFrame` / `.shared`.
    @ObservationIgnored
    @AppStorage("sixfour.paletteMode.v2") private var storedMode: String = "perFrame"

    var primaryOutput: CaptureOutput?

    /// Live 64×64 pixelated preview tile, updated at ~10 fps while
    /// the session is idle (no burst in progress). The CaptureView's
    /// "pixelated" preview mode binds to this; the toggle button in
    /// the top bar switches between the full-res AVCaptureVideoPreview
    /// and this downsampled view. Nil until the first frame arrives.
    var previewTile: UIImage?

    private(set) var session: CaptureSession?
    private(set) var pipeline: MetalPipeline?
    private(set) var store: GeneStore?

    func bootstrap() async {
        let restored = restoredMode()
        composition = Composition(
            name: composition.name,
            metric: composition.metric,
            createdAt: composition.createdAt,
            paletteMode: restored
        )

        do {
            let authorized = await CaptureSession.requestAuthorization()
            guard authorized else {
                phase = .unauthorized
                return
            }
            let pipeline = try MetalPipeline(tileSide: 64)
            let session = try CaptureSession(targetFps: 20, targetFrameCount: 64)
            let store = try GeneStore()

            // CaptureSession.init -> configure() -> selectHDRFormatAndEnable
            // settles activeColorSpaceTag before returning; copy it to the
            // pipeline so the Metal kernel decodes YCbCr10 against the
            // right OETF + RGB primaries instead of always assuming Rec.709.
            pipeline.colorSpaceTag = session.activeColorSpaceTag.rawValue
            Self.logger.info(
                "[viewmodel] propagated colorSpaceTag=\(session.activeColorSpaceTag.label, privacy: .public) to MetalPipeline"
            )

            // Wire the live 64×64 preview path. The callback runs on
            // the session's delegateQueue; we marshal the OKLab→UIImage
            // conversion + assignment to the MainActor here so the
            // SwiftUI binding fires cleanly.
            session.previewPipeline = pipeline
            session.previewCallback = { [weak self] tile in
                guard let image = Self.makePreviewImage(from: tile) else { return }
                Task { @MainActor [weak self] in
                    self?.previewTile = image
                }
            }

            self.pipeline = pipeline
            self.session = session
            self.store = store

            session.startPreview()
            phase = .idle
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    func focus(at normalized: CGPoint) {
        session?.focusAndExpose(at: normalized)
    }

    func capture() async {
        guard let session, let pipeline, let store else { return }
        Self.fireHapticImpact(.medium)
        phase = .locking
        let lockResult = await session.lockExposureAndWhiteBalance(timeoutMs: 400)
        Self.logger.info("[viewmodel] AE/AWB lock: \(String(describing: lockResult), privacy: .public)")

        phase = .capturing(progress: 0)
        do {
            defer { session.unlockExposureAndWhiteBalance() }
            let result = try await session.captureBurst(into: pipeline)
            lastTimingSummary = result.timing.summary
            Self.logger.info("[viewmodel] burst complete: \(result.timing.summary, privacy: .public)")

            let tiles = result.tiles
            let mode = composition.paletteMode
            let composition = self.composition

            primaryOutput = try await renderOnce(
                tiles: tiles,
                mode: mode,
                composition: composition,
                store: store,
                pipeline: pipeline,
                summary: result.timing.summary
            )
            phase = .done
            Self.fireHapticNotification(.success)
        } catch let err as StageBSinkhorn.StageBError {
            let msg = String(describing: err)
            Self.logger.error("[viewmodel] capture failed: \(msg, privacy: .public)")
            phase = .failed(msg)
            Self.fireHapticNotification(.warning)
        } catch let err as CaptureSession.CaptureError {
            let msg = String(describing: err)
            Self.logger.error("[viewmodel] capture failed: \(msg, privacy: .public)")
            phase = .failed(msg)
            Self.fireHapticNotification(.warning)
        } catch {
            let msg = String(describing: error)
            Self.logger.error("[viewmodel] capture failed: \(msg, privacy: .public)")
            phase = .failed(msg)
            Self.fireHapticNotification(.warning)
        }
    }

    private func renderOnce(
        tiles: [OKLabTile],
        mode: PaletteGenerator.Mode,
        composition: Composition,
        store: GeneStore,
        pipeline: MetalPipeline,
        summary: String
    ) async throws -> CaptureOutput {
        let baseURL = makeOutputURL(extension: "gif")
        let sheetURL = baseURL.deletingPathExtension().appendingPathExtension("contact.png")

        let onPhase: @Sendable (GIFRenderer.RenderPhase) -> Void = { stage in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch stage {
                case .stageA: self.phase = .renderingStageA
                case .stageB: self.phase = .renderingStageB
                case .encode: self.phase = .renderingEncode
                }
            }
        }

        let renderer = GIFRenderer(composition: composition, store: store, pipeline: pipeline)
        let report = try await Task.detached(priority: .userInitiated) {
            try await renderer.render(tiles: tiles, to: baseURL, fps: 20, onPhase: onPhase)
        }.value

        // Contact sheet is best-effort.
        do {
            try await Task.detached(priority: .utility) {
                try ContactSheet.writePNG(tiles: tiles, to: sheetURL)
            }.value
        } catch {
            Self.logger.error("Contact sheet failed: \(String(describing: error))")
        }
        let contact: URL? = FileManager.default.fileExists(atPath: sheetURL.path) ? sheetURL : nil

        return CaptureOutput(
            gifURL: baseURL,
            contactURL: contact,
            mode: report.mode,
            renderMillis: report.totalMillis,
            stageAMillis: report.stageAMillis,
            stageBMillis: report.stageBMillis,
            encodeMillis: report.encodeMillis,
            fileSize: report.fileSize,
            achievedTheta: report.achievedTheta,
            attempts: report.attempts,
            timingSummary: summary,
            palettesForDisplay: report.palettesForDisplay
        )
    }

    func reset() {
        phase = .idle
        primaryOutput = nil
    }

    /// Binding for `ModeSelector`. Persists the chosen mode and fires a haptic.
    var paletteModeBinding: Binding<PaletteGenerator.Mode> {
        Binding(
            get: { [weak self] in self?.composition.paletteMode ?? .perFrame },
            set: { [weak self] newMode in
                guard let self else { return }
                self.composition = Composition(
                    name: self.composition.name,
                    metric: self.composition.metric,
                    createdAt: self.composition.createdAt,
                    paletteMode: newMode
                )
                self.storedMode = Self.encode(mode: newMode)
                Self.fireHapticSelection()
            }
        )
    }

    private func restoredMode() -> PaletteGenerator.Mode {
        switch storedMode {
        case "perFrame": return .perFrame
        case "shared":   return .shared
        case "global":   return .global
        // Legacy fallthroughs: the pre-v2 storage encoded 0/1 (perFrame/global).
        // Round to the nearest live endpoint so old installs keep their pick.
        case "0":        return .perFrame
        case "1":        return .shared
        default:         return .perFrame
        }
    }

    private static func encode(mode: PaletteGenerator.Mode) -> String {
        switch mode {
        case .perFrame: return "perFrame"
        case .shared:   return "shared"
        case .global:   return "global"
        }
    }

    // MARK: - Haptics

    nonisolated private static func fireHapticImpact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        Task { @MainActor in
            let gen = UIImpactFeedbackGenerator(style: style)
            gen.impactOccurred()
        }
    }

    nonisolated private static func fireHapticNotification(_ kind: UINotificationFeedbackGenerator.FeedbackType) {
        Task { @MainActor in
            UINotificationFeedbackGenerator().notificationOccurred(kind)
        }
    }

    nonisolated private static func fireHapticSelection() {
        Task { @MainActor in
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    /// Convert one 64×64 OKLab tile into a UIImage in the sRGB color
    /// space, ready for display by SwiftUI Image(uiImage:). The pixel
    /// data is laid out as RGBA8 (alpha = 255) so we can hand it
    /// straight to CGImage without an intermediate vImage convert.
    /// Cost: ~0.5 ms per call (4096 OKLab→sRGB conversions + one
    /// CGImage create). nonisolated so it can run on the session's
    /// delegate queue before being marshaled to MainActor.
    nonisolated private static func makePreviewImage(from tile: OKLabTile) -> UIImage? {
        let side = tile.side
        let pixelCount = side * side
        guard tile.pixels.count == pixelCount else { return nil }

        // RGBA8 buffer (alpha always 255 — opaque preview).
        var bytes = [UInt8](repeating: 255, count: pixelCount * 4)
        for i in 0..<pixelCount {
            let lab = OKLab(tile.pixels[i])
            let rgb = ColorScience.okLabToSRGB8(lab)
            let base = i * 4
            bytes[base + 0] = rgb.x
            bytes[base + 1] = rgb.y
            bytes[base + 2] = rgb.z
            // bytes[base + 3] = 255 already from repeating:
        }

        let bytesPerRow = side * 4
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else {
            return nil
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: CGBitmapInfo = [
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            .byteOrder32Big
        ]
        guard let cgImage = CGImage(
            width: side, height: side,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func makeOutputURL(extension ext: String) -> URL {
        let docs = (try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withTimeZone]
        let stamp = f.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return docs.appending(path: "sixfour_\(stamp).\(ext)")
    }
}
