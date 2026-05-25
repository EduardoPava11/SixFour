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
        case renderingStageA              // CPU refine + dither + per-frame surjectivity rescue
        case renderingEncode              // GIF89a emit
        case done
        case failed(String)
    }

    var phase: Phase = .configuring
    var composition: Composition = .classicalBaseline
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

    /// In-memory CaptureBundle for the most-recent successful render.
    /// Holds the raw OKLab tiles + per-frame ClusterStatistics from
    /// the extractor that produced the current GIF. Replaced on each
    /// new capture; nil before the first capture. Future editing
    /// tools consume this to re-run extraction / inspect statistics
    /// without re-shooting.
    var currentBundle: CaptureBundle?

    /// Bounded undo stack of render snapshots (see `EditHistory`). Reset on
    /// each capture, pushed on each `reExtract`, popped by `undo`.
    private(set) var history = EditHistory()

    /// Editing UI binds these to drive the Undo button + its label.
    var canUndo: Bool { history.canUndo }
    var editCount: Int { history.count }

    private(set) var session: CaptureSession?
    private(set) var pipeline: MetalPipeline?
    /// Per-algorithm palette pipelines, created once at bootstrap and handed
    /// to GIFRenderer; `Composition.makeExtractor` picks the right one.
    private(set) var engines: PaletteEngines?
    private(set) var store: GeneStore?

    func bootstrap() async {
        composition = composition.with(
            ditherMethod: settings.defaultDitherMethod
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
            self.engines = PaletteEngines(
                kMeans: try KMeansPalettePipeline(tileSide: 64)
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
        guard let session, let pipeline, let engines, let store else { return }
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
            let composition = self.composition

            let renderResult = try await renderOnce(
                tiles: tiles,
                composition: composition,
                store: store,
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
            // New capture → reset history to a single initial entry.
            // Any previous edits' GIF files leak slightly here (the
            // OS deletes them on next app launch via Documents
            // recycling); explicit cleanup not critical at burst-size.
            history.reset(to: EditHistory.Entry(
                output: renderResult.output,
                perFrameStatistics: renderResult.perFrameStatistics
            ))
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
        composition: Composition,
        store: GeneStore,
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

        let renderer = GIFRenderer(composition: composition, store: store, engines: engines)
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
            ditherMethod: composition.ditherMethod,
            meanExtractMSE: report.meanExtractMSE,
            meanCentroidConditionNumber: kappa,
            meanAdmissionRateAt05: admissionRate
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

    /// Pop the head of the edit history, restore the previous render
    /// to `primaryOutput` + `currentBundle.perFrameStatistics`.
    /// Refuses to pop below index 0 (the initial capture render is
    /// never lost — Retake is the way out of that state).
    ///
    /// The popped entry's GIF + contact-sheet files are deleted in
    /// the background to keep Documents tidy without blocking the
    /// UI. The dither selector is synced to the restored render's
    /// method so the picker reflects the now-current state.
    func undo() {
        guard let restored = history.undo() else { return }
        Haptics.impact(.light)
        primaryOutput = restored.output
        if var bundle = currentBundle {
            bundle.perFrameStatistics = restored.perFrameStatistics
            currentBundle = bundle
        }
        let restoredMethod = restored.output.ditherMethod
        if composition.ditherMethod != restoredMethod {
            self.composition = composition.with(ditherMethod: restoredMethod)
            self.settings.defaultDitherMethod = restoredMethod
        }
    }

    /// Re-render the cached capture bundle with a different dither method,
    /// in place. No re-capture — the raw OKLab tiles in `currentBundle.tiles`
    /// are the input, re-quantized (Wu+KM) and re-dithered. Updates
    /// `primaryOutput` + `currentBundle.perFrameStatistics` on success.
    ///
    /// Editing-tool entry point: lets the user A/B the two dither looks on
    /// the same scene without retaking. (The extraction algorithm is fixed at
    /// Wu+KM, so dither is the only thing left to vary here.)
    func reExtract(with method: DitherMethod) async {
        guard let bundle = currentBundle,
              let store = store,
              let engines = engines else { return }
        // No-op if the user re-picked the same method; saves a pass + write.
        if composition.ditherMethod == method && primaryOutput != nil { return }

        Haptics.impact(.light)
        let newComposition = composition.with(ditherMethod: method)
        self.composition = newComposition
        self.settings.defaultDitherMethod = method

        phase = .renderingStageA
        do {
            let renderResult = try await renderOnce(
                tiles: bundle.tiles,
                composition: newComposition,
                store: store,
                engines: engines,
                summary: bundle.burstTiming.summary
            )
            primaryOutput = renderResult.output
            // Tiles are unchanged (still re-renderable for further edits).
            currentBundle = CaptureBundle(
                id: bundle.id,
                captureTimestamp: bundle.captureTimestamp,
                burstTiming: bundle.burstTiming,
                colorSpaceTag: bundle.colorSpaceTag,
                tiles: bundle.tiles,
                perFrameStatistics: renderResult.perFrameStatistics
            )
            // Push onto edit history. If we exceed the cap, evict
            // the SECOND entry (preserve the initial render at
            // index 0 + most recent N-1 edits).
            history.push(EditHistory.Entry(
                output: renderResult.output,
                perFrameStatistics: renderResult.perFrameStatistics
            ))
            saveBundleAsync()
            phase = .done
            Haptics.notification(.success)
        } catch {
            let msg = String(describing: error)
            Self.logger.error("[viewmodel] reExtract failed: \(msg, privacy: .public)")
            phase = .failed(msg)
            Haptics.notification(.warning)
        }
    }

    /// Binding for the dither-method selector in CaptureView. Persists the
    /// choice and fires a haptic. Applies to the next capture; re-extract
    /// (`reExtract`) re-renders the cached burst with the current method.
    var ditherMethodBinding: Binding<DitherMethod> {
        Binding(
            get: { [weak self] in self?.composition.ditherMethod ?? .errorDiffusion },
            set: { [weak self] newMethod in
                guard let self else { return }
                self.composition = self.composition.with(ditherMethod: newMethod)
                self.settings.defaultDitherMethod = newMethod
                Haptics.selection()
            }
        )
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
