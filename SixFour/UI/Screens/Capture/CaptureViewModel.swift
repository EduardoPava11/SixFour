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
    let renderMillis: Int
    let stageAMillis: Int
    let encodeMillis: Int
    let fileSize: Int
    let timingSummary: String
    /// sRGB UInt8 palettes for the PaletteStripView — 64 entries (one
    /// per frame) of 256 colours each (the per-frame voxel volume).
    let palettesForDisplay: [[SIMD3<UInt8>]]
    /// Which dither method produced this render (the one creative option).
    let ditherMethod: DitherMethod
    /// Mean per-frame extraction MSE (OKLab units²). Surfaced in
    /// StatsFooterView as a fidelity readout.
    let meanExtractMSE: Float
    /// Mean centroid condition number κ across the 64 per-frame
    /// palettes. κ ≈ 1 → orthogonal centroids (well-conditioned
    /// palette); κ → ∞ → near-collinear centroids (palette has
    /// wasted slots). Surfaced as a multicollinearity diagnostic.
    let meanCentroidConditionNumber: Float
    /// Fraction (0…1) of clusters admitted by the χ²₃ test at
    /// α=0.05 across 64 frames. Higher → more "statistically real"
    /// clusters; lower → many palette slots are noise. Editing
    /// tools (future) can use this to drive auto-prune+refill.
    let meanAdmissionRateAt05: Float

    // Per-frame computation, surfaced for the Review verifier (length T = 64).
    /// 256 significance cells per frame (mean, σ/range, population, provenance).
    let perFrameCells: [[SixFourSignificantCell]]
    /// Significant-slot count per frame — proves 256 (the guarantee).
    let perFrameSignificant: [Int]
    /// Occupied 16³ OKLab bins per frame (single-frame coverage).
    let perFrameCoverage: [Int]
    /// Extraction MSE per frame (OKLab units²).
    let perFrameMSE: [Float]

    var id: URL { gifURL }

    // Identity is the GIF URL; the per-frame arrays aren't Hashable and don't
    // need to participate (two outputs are equal iff they're the same file).
    static func == (lhs: CaptureOutput, rhs: CaptureOutput) -> Bool { lhs.gifURL == rhs.gifURL }
    func hash(into hasher: inout Hasher) { hasher.combine(gifURL) }
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
        case renderingStageA              // CPU refine + dither + significance split-fill
        case renderingEncode              // GIF89a emit
        case done
        case failed(String)
    }

    var phase: Phase = .configuring
    var lastTimingSummary: String? = nil

    /// Persisted user preferences (default extractor today, plus
    /// Settings-screen seams). A future SettingsView binds to this; the
    /// capture screen reads it on `bootstrap` and writes back on change.
    let settings = AppSettings()

    var primaryOutput: CaptureOutput?

    /// Live 64×64 pixelated preview tile, updated at ~10 fps while
    /// the session is idle (no burst in progress). The CaptureView's
    /// "pixelated" preview mode binds to this; the toggle button in
    /// the top bar switches between the full-res AVCaptureVideoPreview
    /// and this downsampled view. Nil until the first frame arrives.
    var previewTile: UIImage?

    /// Live scene readout from the preview — the diversity gauge + dominant
    /// hue the capture screen reflects. EMA-smoothed (see `ingestSceneReadout`)
    /// so the gauge and tint glide rather than jitter at 10 fps.
    private(set) var scene: SceneReadout = .empty

    /// Live diversity ∈ [0,1] for the shutter gauge.
    var sceneGauge: Float { scene.gauge }

    /// Dominant scene hue, softened for chrome legibility (the buttons + the
    /// gauge ring take this). Falls back to white at zero diversity.
    var sceneTint: Color { SFTheme.accent(scene.tint) }

    /// In-memory CaptureBundle for the most-recent successful render.
    /// Holds the raw OKLab tiles + per-frame ClusterStatistics from
    /// the extractor that produced the current GIF. Replaced on each
    /// new capture; nil before the first capture. Future editing
    /// tools consume this to re-run extraction / inspect statistics
    /// without re-shooting.
    var currentBundle: CaptureBundle?

    private(set) var session: CaptureSession?
    private(set) var pipeline: MetalPipeline?
    /// Palette pipelines (Wu+KM extractor + GPU blue-noise), created once at
    /// bootstrap and handed to GIFRenderer.
    private(set) var engines: PaletteEngines?
    private(set) var store: GeneStore?

    func bootstrap() async {
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
                // Analyse on the Metal completion queue (cheap, ~0.1 ms) so we
                // don't hop to the main actor twice; publish both together.
                let readout = LivePreviewAnalysis.analyze(tile)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.previewTile = image
                    self.ingestSceneReadout(readout)
                }
            }

            self.pipeline = pipeline
            self.engines = PaletteEngines(
                kMeans: try KMeansPalettePipeline(tileSide: 64),
                blueNoise: try? BlueNoisePalettePipeline()
            )
            self.session = session
            self.store = store

            // Restore the most-recent CaptureBundle from disk (if
            // any). Populates `currentBundle` only — no GIF is
            // rendered automatically; the rendered GIF for an old
            // bundle is gone, and re-running the full render on
            // bootstrap would be a surprising hidden cost. Future
            // "open old captures" UI will surface this.
            do {
                if let loaded = try CaptureBundle.load() {
                    self.currentBundle = loaded
                    Self.logger.info("[viewmodel] restored CaptureBundle id=\(loaded.id, privacy: .public)")
                }
            } catch {
                Self.logger.warning("[viewmodel] CaptureBundle restore failed (ignored): \(String(describing: error), privacy: .public)")
            }

            session.startPreview()
            phase = .idle
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Best-effort background write of the current bundle to
    /// Documents. Logged on failure; never throws into the UI
    /// (persistence is a nice-to-have, not a critical path).
    private func saveBundleAsync() {
        guard let bundle = currentBundle else { return }
        Task.detached(priority: .background) {
            do {
                try bundle.save()
                Self.logger.info("[viewmodel] CaptureBundle saved to disk")
            } catch {
                Self.logger.warning("[viewmodel] CaptureBundle save failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func focus(at normalized: CGPoint) {
        session?.focusAndExpose(at: normalized)
    }

    func capture() async {
        guard let session, let pipeline, let engines else { return }
        Haptics.impact(.medium)
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
            // The sampler is configured in Settings, read fresh per capture.
            let dither = settings.ditherConfig

            let renderResult = try await renderOnce(
                tiles: tiles,
                dither: dither,
                engines: engines,
                summary: result.timing.summary
            )
            primaryOutput = renderResult.output
            // Build the in-memory CaptureBundle from raw tiles + the
            // per-frame statistics the extractor produced. Editing
            // tools consume this without needing to re-shoot.
            currentBundle = CaptureBundle(
                id: UUID(),
                captureTimestamp: Date(),
                burstTiming: result.timing,
                colorSpaceTag: session.activeColorSpaceTag,
                tiles: tiles,
                perFrameStatistics: renderResult.perFrameStatistics
            )
            saveBundleAsync()
            phase = .done
            Haptics.notification(.success)
        } catch let err as CaptureSession.CaptureError {
            let msg = String(describing: err)
            Self.logger.error("[viewmodel] capture failed: \(msg, privacy: .public)")
            phase = .failed(msg)
            Haptics.notification(.warning)
        } catch {
            let msg = String(describing: error)
            Self.logger.error("[viewmodel] capture failed: \(msg, privacy: .public)")
            phase = .failed(msg)
            Haptics.notification(.warning)
        }
    }

    /// Render-and-package result. The viewmodel needs both the
    /// user-visible `CaptureOutput` (GIF URL, palettes, timing) AND
    /// the per-frame statistics so it can assemble a CaptureBundle
    /// for downstream editing tools. Returning both from `renderOnce`
    /// keeps the data flow linear (no extra plumbing back through
    /// GIFRenderer.Report).
    private struct RenderResult: Sendable {
        let output: CaptureOutput
        let perFrameStatistics: [ClusterStatistics]
    }

    private func renderOnce(
        tiles: [OKLabTile],
        dither: DitherConfig,
        engines: PaletteEngines,
        summary: String
    ) async throws -> RenderResult {
        let baseURL = makeOutputURL(extension: "gif")
        let sheetURL = baseURL.deletingPathExtension().appendingPathExtension("contact.png")

        let onPhase: @Sendable (GIFRenderer.RenderPhase) -> Void = { stage in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch stage {
                case .stageA: self.phase = .renderingStageA
                case .encode: self.phase = .renderingEncode
                }
            }
        }

        let renderer = GIFRenderer(dither: dither, engines: engines)
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

        // Compute per-frame quality diagnostics via the Phase D
        // statistics module. Cost: ~10 µs/frame × 64 frames < 1 ms
        // total — negligible vs. the 100s of ms of GIF render. We
        // run this once per render; if the user re-extracts, this
        // is re-computed via the new render's perFrameStatistics.
        let (kappa, admissionRate) = Self.qualityDiagnostics(
            perFrameStatistics: report.perFrameStatistics
        )

        let output = CaptureOutput(
            gifURL: baseURL,
            contactURL: contact,
            renderMillis: report.totalMillis,
            stageAMillis: report.stageAMillis,
            encodeMillis: report.encodeMillis,
            fileSize: report.fileSize,
            timingSummary: summary,
            palettesForDisplay: report.palettesForDisplay,
            ditherMethod: dither.method,
            meanExtractMSE: report.meanExtractMSE,
            meanCentroidConditionNumber: kappa,
            meanAdmissionRateAt05: admissionRate,
            perFrameCells: report.perFrameCells,
            perFrameSignificant: report.perFrameSignificant,
            perFrameCoverage: report.perFrameCoverage,
            perFrameMSE: report.perFrameMSE
        )
        return RenderResult(output: output, perFrameStatistics: report.perFrameStatistics)
    }

    /// Compute the two extractor-quality summary metrics across all
    /// 64 per-frame palettes:
    ///   - mean κ (centroid Gram condition number) — multicollinearity
    ///   - mean fraction admitted by χ²₃ at α=0.05 — statistical
    ///     significance of the per-frame clusters relative to that
    ///     frame's pooled mean+covariance.
    /// Skips per-frame κ values that are infinite (rank-deficient
    /// palettes) when averaging — those would dominate the mean
    /// and obscure typical κ.
    nonisolated static func qualityDiagnostics(
        perFrameStatistics: [ClusterStatistics]
    ) -> (kappa: Float, admissionRate: Float) {
        guard !perFrameStatistics.isEmpty else { return (.infinity, 0) }
        var kappaSum: Float = 0
        var kappaCount = 0
        var admittedSum: Float = 0
        for stats in perFrameStatistics {
            let κ = ClusterStatisticsOps.centroidConditionNumber(stats.clusters)
            if κ.isFinite {
                kappaSum += κ
                kappaCount += 1
            }
            let pooledMean = ClusterStatisticsOps.pooledMean(stats.clusters)
            let pooledCov = ClusterStatisticsOps.pooledCovariance(
                stats.clusters, pooledMean: pooledMean
            )
            let (admitted, _) = ClusterStatisticsOps.chiSquareAdmission(
                clusters: stats.clusters,
                alpha: 0.05,
                populationMean: pooledMean,
                populationCovariance: pooledCov
            )
            // Denominator is total clusters (including empty); the
            // "admission rate" is what fraction of the palette
            // budget is being earned.
            admittedSum += Float(admitted.count) / Float(max(1, stats.clusters.count))
        }
        let meanKappa: Float = kappaCount > 0
            ? kappaSum / Float(kappaCount)
            : .infinity
        let meanAdmitted = admittedSum / Float(perFrameStatistics.count)
        return (meanKappa, meanAdmitted)
    }

    func reset() {
        phase = .idle
        primaryOutput = nil
        // currentBundle deliberately persists across reset() — Retake
        // brings the user back to capture, but if they DON'T retake
        // they should still be able to open editing tools on the
        // last bundle. The bundle is only replaced on a successful
        // new capture.
    }

    /// EMA-blend a fresh raw readout into the published `scene` so the gauge,
    /// dominant tint, and bin count glide rather than jitter at 10 fps. The
    /// View decides whether to *animate* the change (it snaps under
    /// reduce-motion); the signal itself is always smoothed.
    private func ingestSceneReadout(_ r: SceneReadout) {
        let a: Float = 0.2  // EMA weight per ~10 fps tick
        let g = scene.gauge * (1 - a) + r.gauge * a
        let bins = Int((Float(scene.occupiedBins) * (1 - a) + Float(r.occupiedBins) * a).rounded())
        let old = SIMD3<Float>(Float(scene.tint.x), Float(scene.tint.y), Float(scene.tint.z))
        let new = SIMD3<Float>(Float(r.tint.x), Float(r.tint.y), Float(r.tint.z))
        let b = old * (1 - a) + new * a
        let tint = SIMD3<UInt8>(
            UInt8(min(255, max(0, b.x.rounded()))),
            UInt8(min(255, max(0, b.y.rounded()))),
            UInt8(min(255, max(0, b.z.rounded())))
        )
        scene = SceneReadout(occupiedBins: bins, gauge: g, tint: tint, accents: r.accents)
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
