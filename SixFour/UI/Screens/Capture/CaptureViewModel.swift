import Foundation
import SwiftUI
import UIKit
import simd
import os

/// Value type for one completed capture-and-render. The Review screen
/// (GIFReviewView) reads these fields to drive the player, palette views,
/// status line, and the determinism badge.
struct CaptureOutput: Sendable, Hashable, Identifiable {
    let gifURL: URL
    let contactURL: URL?
    let renderMillis: Int
    let stageAMillis: Int
    let encodeMillis: Int
    let fileSize: Int
    let timingSummary: String
    /// sRGB UInt8 palettes for the Review palette views — 64 entries (one
    /// per frame) of 256 colours each (the per-frame voxel volume).
    let palettesForDisplay: [[SIMD3<UInt8>]]
    /// Which dither method produced this render (the one creative option).
    let ditherMethod: DitherMethod
    /// Mean per-frame extraction MSE (OKLab units²), computed in the Q16 integer
    /// domain so it matches the deterministic bytes. Surfaced in the Review status line.
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

    /// 64 × 4096 per-pixel palette indices (row-major `y*64 + x`, top-left
    /// origin) — the source for the 3D voxel-cube Review mode. A voxel's colour
    /// is `palettesForDisplay[t][frameIndicesForVoxels[t][y*64 + x]]`. Optional
    /// (nil on legacy/synthetic outputs). Out of ==/hash (identity is gifURL).
    /// `var` (not `let`) so it stays in the memberwise init while keeping a
    /// default — matching `deterministic`/`sha256` below.
    var frameIndicesForVoxels: [[UInt8]]? = nil

    /// True when produced by the deterministic fixed-point Zig core (vs the GPU
    /// float path). Drives the Review reproducibility badge.
    var deterministic: Bool = false
    /// Lowercase hex SHA-256 of the GIF bytes — the reproducible fingerprint,
    /// non-nil only on the deterministic path. Same scene+settings ⇒ same hash.
    var sha256: String? = nil
    /// Wall-time (ms) of each verified Zig kernel, in Stage order [quantize, dither,
    /// significance, palette, encode]. Empty on the GPU path. Surfaced under the
    /// determinism badge so the visible spine is quantitative (not `encodeMillis:0`).
    var stageMillis: [Int] = []

    var id: URL { gifURL }

    // Identity is the GIF URL; the per-frame arrays aren't Hashable and don't
    // need to participate (two outputs are equal iff they're the same file).
    static func == (lhs: CaptureOutput, rhs: CaptureOutput) -> Bool { lhs.gifURL == rhs.gifURL }
    func hash(into hasher: inout Hasher) { hasher.combine(gifURL) }
}

