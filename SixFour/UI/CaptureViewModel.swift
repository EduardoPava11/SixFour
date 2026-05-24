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
    /// Which extractor produced the per-frame palettes for this render.
    let extractorChoice: Composition.ExtractorChoice
    /// Mean per-frame extraction MSE (OKLab units²). Surfaced in
    /// StatsFooterView so users can A/B compare extractors on the
    /// same scene.
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

    /// In-memory CaptureBundle for the most-recent successful render.
    /// Holds the raw OKLab tiles + per-frame ClusterStatistics from
    /// the extractor that produced the current GIF. Replaced on each
    /// new capture; nil before the first capture. Future editing
    /// tools consume this to re-run extraction / inspect statistics
    /// without re-shooting.
    var currentBundle: CaptureBundle?

    /// Edit history stack. Index 0 = the initial render produced by
    /// `capture()`. Each `reExtract()` appends a new entry. `undo()`
    /// pops the head (refuses to drop below index 0). Capped at 10
    /// entries; eldest non-initial gets evicted on overflow with
    /// background file cleanup.
    private(set) var editHistory: [EditHistoryEntry] = []

    /// One entry on the edit history stack — a complete render
    /// snapshot (user-visible CaptureOutput + the rich
    /// ClusterStatistics that produced it). Carrying both lets
    /// `undo()` restore primaryOutput + the bundle's
    /// perFrameStatistics atomically.
    struct EditHistoryEntry: Sendable {
        let output: CaptureOutput
        let perFrameStatistics: [ClusterStatistics]
    }

    /// Editing UI binds this to enable/disable the Undo button.
    var canUndo: Bool { editHistory.count > 1 }

    /// Max entries kept on the edit history stack. The initial
    /// render plus 9 user edits — covers the typical A/B/C
    /// comparison flow without growing storage forever.
    static let editHistoryCap: Int = 10

    /// Persisted last-used extractor choice (K-means / Wu / Octree).
    /// Restored on bootstrap. Format: the enum's `rawValue` string.
    @ObservationIgnored
    @AppStorage("sixfour.extractor.v1") private var storedExtractor: String = "kMeans"

    private(set) var session: CaptureSession?
    private(set) var pipeline: MetalPipeline?
    private(set) var store: GeneStore?

    func bootstrap() async {
        let restoredMode = restoredMode()
        let restoredChoice = restoredExtractorChoice()
        composition = Composition(
            name: composition.name,
            metric: composition.metric,
            createdAt: composition.createdAt,
            paletteMode: restoredMode,
            extractorChoice: restoredChoice
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

            let renderResult = try await renderOnce(
                tiles: tiles,
                mode: mode,
                composition: composition,
                store: store,
                pipeline: pipeline,
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
            editHistory = [EditHistoryEntry(
                output: renderResult.output,
                perFrameStatistics: renderResult.perFrameStatistics
            )]
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
        mode: PaletteGenerator.Mode,
        composition: Composition,
        store: GeneStore,
        pipeline: MetalPipeline,
        summary: String
    ) async throws -> RenderResult {
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
            mode: report.mode,
            renderMillis: report.totalMillis,
            stageAMillis: report.stageAMillis,
            stageBMillis: report.stageBMillis,
            encodeMillis: report.encodeMillis,
            fileSize: report.fileSize,
            achievedTheta: report.achievedTheta,
            attempts: report.attempts,
            timingSummary: summary,
            palettesForDisplay: report.palettesForDisplay,
            extractorChoice: report.extractorChoice,
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
    /// UI. The `composition.extractorChoice` is reverted to the
    /// previous entry's extractor so the picker on screen reflects
    /// the now-current state.
    func undo() {
        guard canUndo else { return }
        let popped = editHistory.removeLast()
        let restored = editHistory.last!  // safe: count > 1 verified above
        Self.fireHapticImpact(.light)
        Self.deleteFilesAsync(for: popped.output)
        primaryOutput = restored.output
        if var bundle = currentBundle {
            bundle.perFrameStatistics = restored.perFrameStatistics
            currentBundle = bundle
        }
        // Sync the picker selection to whatever the restored render
        // was extracted with.
        let restoredChoice = restored.output.extractorChoice
        if composition.extractorChoice != restoredChoice {
            self.composition = Composition(
                name: composition.name,
                metric: composition.metric,
                createdAt: composition.createdAt,
                paletteMode: composition.paletteMode,
                extractorChoice: restoredChoice
            )
            self.storedExtractor = restoredChoice.rawValue
        }
    }

    /// Background file cleanup. Deletes the GIF + (optional)
    /// contact-sheet for an evicted/popped EditHistoryEntry. Errors
    /// are swallowed — best-effort; the OS recycles Documents on
    /// next launch anyway, and the user shouldn't see hitches
    /// because Undo is supposed to feel instant.
    nonisolated static func deleteFilesAsync(for output: CaptureOutput) {
        let gif = output.gifURL
        let contact = output.contactURL
        Task.detached(priority: .background) {
            try? FileManager.default.removeItem(at: gif)
            if let contact = contact {
                try? FileManager.default.removeItem(at: contact)
            }
        }
    }

    /// Re-extract palettes from the cached capture bundle with a
    /// different extractor family and re-render the GIF in place.
    /// No re-capture — the raw OKLab tiles in `currentBundle.tiles`
    /// are the input. Updates `primaryOutput` + `currentBundle
    /// .perFrameStatistics` on success.
    ///
    /// Editing-tool entry point #1: lets the user A/B different
    /// extractors on the same scene without retaking. Future edits
    /// (parameter sliders, χ²-refill toggle, K=64/128/256) will use
    /// the same pattern — pass new params + reuse bundle.tiles.
    ///
    /// Updates `composition.extractorChoice` so subsequent captures
    /// default to the new pick. The AppStorage persistence flows
    /// through `extractorChoiceBinding`.
    func reExtract(with choice: Composition.ExtractorChoice) async {
        guard let bundle = currentBundle,
              let store = store,
              let pipeline = pipeline else { return }
        // No-op if the user re-picked the same extractor; saves a
        // GPU/CPU pass and a Documents write.
        if composition.extractorChoice == choice && primaryOutput != nil { return }

        Self.fireHapticImpact(.light)
        let newComposition = Composition(
            name: composition.name,
            metric: composition.metric,
            createdAt: composition.createdAt,
            paletteMode: composition.paletteMode,
            extractorChoice: choice
        )
        self.composition = newComposition
        self.storedExtractor = choice.rawValue

        phase = .renderingStageA
        do {
            let renderResult = try await renderOnce(
                tiles: bundle.tiles,
                mode: newComposition.paletteMode,
                composition: newComposition,
                store: store,
                pipeline: pipeline,
                summary: bundle.burstTiming.summary
            )
            primaryOutput = renderResult.output
            // Replace the cached perFrameStatistics with the new
            // extractor's output. Tiles are unchanged (still
            // re-extractable for further edits).
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
            let entry = EditHistoryEntry(
                output: renderResult.output,
                perFrameStatistics: renderResult.perFrameStatistics
            )
            editHistory.append(entry)
            if editHistory.count > Self.editHistoryCap {
                let evicted = editHistory.remove(at: 1)
                Self.deleteFilesAsync(for: evicted.output)
            }
            phase = .done
            Self.fireHapticNotification(.success)
        } catch let err as StageBSinkhorn.StageBError {
            let msg = String(describing: err)
            Self.logger.error("[viewmodel] reExtract failed: \(msg, privacy: .public)")
            phase = .failed(msg)
            Self.fireHapticNotification(.warning)
        } catch {
            let msg = String(describing: error)
            Self.logger.error("[viewmodel] reExtract failed: \(msg, privacy: .public)")
            phase = .failed(msg)
            Self.fireHapticNotification(.warning)
        }
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
                    paletteMode: newMode,
                    extractorChoice: self.composition.extractorChoice
                )
                self.storedMode = Self.encode(mode: newMode)
                Self.fireHapticSelection()
            }
        )
    }

    /// Binding for the extractor picker in CaptureView. Persists the
    /// chosen family and fires a haptic. The next capture uses the
    /// new choice; previously rendered GIFs / bundles aren't affected.
    var extractorChoiceBinding: Binding<Composition.ExtractorChoice> {
        Binding(
            get: { [weak self] in self?.composition.extractorChoice ?? .kMeans },
            set: { [weak self] newChoice in
                guard let self else { return }
                self.composition = Composition(
                    name: self.composition.name,
                    metric: self.composition.metric,
                    createdAt: self.composition.createdAt,
                    paletteMode: self.composition.paletteMode,
                    extractorChoice: newChoice
                )
                self.storedExtractor = newChoice.rawValue
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

    /// Restore the extractor pick from AppStorage. Defaults to
    /// .kMeans for first launch (matches the prior behavior).
    private func restoredExtractorChoice() -> Composition.ExtractorChoice {
        Composition.ExtractorChoice(rawValue: storedExtractor) ?? .kMeans
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