/// Serial off-camera-queue renderer with a **coalescing latch**: only the NEWEST
/// submitted tile is rendered; intermediate tiles are dropped if the renderer
/// falls behind. A preview wants the latest frame, not a backlog — so this keeps
/// the heavy quantize + CGImage build OFF the camera intake (delegate) queue,
/// which is what lets a burst run without dropping RECORDED frames to
/// `alwaysDiscardsLateVideoFrames` back-pressure. `submit` is O(1) and
/// non-blocking, safe to call from the delegate queue.
private final class CoalescingFrameRenderer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.sixfour.preview.render", qos: .userInitiated)
    private let lock = NSLock()
    private var pending: OKLabTile?
    private var draining = false
    private let render: @Sendable (OKLabTile) -> CaptureViewModel.PreviewFrame?
    private let onFrame: @Sendable (CaptureViewModel.PreviewFrame) -> Void

    init(render: @escaping @Sendable (OKLabTile) -> CaptureViewModel.PreviewFrame?,
         onFrame: @escaping @Sendable (CaptureViewModel.PreviewFrame) -> Void) {
        self.render = render
        self.onFrame = onFrame
    }

    /// Stash the newest tile and kick the drain if idle. Never blocks the caller.
    func submit(_ tile: OKLabTile) {
        lock.lock()
        pending = tile
        let kick = !draining
        if kick { draining = true }
        lock.unlock()
        guard kick else { return }            // a drain is already running; it will pick this up
        queue.async { [weak self] in self?.drain() }
    }

    /// Render newest-available tiles until the latch is empty. `pending` and
    /// `draining` are only ever touched under `lock`, so there is no lost wakeup:
    /// a `submit` racing the empty check either lands before the read (rendered
    /// this pass) or after `draining=false` (kicks a fresh drain).
    private func drain() {
        while true {
            lock.lock()
            let tile = pending
            pending = nil
            if tile == nil { draining = false; lock.unlock(); return }
            lock.unlock()
            if let tile, let frame = render(tile) { onFrame(frame) }
        }
    }
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
    /// V2.1 (Feature.v21Capture only): the last burst's time-pooled camera-box probability field
    /// `[y,x,3,256]` Int32 counts. Folded into `Surface.v21Counts` at commit so the review bench's
    /// FIELD / AIRDROP use the true camera histogram instead of the index-cube proxy. nil otherwise.
    var v21Counts: [Int32]? = nil

    /// The current deterministic-core stage banner (quantize → dither →
    /// significance → palette → encode), or nil when not rendering deterministically.
    /// Surfaces the verified Zig pipeline as the thing the user watches run.
    var deterministicStage: String? = nil

    /// GIFA-build progress in [0,1], driving the on-grid serpentine "resolve sweep"
    /// loading state (no spinner). Monotonic across the real build stages; reset to 0
    /// at capture start. The 5 deterministic kernels map to fifths; the GPU fallback
    /// degrades to two bands (stageA, encode).
    var loadingProgress: Double = 0

    /// The latest streamed render PARTIAL — the real in-progress GIFA cube + its frame-0
    /// palette, surfaced per deterministic stage so the loading sweep paints the actual
    /// `raw→quantize→dither→palette` process in TRUE colours (not a synthetic placeholder).
    /// `SurfaceView` folds these into σ while the surface is `.rendering`.
    var renderPartialCube: [UInt8] = []
    var renderPartialPalette: [SIMD3<UInt8>] = []

    /// Set the deterministic stage label + advance `loadingProgress` to that stage's
    /// fraction (stage k of n complete = k/n). One place so every render path stays
    /// consistent.
    private func surfaceDeterministicStage(_ stage: DeterministicRenderer.Stage) {
        deterministicStage = stage.rawValue
        let all = DeterministicRenderer.Stage.allCases
        let i = all.firstIndex(of: stage) ?? 0
        loadingProgress = Double(i + 1) / Double(all.count)
    }

    /// Publish a streamed render partial onto the observable spine (MainActor). Read by
    /// `SurfaceView`'s `renderPartialCube` observer and folded into σ.
    private func surfaceRenderPartial(_ p: DeterministicRenderer.StagePartial) {
        renderPartialPalette = p.palette
        renderPartialCube = p.indicesFlat   // set the cube LAST so its observer sees both
    }

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

    /// The live 64×64 camera tile as INDEXED cells (row-major `y*64 + x`) + its paired
    /// sRGB palette — the σ-pure form of `previewTile` (no `UIImage` on the state spine).
    /// `SurfaceView` folds these into σ so `LivePhaseField` paints the REAL camera through
    /// the cell grid (replacing the synthetic palette scroll). Empty until the first
    /// quantized frame; empty also on the raw-downsample fallback path.
    var previewIndexTile: [UInt8] = []
    var previewPalette: [SIMD3<UInt8>] = []

    /// The live 256-colour palette of the current scene (sRGB8), recomputed from the
    /// preview tile at ~3 fps (maximin, off the delegate queue). Drives the capture
    /// screen's 16×16 palette grid + the 4×4 Haar shutter (the abstraction cascade,
    /// ADR-5). Empty until the first throttled compute lands.
    var livePalette: [SIMD3<UInt8>] = []
    /// Throttle for `livePalette` (~3 fps; the maximin-256 is cheap but not free).
    @ObservationIgnored nonisolated(unsafe) private var lastLivePaletteNanos: UInt64 = 0

    /// Snapshot of `settings.useDeterministicCore` read off the delegate queue
    /// by the preview callback, so the live 64×64 canvas shows the deterministic
    /// quantized look (vs the raw downsample). Updated on bootstrap and capture.
    @ObservationIgnored nonisolated(unsafe) private var previewQuantized = true

    /// The CHEAP dither the live preview renders with, snapshotted off the delegate
    /// queue (mode 0 = FS, 1 = Atkinson). Blue-noise (mode 2/3) needs a per-frame STBN
    /// slice + temporal context a single live frame can't supply, so the preview shows
    /// FS for it and the HUD labels the divergence (`previewSamplerNote`). Keeps the
    /// hero WYSIWYG for the common error-diffusion case (#2).
    @ObservationIgnored nonisolated(unsafe) private var previewDitherMode = 0
    @ObservationIgnored nonisolated(unsafe) private var previewSerpentine = false

    /// Off-delegate-queue preview renderer for the burst (built per capture, torn
    /// down in the `capture()` defer). The camera intake queue only `submit`s the
    /// newest tile here; the heavy render runs on this renderer's own queue.
    @ObservationIgnored private var previewRenderer: CoalescingFrameRenderer?

    /// Re-snapshot the preview engine + dither from the current settings. Called on
    /// bootstrap, on capture, and on any live Settings change (CaptureView `.onChange`)
    /// so a mid-session sampler flip isn't stale on the hero.
    func syncPreviewDither() {
        previewQuantized = settings.useDeterministicCore
        let c = settings.ditherConfig
        switch c.method {
        case .errorDiffusion:
            previewDitherMode = (c.kernel == .floydSteinberg) ? 0 : 1
            previewSerpentine = c.serpentine
        case .blueNoise:
            previewDitherMode = 0       // STBN/temporal can't render per live frame
            previewSerpentine = false
        }
    }

    /// Honest note when the live preview diverges from what the EXPORT will be —
    /// nil when the hero is already WYSIWYG. Shown under the preview so the 384pt
    /// hero never silently implies blue-noise or the global-collapse look.
    var previewSamplerNote: String? {
        guard previewQuantized else { return nil }
        var parts: [String] = []
        if settings.ditherConfig.method == .blueNoise { parts.append("FS shown · blue-noise on export") }
        if Feature.globalPaletteV2 && settings.paletteScope == .global { parts.append("per-frame shown · global on export") }
        return parts.isEmpty ? nil : "preview: " + parts.joined(separator: " · ")
    }

    /// Live scene readout from the preview — the diversity gauge + dominant
    /// hue the capture screen reflects. EMA-smoothed (see `ingestSceneReadout`)
    /// so the gauge and tint glide rather than jitter at 10 fps.
    private(set) var scene: SceneReadout = .empty

    /// Live diversity ∈ [0,1] for the shutter gauge.
    var sceneGauge: Float { scene.gauge }

    /// Dominant scene hue, softened for chrome legibility (the buttons + the
    /// gauge ring take this). Falls back to white at zero diversity.
    var sceneTint: Color { SFTheme.accent(scene.tint) }

    /// Raw dominant scene tint (sRGB8) for the background cell field — darkened +
    /// tiled by `CellField`, so the whole screen responds to the live camera.
    var sceneGroundTint: SIMD3<UInt8> { scene.tint }

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

    /// The fully-built capture stack, returned across the actor hop from the
    /// off-main builder. Every member is already `Sendable` (MetalPipeline /
    /// CaptureSession are `@unchecked Sendable`, PaletteEngines is `Sendable`,
    /// GeneStore is an actor, CaptureBundle is a `Sendable` value), so the
    /// value crosses back to the `@MainActor` with compiler-checked race safety —
    /// no `nonisolated(unsafe)`, no warnings.
    private struct BuiltStack: Sendable {
        let pipeline: MetalPipeline
        let session: CaptureSession
        let engines: PaletteEngines
        let store: GeneStore
        let restoredBundle: CaptureBundle?
    }

    /// Build the entire heavy capture stack OFF the main actor. Because this is a
    /// `nonisolated async` function (SE-0338), it runs on the cooperative
    /// background executor even though it has no internal suspension point — so the
    /// `await` from `bootstrap()` frees the main thread, letting SwiftUI commit the
    /// first frame (StageGround + the bootstrap phase field) while the camera's ISP
    /// negotiation (`MetalPipeline` shader compiles + `CaptureSession.configure()` →
    /// `selectHDRFormat` probe loop) runs here. This is THE launch-stall fix: none
    /// of this blocking work touches the main thread anymore.
    private nonisolated static func buildCaptureStack(
        tileSide: Int, fps: Int, frameCount: Int
    ) async throws -> BuiltStack {
        let pipeline = try MetalPipeline(tileSide: tileSide)
        let session  = try CaptureSession(targetFps: fps, targetFrameCount: frameCount)
        // CaptureSession.init -> configure() -> selectHDRFormat settles
        // activeColorSpaceTag synchronously on THIS (builder) thread before
        // returning, establishing happens-before; this write runs in the builder's
        // sole-ownership window (the object is not yet published to the main actor),
        // so it is race-free without locking. Copy it to the pipeline so the Metal
        // kernel decodes YCbCr10 against the right OETF + RGB primaries instead of
        // always assuming Rec.709.
        pipeline.colorSpaceTag = session.activeColorSpaceTag.rawValue

        let store = try GeneStore()
        let engines = PaletteEngines(
            kMeans:   try KMeansPalettePipeline(tileSide: tileSide),
            blueNoise: try? BlueNoisePalettePipeline()
        )
        // Best-effort restore of the most-recent CaptureBundle, off-main (a
        // multi-MB JSON parse that must NOT block the launch). Failure is ignored —
        // persistence is a nice-to-have, not a critical path.
        let bundle = (try? CaptureBundle.load()) ?? nil
        return BuiltStack(pipeline: pipeline, session: session,
                          engines: engines, store: store, restoredBundle: bundle)
    }

    func bootstrap() async {
        // Launch trace via NSLog (device-visible, unlike os_log .debug). The FFI probe (expect 42)
        // proves the native Zig lib loaded + the C ABI works BEFORE anything else, killing or
        // confirming the native-lib hypothesis in one line. Each step is bracketed so the LAST
        // "SF-" line printed on a crashed launch localizes the fault.
        NSLog("SF-B: bootstrap start; ffi probe(41)=\(SixFourNative.probe(41)) (expect 42)")
        // Route the Zig core's pushed log lines into Console (category native.zig)
        // so every deterministic kernel call leaves visible evidence it ran.
        SixFourNative.installLogging()
        NSLog("SF-C: installLogging done")
        do {
            let authorized = await CaptureSession.requestAuthorization()
            NSLog("SF-D: camera authorized=\(authorized)")
            guard authorized else {
                phase = .unauthorized
                return
            }
            // STRUCTURAL suspension: `buildCaptureStack` is `nonisolated async`, so
            // awaiting it hops OFF the main actor (even though camera auth above did
            // not suspend when already authorized). The main thread is freed here →
            // SwiftUI commits the first frame while the camera spins up.
            NSLog("SF-E: building capture stack OFF-MAIN")
            let built = try await Self.buildCaptureStack(tileSide: 64, fps: 20, frameCount: 64)
            NSLog("SF-G: capture stack built; publishing on MainActor")

            // ---- back on @MainActor: publish the finished objects + wire preview ----
            let pipeline = built.pipeline
            let session  = built.session
            self.pipeline = pipeline
            self.engines  = built.engines
            self.session  = session
            self.store    = built.store
            // Restored CaptureBundle (loaded off-main). Populates `currentBundle`
            // only — no GIF is rendered automatically; the rendered GIF for an old
            // bundle is gone, and re-running the full render on bootstrap would be a
            // surprising hidden cost. Future "open old captures" UI will surface this.
            if let loaded = built.restoredBundle {
                self.currentBundle = loaded
                Self.logger.debug("[viewmodel] restored CaptureBundle id=\(loaded.id, privacy: .public)")
            }
            Self.logger.debug(
                "[viewmodel] propagated colorSpaceTag=\(session.activeColorSpaceTag.label, privacy: .public) to MetalPipeline"
            )

            // Wire the live 64×64 preview path. The callback runs on
            // the session's delegateQueue; we marshal the OKLab→UIImage
            // conversion + assignment to the MainActor here so the
            // SwiftUI binding fires cleanly. This wiring stays on the main
            // actor (it captures `@MainActor self`); only the heavy
            // construction above moved off-main.
            session.previewPipeline = pipeline
            syncPreviewDither()
            session.previewCallback = { [weak self] tile in
                guard let self else { return }
                // The "well done" 64×64: show the deterministic quantized look
                // live (the actual GIF aesthetic), or the raw downsample if the
                // deterministic engine is off.
                let frame: PreviewFrame = self.previewQuantized
                    ? Self.makeQuantizedPreviewImage(from: tile, mode: self.previewDitherMode,
                                                     serpentine: self.previewSerpentine)
                    : PreviewFrame(image: Self.makePreviewImage(from: tile), indices: [], palette: [])
                guard frame.image != nil else { return }
                // Analyse on the Metal completion queue (cheap, ~0.1 ms) so we
                // don't hop to the main actor twice; publish both together. The
                // diversity gauge reads the RAW tile (true scene colour), not the
                // quantized preview.
                let readout = LivePreviewAnalysis.analyze(tile)
                // Capture the value parts (the index tile + palette are Sendable; the
                // UIImage matches the existing main-actor hop pattern).
                let img = frame.image, idx = frame.indices, pal = frame.palette
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.previewTile = img
                    self.previewIndexTile = idx          // the REAL camera cells for the live hero
                    self.previewPalette = pal
                    self.ingestSceneReadout(readout)
                }
                // Throttled live palette (~3 fps) for the capture-screen cascade
                // (16×16 grid + 4×4 Haar shutter). Maximin-only (lloydIters 0) keeps
                // it cheap; the real capture re-quantizes per frame at full quality.
                let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                if now &- self.lastLivePaletteNanos > 330_000_000 {
                    self.lastLivePaletteNanos = now
                    if let pal = Self.computeLivePalette(from: tile) {
                        Task { @MainActor [weak self] in self?.livePalette = pal }
                    }
                }
            }

            NSLog("SF-H: starting preview")
            session.startPreview()                  // already Task.detached internally
            NSLog("SF-I: bootstrap complete -> idle")
            phase = .idle
        } catch {
            NSLog("SF-X: bootstrap THREW (handled): \(String(describing: error))")
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
                Self.logger.debug("[viewmodel] CaptureBundle saved to disk")
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
        syncPreviewDither()  // keep the live look in sync with the engine + sampler
        Haptics.impact(.medium)
        loadingProgress = 0      // fresh resolve sweep for this capture
        phase = .locking
        let lockResult = await session.lockExposureAndWhiteBalance(timeoutMs: 400)
        Self.logger.debug("[viewmodel] AE/AWB lock: \(String(describing: lockResult), privacy: .public)")

        phase = .capturing(progress: 0)
        // Stream each captured frame into the SAME preview the live feed uses, so
        // the screen animates the burst (≈20 fps) instead of freezing, and advance
        // the progress 0→1. Runs on the Metal completion queue; marshal to main.
        let burstTotal = session.targetFrameCount
        // Snapshot the preview look ONCE (constant for the burst) so the renderer's
        // @Sendable closure doesn't reach back into main-actor state per frame.
        let quantized = previewQuantized
        let mode = previewDitherMode
        let serpentine = previewSerpentine
        let renderer = CoalescingFrameRenderer(
            render: { tile in
                quantized
                    ? Self.makeQuantizedPreviewImage(from: tile, mode: mode, serpentine: serpentine)
                    : PreviewFrame(image: Self.makePreviewImage(from: tile), indices: [], palette: [])
            },
            onFrame: { [weak self] frame in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // Stream the newest captured frame into σ so the capturing hero shows the latest
                    // landed frame forward (no freeze). The reverse-cursor accumulation was removed
                    // (the preview renderer coalesces, so a per-frame build isn't available here).
                    self.previewTile = frame.image
                    guard !frame.indices.isEmpty else { return }
                    self.previewIndexTile = frame.indices
                    self.previewPalette = frame.palette
                }
            }
        )
        previewRenderer = renderer
        session.burstFrameCallback = { [weak self] tile, n in
            guard self != nil else { return }
            // The delegate (camera intake) queue does only this: hand the newest
            // tile to the off-queue renderer (O(1), non-blocking) and tick progress.
            // The heavy quantize+CGImage build never runs here, so back-pressure
            // can't drop recorded burst frames.
            renderer.submit(tile)
            Task { @MainActor [weak self] in
                self?.phase = .capturing(progress: Double(n) / Double(max(1, burstTotal)))
            }
        }
        do {
            defer {
                session.unlockExposureAndWhiteBalance()
                session.burstFrameCallback = nil
                previewRenderer = nil
            }
            let result = try await session.captureBurst(into: pipeline)
            lastTimingSummary = result.timing.summary
            v21Counts = result.v21Counts   // camera-box field (gated); nil keeps the proxy path
            Self.logger.debug("[viewmodel] burst complete: \(result.timing.summary, privacy: .public)")

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

        // The deterministic fixed-point Zig core is the default render path: it
        // surfaces each stage as it runs and yields a byte-reproducible GIF. The
        // GPU float path below is a silent fallback only if a kernel ever fails.
        if settings.useDeterministicCore {
            do {
                return try await renderDeterministic(
                    tiles: tiles, dither: dither, baseURL: baseURL, sheetURL: sheetURL, summary: summary
                )
            } catch {
                deterministicStage = nil
                Self.logger.error("[viewmodel] deterministic core failed; falling back to GPU path: \(String(describing: error), privacy: .public)")
            }
        }

        let onPhase: @Sendable (GIFRenderer.RenderPhase) -> Void = { stage in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch stage {
                case .stageA: self.phase = .renderingStageA; self.loadingProgress = 0.5
                case .encode: self.phase = .renderingEncode; self.loadingProgress = 0.9
                }
            }
        }

        let renderer = GIFRenderer(dither: dither, engines: engines)
        let report = try await Task.detached(priority: .userInitiated) {
            try await renderer.render(tiles: tiles, to: baseURL, fps: SFTheme.gifFrameRate, onPhase: onPhase)
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
            perFrameMSE: report.perFrameMSE,
            frameIndicesForVoxels: report.frameIndices
        )
        return RenderResult(output: output, perFrameStatistics: report.perFrameStatistics)
    }

    /// Render via the deterministic fixed-point Zig core, surfacing each stage as
    /// a banner and producing a byte-reproducible GIF (with its SHA-256). The
    /// same Complete/Significant voxel brands gate the bytes; per-frame numbers
    /// are computed in the same integer domain so Review stays honest.
    private func renderDeterministic(
        tiles: [OKLabTile],
        dither: DitherConfig,
        baseURL: URL,
        sheetURL: URL,
        summary: String
    ) async throws -> RenderResult {
        // GIFB: one global palette (collapse + whole-GIF rescue), gated by the
        // whole-GIF brands. Routed by the user's paletteScope toggle.
        //
        // ⚠️ V2-DEFERRED-GLOBAL-PALETTE — global (GIFB) collapse path, deferred to V2 behind
        // Feature.globalPaletteV2 (false in MVP1 ⇒ this branch is statically unreachable). Kept,
        // compiled, and golden-gated for V2; MVP1 is per-frame only.
        // See docs/SIXFOUR-GLOBAL-PALETTE-RETIREMENT-WORKFLOW.md §2 (GS1 + SAN). Do not add new callers.
        // GS1 + SAN: gate on the flag AND coerce a stale persisted `.global` to per-frame.
        let paletteScope: PaletteScope = Feature.globalPaletteV2 ? settings.paletteScope : .perFrame
        if paletteScope == .global {
            return try await renderDeterministicGlobal(
                tiles: tiles, dither: dither, baseURL: baseURL, sheetURL: sheetURL, summary: summary
            )
        }
        let start = ContinuousClock().now
        phase = .renderingStageA   // busy + spinner; the granular stage rides on `deterministicStage`
        let comment = "SixFour deterministic core · \(tiles.count)×\(tiles.first?.side ?? 64)² · K=\(SixFourShape.K)"
        let renderer = DeterministicRenderer(dither: dither)

        let result = try await Task.detached(priority: .userInitiated) {
            try renderer.render(tiles: tiles, comment: comment, onStage: { stage in
                Task { @MainActor [weak self] in self?.surfaceDeterministicStage(stage) }
            }, onPartial: { _, partial in
                // Stream the real per-stage buffer onto σ so the sweep shows the true process.
                Task { @MainActor [weak self] in self?.surfaceRenderPartial(partial) }
            })
        }.value
        deterministicStage = nil

        // Same unforgeable gates as the GPU path — the deterministic bytes must
        // still be a complete, all-significant voxel volume.
        guard let volume = CompleteVoxelVolume(checkingFrames: result.frameIndices) else {
            throw GIFEncoderError.incompleteVoxelVolume
        }
        guard SignificantVoxelVolume(complete: volume, cells: result.cells) != nil else {
            throw GIFEncoderError.insignificantVoxelVolume
        }

        try result.gifData.write(to: baseURL)

        // Contact sheet is best-effort (same as the GPU path).
        do {
            try await Task.detached(priority: .utility) {
                try ContactSheet.writePNG(tiles: tiles, to: sheetURL)
            }.value
        } catch {
            Self.logger.error("Contact sheet failed: \(String(describing: error))")
        }
        let contact: URL? = FileManager.default.fileExists(atPath: sheetURL.path) ? sheetURL : nil

        let totalMs = PaletteGenerator.milliseconds(ContinuousClock().now - start)
        let perFrameSignificant = result.cells.map {
            $0.filter { $0.count >= SixFourSignificance.minPopulation }.count
        }

        let output = CaptureOutput(
            gifURL: baseURL,
            contactURL: contact,
            renderMillis: totalMs,
            stageAMillis: totalMs,
            encodeMillis: result.stageMillis.last ?? 0,
            fileSize: result.gifData.count,
            timingSummary: summary,
            palettesForDisplay: result.srgbPalettes,
            ditherMethod: dither.method,
            meanExtractMSE: result.meanExtractMSE,
            meanCentroidConditionNumber: .nan,   // GPU-path diagnostic; N/A here
            meanAdmissionRateAt05: 0,            // GPU-path diagnostic; N/A here
            perFrameCells: result.cells,
            perFrameSignificant: perFrameSignificant,
            perFrameCoverage: result.perFrameCoverage,
            perFrameMSE: result.perFrameMSE,
            frameIndicesForVoxels: result.frameIndices,
            deterministic: true,
            sha256: result.sha256Hex,
            stageMillis: result.stageMillis
        )
        // No per-frame ClusterStatistics on this path (editing tools are future);
        // the CaptureBundle records an empty stats array.
        return RenderResult(output: output, perFrameStatistics: [])
    }

    /// GIFB: collapse the 64 per-frame palettes into ONE global palette (owned Zig
    /// `s4_global_collapse`) + whole-GIF significance rescue, then gate the bytes
    /// with the WHOLE-GIF brands. A global palette cannot pass the per-frame
    /// `CompleteVoxelVolume` (a frame need not use all K shared colours), so
    /// `GlobalCompleteVolume` (union-surjective onto K) + `GlobalSignificantVolume`
    /// (every slot ≥ minPopulation pooled) are the correct unforgeable gates.
    private func renderDeterministicGlobal(
        tiles: [OKLabTile],
        dither: DitherConfig,
        baseURL: URL,
        sheetURL: URL,
        summary: String
    ) async throws -> RenderResult {
        let start = ContinuousClock().now
        phase = .renderingStageA
        let comment = "SixFour deterministic core · GLOBAL palette · \(tiles.count)×\(tiles.first?.side ?? 64)² · K=\(SixFourShape.K)"
        let renderer = DeterministicRenderer(dither: dither)

        let branching = settings.paletteBranching   // the radix = the NN genome
        // Color Atlas RETIRED (branch spec/retire-ab-one-truth): the curated-palette injection
        // is gone with the A/B subsystem; the render path always uses the deterministic global
        // palette (exactly the former flag-off path, which was byte-identical).
        let curatedLeaves: [SIMD3<Int32>]? = nil
        let g = try await Task.detached(priority: .userInitiated) {
            try renderer.renderGlobalPalette(tiles: tiles, comment: comment, branching: branching,
                                             curatedLeavesQ16: curatedLeaves) { stage in
                Task { @MainActor [weak self] in self?.surfaceDeterministicStage(stage) }
            }
        }.value
        deterministicStage = nil

        // Whole-GIF brands (replace the per-frame CompleteVoxelVolume gate).
        guard let complete = GlobalCompleteVolume(checkingFrames: g.frameIndices) else {
            throw GIFEncoderError.incompleteVoxelVolume
        }
        guard GlobalSignificantVolume(complete: complete, pooledCounts: g.pooledCounts) != nil else {
            throw GIFEncoderError.insignificantVoxelVolume
        }

        try g.gifData.write(to: baseURL)
        do {
            try await Task.detached(priority: .utility) {
                try ContactSheet.writePNG(tiles: tiles, to: sheetURL)
            }.value
        } catch {
            Self.logger.error("Contact sheet failed: \(String(describing: error))")
        }
        let contact: URL? = FileManager.default.fileExists(atPath: sheetURL.path) ? sheetURL : nil
        let totalMs = PaletteGenerator.milliseconds(ContinuousClock().now - start)

        // One global palette shared by every frame. The per-frame Review fields
        // describe each frame's USE of that shared palette: cells are synthesised
        // from the whole-GIF pooled populations (the palette is fully significant by
        // the brand), and `perFrameSignificant` is each frame's distinct-colour count.
        let k = SixFourShape.K
        let minPop = SixFourSignificance.minPopulation
        let globalCells: [SixFourSignificantCell] = (0..<k).map { j in
            let lab = g.globalLeavesQ16[j]
            let mean = SIMD3<Float>(Float(lab.x) / 65536, Float(lab.y) / 65536, Float(lab.z) / 65536)
            let n = g.pooledCounts[j]
            return SixFourSignificantCell(mean: mean, stdDev: .zero, count: n,
                                          provenance: n >= minPop ? .extracted : .degenerate)
        }
        let palettesForDisplay = Array(repeating: g.globalPalette, count: tiles.count)
        let cells = Array(repeating: globalCells, count: tiles.count)
        let perFrameSignificant = g.frameIndices.map { Set($0).count }
        let perFrameCoverage = Array(repeating: g.globalCoverage, count: tiles.count)
        let meanMSE = g.perFrameMSE.isEmpty ? 0 : g.perFrameMSE.reduce(0, +) / Float(g.perFrameMSE.count)

        let output = CaptureOutput(
            gifURL: baseURL,
            contactURL: contact,
            renderMillis: totalMs,
            stageAMillis: totalMs,
            encodeMillis: g.stageMillis.last ?? 0,
            fileSize: g.gifData.count,
            timingSummary: summary,
            palettesForDisplay: palettesForDisplay,
            ditherMethod: dither.method,
            meanExtractMSE: meanMSE,
            meanCentroidConditionNumber: .nan,
            meanAdmissionRateAt05: 0,
            perFrameCells: cells,
            perFrameSignificant: perFrameSignificant,
            perFrameCoverage: perFrameCoverage,
            perFrameMSE: g.perFrameMSE,
            frameIndicesForVoxels: g.frameIndices,
            deterministic: true,
            sha256: g.sha256Hex,
            stageMillis: g.stageMillis
        )
        return RenderResult(output: output, perFrameStatistics: [])
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

    /// The live 256-colour palette of one preview tile: OKLab → Q16 → maximin (no
    /// Lloyd) → sRGB8. Runs on the delegate queue, throttled by the caller. Mirrors
    /// the capture path's quantizer at preview speed for the on-screen cascade.
    nonisolated private static func computeLivePalette(from tile: OKLabTile) -> [SIMD3<UInt8>]? {
        guard tile.pixels.count == tile.side * tile.side, tile.pixels.count >= 256 else { return nil }
        let q16 = SixFourNative.oklabToQ16(tile.pixels)
        guard let q = SixFourNative.quantizeFrame(oklabQ16: q16, k: 256, lloydIters: 0),
              let srgb = SixFourNative.paletteToSRGB8(centroidsQ16: q.centroids, k: 256) else { return nil }
        return (0 ..< 256).map { SIMD3<UInt8>(srgb[$0 * 3], srgb[$0 * 3 + 1], srgb[$0 * 3 + 2]) }
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
        return image(fromRGBA: bytes, side: side)
    }

    /// The "well done" 64×64: the live tile pushed through the deterministic Zig
    /// spine (maximin quantize → dither → palette), so the canvas shows the
    /// ACTUAL 256-colour output look while you compose — not a smooth downsample.
    /// ~3–4 ms/frame at the 10 fps preview rate; falls back to the raw image if a
    /// kernel ever declines. Pure/nonisolated — called from the live preview
    /// callback and, during a burst, from `CoalescingFrameRenderer`'s own queue
    /// (NOT the camera delegate queue, so it can't back-pressure recorded frames).
    /// The deterministic quantized preview as both the drawn image AND the raw index tile +
    /// palette behind it — so the live hero can paint INDEXED cells (σ-pure, no `UIImage` on
    /// the state spine) while the burst path still gets a `UIImage`. `indices` empty ⇒ the
    /// raw fallback ran (no quantized tile available).
    struct PreviewFrame {
        let image: UIImage?
        let indices: [UInt8]              // 64×64 nearest-centroid+dither map (row-major y*64+x)
        let palette: [SIMD3<UInt8>]       // the tile's own sRGB palette (paired with `indices`)
    }

    nonisolated private static func makeQuantizedPreviewImage(from tile: OKLabTile,
                                                               mode: Int, serpentine: Bool) -> PreviewFrame {
        let side = tile.side
        let pixelCount = side * side
        let k = SixFourShape.K
        guard tile.pixels.count == pixelCount else {
            return PreviewFrame(image: nil, indices: [], palette: [])
        }

        let q16 = SixFourNative.oklabToQ16(tile.pixels)
        // Suppress the per-kernel Zig logs for this ~10 fps preview frame so they
        // don't flood the log stream; the capture render (other thread) still logs.
        return SixFourNative.withZigLogsSuppressed {
            guard let quant = SixFourNative.quantizeFrame(oklabQ16: q16, k: k, lloydIters: 0),
                  let indices = SixFourNative.ditherFrame(
                      oklabQ16: q16, centroids: quant.centroids, k: k,
                      mode: mode, serpentine: serpentine, stbnSlice: nil),  // configured cheap dither (#2)
                  let palette = SixFourNative.paletteToSRGB8(centroidsQ16: quant.centroids, k: k)
            else {
                // Graceful fallback to the raw look — no index tile in this branch.
                return PreviewFrame(image: makePreviewImage(from: tile), indices: [], palette: [])
            }

            var bytes = [UInt8](repeating: 255, count: pixelCount * 4)
            for i in 0..<pixelCount {
                let c = Int(indices[i]) * 3
                let base = i * 4
                bytes[base + 0] = palette[c + 0]
                bytes[base + 1] = palette[c + 1]
                bytes[base + 2] = palette[c + 2]
            }
            var pal: [SIMD3<UInt8>] = []
            pal.reserveCapacity(k)
            for j in 0..<k { pal.append(SIMD3(palette[j * 3], palette[j * 3 + 1], palette[j * 3 + 2])) }
            return PreviewFrame(image: image(fromRGBA: bytes, side: side), indices: indices, palette: pal)
        }
    }

    /// Build an opaque sRGB `UIImage` from a `side×side` RGBA8 buffer, with
    /// interpolation off (the 64×64 pixels stay hard under upscale).
    nonisolated private static func image(fromRGBA bytes: [UInt8], side: Int) -> UIImage? {
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
