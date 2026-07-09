import Foundation
import AVFoundation
import CoreMedia
import os

/// AVCaptureVideoDataOutput-based 20 fps burst capture for SixFour.
///
/// Lifecycle:
///   1. `await CaptureSession.requestAuthorization()` once at app launch.
///   2. `let session = try CaptureSession()` — configures session.
///   3. `session.startPreview()` to start the AVCaptureSession running.
///   4. `let result = try await session.captureBurst(into: pipeline)` — fills the burst.
///
/// Pipeline architecture:
///   - Delegate queue receives a CMSampleBuffer at ~20 fps.
///   - It immediately submits to `MetalPipeline.submitAsync` (non-blocking) and returns.
///   - Metal's completion handler dispatches back onto the delegate queue to append.
///   - When count reaches `targetFrameCount`, timing stats are logged and the
///     burst future resolves.
final class CaptureSession: NSObject, @unchecked Sendable {

    static let log = Logger(subsystem: "com.sixfour.SixFour", category: "capture")

    let targetFps: Int
    let targetFrameCount: Int
    let session = AVCaptureSession()
    private(set) var device: AVCaptureDevice?
    private let dataOutput = AVCaptureVideoDataOutput()
    private let delegateQueue = DispatchQueue(label: "com.sixfour.capture.delegate", qos: .userInitiated)

    // Burst state — only mutated on `delegateQueue`.
    private var collecting = false
    private var collected: [OKLabTile] = []
    private var ptsSeconds: [Double] = []
    private var submittedCount = 0
    /// Frames dropped kernel-side during the active burst. The cadence is
    /// hardware-pinned (`activeVideoMin == MaxFrameDuration = 1/fps`), so the
    /// only thing that can break "truly 20 fps apart" is a dropped frame —
    /// which `alwaysDiscardsLateVideoFrames` would otherwise hide behind a
    /// silent ~2× interval. Counted here so the burst timing can report it.
    /// Only mutated on `delegateQueue`.
    private var droppedFrameCount = 0
    /// TROUBLESHOOT (2026-07-08): per-burst CPU cost of the yin-yang ladder tick
    /// (poolSums64 + ingest, synchronous on the delegate queue) — aggregated per
    /// tick, logged ONCE in `finishBurst`, reset with the other burst counters.
    private var tickCpuTotalUs: UInt64 = 0
    private var tickCpuMaxUs: UInt64 = 0
    private var tickCpuCount = 0
    private var pipelineRef: MetalPipeline?
    /// V2.1 (Feature.v21Capture only): the persistent burst histogram buffer the GPU accumulates the
    /// camera-box probability field into, one slice per frame. Allocated at burst start, pooled and
    /// released in `finishBurst`. nil keeps the shipped path untouched.
    private var v21HistBuffer: (any MTLBuffer)?
    private let v21Levels = 256
    private var continuation: CheckedContinuation<BurstResult, Error>?
    /// V3.0 seam relief: where the ASYNC flow encode delivers (set by the view model
    /// before a burst; runs on the detached encoder task, NOT the main actor). The Int
    /// is the BURST GENERATION the flow belongs to — the receiver MUST drop deliveries
    /// whose generation is not the current one (the stale-flow corruption gate).
    var flowCallback: (@Sendable (V21Flow?, Int) -> Void)?

    /// The camera-box-field twin of `flowCallback` (perf 2026-07-08): the field
    /// pool (~201M Int32 adds over the hist buffer) left the shutter seam — it
    /// used to run synchronously in `finishBurst` before the continuation
    /// resumed. The pooled `[y,x,3,256]` counts now arrive here (generation-
    /// tagged) from the same detached task that owns the buffer, ahead of the
    /// flow encode. `BurstResult.v21Counts` is nil by design, like `flow`.
    var v21CountsCallback: (@Sendable ([Int32]?, Int) -> Void)?

    /// The somatic-train twin of `flowCallback` (QoL 2026-07-03): θ_up training left
    /// the burst seam — it used to run synchronously in `finishBurst`, holding the
    /// capture screen until the GPU dispatch finished (the felt post-capture delay).
    /// The gene now arrives here (generation-tagged, possibly nil = the floor) and the
    /// engine folds it into σ late; `BurstResult.thetaUp` is nil by design, like `flow`.
    var thetaUpCallback: (@Sendable (CaptureGene.ThetaUp?, Int) -> Void)?

    /// YIN-YANG (Feature.yinYangBands only): the per-burst 16/32/64 ladder. Fresh
    /// per burst (its tick pairing is burst-relative), fed synchronously on
    /// `delegateQueue` right after each frame's GPU submission, drained at the
    /// burst seam. nil keeps the shipped path untouched.
    private var colorHead: ColorHead?
    /// The band-head twin of `thetaUpCallback`: the S_t yang head's training
    /// verdict (generation-tagged, nil = Metal unavailable, no pairs, or the
    /// certified floor was already exact — the floor ships, never an error) AND
    /// the per-slot certified-order vector (`haltFloor()`), the halting-depth
    /// budget that must survive to the render/influence path (A1, the
    /// KinematicHaltPrior keystone). Empty vector = the ladder was off.
    var bandHeadCallback: (@Sendable (BandHeadTrainer.Result?, [Int32], Int) -> Void)?

    /// INDEPENDENT LADDER (Feature.multiScaleLadder only): the burst-time weave
    /// driver — cycles REAL exposures across the interleaved schedule and
    /// accumulates the three independent per-rung volumes. Fresh per burst,
    /// constructed AND mutated only on `delegateQueue` (unlike the idle-preview
    /// `exposureDriver`, which predates that rule). nil keeps the shipped
    /// single-exposure burst path untouched.
    private var weaveDriver: BurstWeaveDriver?

    /// RUNG TELEMETRY (Feature.rungTelemetry only): the per-rung instrument
    /// snapshot, published from `delegateQueue` at the 16-rung cadence (every
    /// 4th tick = 5 Hz, coalesced — all three rungs ride ONE delivery) plus a
    /// final snapshot at the burst seam. The receiver marshals to the main
    /// actor. Works in BOTH modes: independent (weave driver) and derived
    /// (`ColorHead`, reported honestly as pooling-equivalent / maximal
    /// correlation). Generation-tagged inside the value (`flowCallback` rules).
    var rungTelemetryCallback: (@Sendable (RungTelemetry) -> Void)?

    /// SYSTEM TELEMETRY (Feature.rungTelemetry only): tick CPU vs the 50 ms
    /// budget, v21 hist-buffer lifecycle, camera system pressure. Published
    /// from `delegateQueue` ON CHANGE and at burst boundaries only.
    var systemTelemetryCallback: (@Sendable (SystemTelemetry) -> Void)?

    /// Where the per-burst v21 histogram buffer is in its life (delegateQueue-
    /// confined; feeds the system-telemetry region).
    private var v21BufferState: SystemTelemetry.V21BufferState = .none
    /// The burst generation `v21BufferState` belongs to — stamped at every
    /// burst-start state write. A PREVIOUS burst's detached flow-encode job can
    /// finish mid-next-burst; its completion may only downgrade the state to
    /// `.freed` if the state still belongs to ITS generation, so it never
    /// clobbers a newer burst's live `.allocated` (the ~384 MiB the meter
    /// exists to watch would otherwise read FREED while resident).
    private var v21BufferGeneration = 0

    /// Last observed `AVCaptureDevice.SystemPressureState` level, mapped 0…4
    /// (-1 = never observed). delegateQueue-confined.
    private var pressureRaw = -1

    /// KVO token for `device.systemPressureState` (publish on change only).
    private var pressureObservation: NSKeyValueObservation?

    /// Monotonic burst counter (delegateQueue-confined): stamps every async flow
    /// delivery so a late encode can never be attributed to a newer capture.
    private(set) var burstGeneration = 0

    /// True while a detached flow encode still holds its ~800 MB histogram buffer
    /// (delegateQueue-confined). A new burst SKIPS its own flow encode while set —
    /// two live buffers risk jetsam (device audit 2026-07-01); the skipped burst
    /// ships without a flow (the export's temporal-proxy fallback covers it).
    private var flowJobActive = false

    /// The detached flow-encode task's buffer handle (MTLBuffer is thread-safe for
    /// read-only accumulation results; the wrapper states that intent).
    private struct V21FlowJob: @unchecked Sendable { let buffer: any MTLBuffer }

    /// Per-burst latch — the first delivered sample buffer's
    /// `CMFormatDescription` is checked against x420; subsequent frames
    /// skip the read since pixel-format negotiation is fixed at
    /// addOutput time. Reset to `false` at every `captureBurst` start.
    private var firstFrameVerified = false

    // MARK: - Live 64×64 preview

    /// Persistent reference to the MetalPipeline used for both burst
    /// capture and idle preview. ViewModel assigns this once during
    /// bootstrap; the delegate uses it for preview submissions while
    /// `collecting == false`. Burst capture still passes a pipeline
    /// to `captureBurst(into:)` — usually the same instance — but the
    /// signature stays parameterized for testability.
    var previewPipeline: MetalPipeline?

    /// Callback fired with the latest 64×64 OKLab tile while the
    /// session is idle (no burst in progress). Throttled to ~10 fps
    /// via `previewMinIntervalNanos`. Set to nil to disable preview.
    /// The callback runs on `delegateQueue`, NOT the main actor —
    /// the receiver is responsible for dispatching UI updates.
    var previewCallback: (@Sendable (OKLabTile) -> Void)?

    /// LIVE-LADDER (Feature.liveLadder only): a persistent preview-side ColorHead that
    /// ingests the SAME idle x420 preview buffers as `previewCallback` (on `delegateQueue`,
    /// at the same 10 fps throttle) and realizes its 32²/16² rungs to sRGB8 for the
    /// inverted-pyramid preview. Constructed in `startPreview` when the flag is on, nil'd
    /// on `stopPreview`. INDEPENDENT of the per-burst `colorHead` (line 67): this one runs
    /// only while idle (`collecting == false`); the burst head runs only while collecting.
    /// nil ⇒ the whole live-ladder path is statically inert and the preview is exactly
    /// today's in-view pooling.
    private var previewColorHead: ColorHead?

    /// The realized-ladder twin of `previewCallback` (Feature.liveLadder only): the
    /// 32² (1024 RGB) and 16² (256 RGB) realized tiles, fired on `delegateQueue` after
    /// each throttled preview ingest. nil (or the flag off) keeps the shipped path
    /// untouched. Display-only — no GIF byte depends on it.
    var ladderCallback: (@Sendable ([SIMD3<UInt8>], [SIMD3<UInt8>]) -> Void)?

    /// THE FLUX BAR seam (THE DESIGN E6): the freshest 768-byte GCT (`ColorHead
    /// .latestGCT`), fired at the 16-rung realize cadence (every 4th ingested tick =
    /// 5 Hz) from whichever head is live — the per-burst `colorHead` during a burst,
    /// the preview head while idle (Feature.liveLadder). The UI differences
    /// CONSECUTIVE deliveries through `s4_v21_wdist1d` (paletteW1) — the wave meter.
    /// Fires on `delegateQueue`; the receiver marshals. Display-only.
    var gctCallback: (@Sendable ([UInt8]) -> Void)?

    /// OPTICAL-EV (Feature.opticalEV only): the single-camera exposure-bracket driver + its
    /// display-only ColorHead. Constructed in `startPreview` when the flag is on, fed every
    /// idle preview frame in `captureOutput`, torn down in `stopPreview`. nil ⇒ inert. The
    /// callback delivers one realized rung tile (side ∈ {64,32,16}) per SETTLED real exposure;
    /// fires on `delegateQueue`, receiver marshals to the main actor.
    private var exposureDriver: ExposureBracketDriver?
    private var opticalColorHead: ColorHead?
    var opticalTileCallback: (@Sendable (Int, [SIMD3<UInt8>]) -> Void)?

    /// Callback fired once per captured frame DURING a burst (`collecting ==
    /// true`), with the just-collected tile and the running count
    /// (`1...targetFrameCount`). Runs on the Metal completion queue (like
    /// `previewCallback`), NOT the main actor — the receiver marshals UI updates.
    /// This lets the preview show each frame as it captures instead of freezing
    /// on the last live frame for the whole burst. Set to nil to disable.
    var burstFrameCallback: (@Sendable (OKLabTile, Int) -> Void)?

    /// Last preview submission timestamp (nanoseconds since boot) for
    /// throttling. Only touched on `delegateQueue`.
    private var lastPreviewSubmitNanos: UInt64 = 0

    /// Throttle: 100 ms = 10 fps. Capture delegate fires at 20 fps, so
    /// every second frame becomes a preview submission.
    private static let previewMinIntervalNanos: UInt64 = 100_000_000

    /// Result of a completed 64-frame burst.
    struct BurstResult: Sendable {
        let tiles: [OKLabTile]
        let timing: BurstTiming
        /// V2.1 (Feature.v21Capture only): the time-pooled camera-box probability field
        /// `[y, x, 3, 256]` Int32 counts (the GPU `v21AccumulateHistKernel` pooled over the burst).
        /// nil when the flag is off or the buffer could not be allocated.
        let v21Counts: [Int32]?
        /// V2.1 (Feature.v21Capture only): the recovered TIME AXIS — a barycenter anchor plus per-frame
        /// RLE transport maps (`MetalPipeline.encodeV21Flow`), from which every per-frame slice and the
        /// model's GIF derive. Unlike `v21Counts` (pooled, time destroyed) this keeps the full
        /// `[t × value]` joint, so a MOVING capture stays trainable. nil when off/unavailable.
        let flow: V21Flow?
        /// V3.0 (Feature.v3SomaticTrain only): the per-capture SOMATIC gene — θ_up fine-tuned on
        /// this burst's own manufactured octant pairs (`CaptureGene.train`, one fused GPU dispatch).
        /// ALWAYS nil by design since QoL 2026-07-03 (like `flow`): training left the burst seam
        /// and the gene arrives late via `thetaUpCallback`. Its absence is the deterministic
        /// floor (zero-gene == floor); the decide surface attaches the gene when it lands.
        let thetaUp: CaptureGene.ThetaUp?
        /// Measured per-frame intervals in integer MICROSECONDS (63 values for a
        /// clean 64-frame burst; empty when < 2 frames landed). The capture
        /// record (`Spec.CaptureRecord`) persists these — the one place the
        /// float timestamps round to integers.
        let intervalsUs: [UInt64]
        /// The color head's final 16×16×3 u64 bin sums (Feature.yinYangBands
        /// only; nil otherwise) — the exact transitive carrier, snapshotted
        /// before the head is released.
        let sums16: [UInt64]?
        /// The color head's realized 768-byte GCT (Feature.yinYangBands only).
        let gct: [UInt8]?
        /// The per-rung u64 sum volumes (owned slices only, t-major),
        /// snapshotted at the burst seam for the capture record — the
        /// `recordSums16` pattern. Ladder mode (Feature.multiScaleLadder)
        /// fills all three independent cubes; derived mode fills `cube16`
        /// only (the ColorHead's retained 16-rung stream — the record's
        /// c16-only provenance signature). nil when neither ran.
        let rungCubes: RungCubes?
        /// The final per-rung telemetry snapshot (Feature.rungTelemetry only;
        /// nil otherwise) — the record phase persists its exposure/arrival/N/
        /// independence numbers (`Spec.CaptureRecord` v2 `ev`/`tel`).
        let rungTelemetry: RungTelemetry?
        /// The weave word actually executed (owner depth code per tick,
        /// `Spec.WeaveOrder`). Empty = the uniform single-exposure burst
        /// (today's all-zeros record word stands).
        let weaveWord: [UInt64]
    }

    /// The three per-rung sum volumes: each is `framesN` t-major slices of
    /// `side²·3` u64 sums. Ladder mode (Feature.multiScaleLadder) fills all
    /// three with only the frames the weave actually OWNED (settle/dropped
    /// ticks are skipped honestly and show up in the telemetry's `skipped`,
    /// never as zero slices here); derived mode fills `cube16` only, from the
    /// ColorHead's exactly-pooled 16-rung stream.
    struct RungCubes: Sendable {
        let cube64: [UInt64]
        let frames64: Int
        let cube32: [UInt64]
        let frames32: Int
        let cube16: [UInt64]
        let frames16: Int
    }

    /// Aggregate statistics over the 63 inter-frame intervals (in ms).
    ///
    /// Policy is **measure & warn only**: the 50 ms cadence is hardware-pinned,
    /// so these stats are surfaced for visibility — no burst is rejected and the
    /// GIF frame delay stays a uniform 5 cs. `worstAbsDeviationMs` and
    /// `droppedFrameCount` are the two numbers that reveal a real cadence break.
    struct BurstTiming: Sendable, Codable {
        let frameCount: Int
        let durationMs: Double
        let meanIntervalMs: Double
        let stdIntervalMs: Double
        let minIntervalMs: Double
        let maxIntervalMs: Double
        let targetIntervalMs: Double
        /// Largest |interval − target| over the burst (ms). 0 when < 2 frames.
        let worstAbsDeviationMs: Double
        /// Frames dropped kernel-side during the burst (0 == clean cadence).
        let droppedFrameCount: Int
        var summary: String {
            String(
                format: "%d frames in %.1f ms — interval mean %.2f ms (target %.2f), σ %.2f, min %.2f, max %.2f, worst Δ %.2f, dropped %d",
                frameCount, durationMs,
                meanIntervalMs, targetIntervalMs,
                stdIntervalMs, minIntervalMs, maxIntervalMs,
                worstAbsDeviationMs, droppedFrameCount
            )
        }

        enum CodingKeys: String, CodingKey {
            case frameCount, durationMs, meanIntervalMs, stdIntervalMs
            case minIntervalMs, maxIntervalMs, targetIntervalMs
            case worstAbsDeviationMs, droppedFrameCount
        }

        init(
            frameCount: Int, durationMs: Double, meanIntervalMs: Double,
            stdIntervalMs: Double, minIntervalMs: Double, maxIntervalMs: Double,
            targetIntervalMs: Double, worstAbsDeviationMs: Double, droppedFrameCount: Int
        ) {
            self.frameCount = frameCount
            self.durationMs = durationMs
            self.meanIntervalMs = meanIntervalMs
            self.stdIntervalMs = stdIntervalMs
            self.minIntervalMs = minIntervalMs
            self.maxIntervalMs = maxIntervalMs
            self.targetIntervalMs = targetIntervalMs
            self.worstAbsDeviationMs = worstAbsDeviationMs
            self.droppedFrameCount = droppedFrameCount
        }

        // Tolerant decode: capture bundles saved before worstAbsDeviationMs /
        // droppedFrameCount existed still restore (those fields default to 0
        // instead of throwing keyNotFound). encode(to:) stays synthesized.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            frameCount = try c.decode(Int.self, forKey: .frameCount)
            durationMs = try c.decode(Double.self, forKey: .durationMs)
            meanIntervalMs = try c.decode(Double.self, forKey: .meanIntervalMs)
            stdIntervalMs = try c.decode(Double.self, forKey: .stdIntervalMs)
            minIntervalMs = try c.decode(Double.self, forKey: .minIntervalMs)
            maxIntervalMs = try c.decode(Double.self, forKey: .maxIntervalMs)
            targetIntervalMs = try c.decode(Double.self, forKey: .targetIntervalMs)
            worstAbsDeviationMs = try c.decodeIfPresent(Double.self, forKey: .worstAbsDeviationMs) ?? 0
            droppedFrameCount = try c.decodeIfPresent(Int.self, forKey: .droppedFrameCount) ?? 0
        }
    }

    init(targetFps: Int = 20, targetFrameCount: Int = 64) throws {
        self.targetFps = targetFps
        self.targetFrameCount = targetFrameCount
        super.init()
        try configure()
    }

    static func requestAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    // MARK: - Configuration

    /// AVCam-canonical capture configuration for iPhone 17 Pro / iOS 26+.
    ///
    /// Order matters and is non-obvious:
    ///   1. addInput      — gets the video device into the session.
    ///   2. configure dataOutput (videoSettings = x420, delegate,
    ///      alwaysDiscardsLateVideoFrames).
    ///   3. addOutput     — connects the output to the input. This is the
    ///      point at which AVFoundation negotiates pixel format between
    ///      input and output; the videoSettings request must already be
    ///      set so the system knows we want 10-bit YCbCr.
    ///   4. selectHDRFormat — lockForConfiguration → activeFormat (x420)
    ///      → activeColorSpace (HLG_BT2020 or P3_D65) → unlock.
    ///   5. rotation + clamp frame rate.
    ///   6. commitConfiguration (via defer).
    ///
    /// We intentionally do NOT preflight `availableVideoPixelFormatTypes`:
    /// inside `beginConfiguration` it returns the conservative pre-commit
    /// list (8-bit only) on iOS 26 even when an x420 format is queued.
    /// The real verification is `CMFormatDescriptionGetMediaSubType` on the
    /// first delivered sample buffer (see the delegate). Defending here
    /// with the stale list rejects every iPhone 17 Pro build.
    ///
    /// We also DO NOT touch `isVideoHDREnabled` / `automaticallyAdjusts…` —
    /// those setters raise NSInvalidArgumentException on iOS 26 ("Not
    /// supported - use activeFormat.isVideoHDRSupported") and are ObjC
    /// exceptions that Swift `try` can't catch. HDR is implicit on iOS 17+:
    /// pick an HDR-capable activeFormat + activeColorSpace and the system
    /// delivers HDR.
    private func configure() throws {
        NSLog("SF-cfg1: configure begin (DEVICE-ONLY path; sim throws at noCamera below)")
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            Self.log.error("[capture] No back wide-angle camera available")
            throw CaptureError.noCamera
        }
        NSLog("SF-cfg2: device=\(device.localizedName)")
        self.device = device
        // SYSTEM TELEMETRY (Feature.rungTelemetry): observe the camera's
        // thermal/system pressure and publish ON CHANGE only (never polled,
        // never per-tick). The KVO handler runs on an arbitrary thread; state
        // lives on delegateQueue, so hop there before touching it.
        if Feature.rungTelemetry {
            pressureObservation = device.observe(\.systemPressureState, options: [.initial, .new]) {
                [weak self] dev, _ in
                let raw = Self.pressureLevelRaw(dev.systemPressureState.level)
                guard let self else { return }
                self.delegateQueue.async {
                    guard raw != self.pressureRaw else { return }
                    self.pressureRaw = raw
                    self.publishSystemTelemetry()
                }
            }
        }
        Self.log.debug("[capture] Device: \(device.localizedName, privacy: .public) modelID=\(device.modelID, privacy: .public)")

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CaptureError.cantAddInput }
        session.addInput(input)

        // Output config — DO NOT set videoSettings. On iOS 26 passing
        // a 10-bit pixel format raises NSException ("Unsupported pixel
        // format type - use -availableVideoCVPixelFormatTypes"), and
        // videoSettings is for *converting* the camera output to a
        // different format anyway. We want native delivery — leaving
        // videoSettings nil tells AVFoundation to deliver whatever
        // `activeFormat` dictates, which after `selectHDRFormat` below
        // will be x420 (10-bit YCbCr 4:2:0 video range).
        //
        // `alwaysDiscardsLateVideoFrames` is a GPU-stall safety net;
        // we drop late frames rather than backpressure the delegate
        // queue.
        dataOutput.alwaysDiscardsLateVideoFrames = true
        dataOutput.setSampleBufferDelegate(self, queue: delegateQueue)
        guard session.canAddOutput(dataOutput) else { throw CaptureError.cantAddOutput }
        session.addOutput(dataOutput)

        // Select HDR format + color space AFTER the output is in the
        // session. AVCam-canonical order; the output's negotiation sees
        // the activeFormat change at the right moment.
        NSLog("SF-cfg3: -> selectHDRFormat")
        try selectHDRFormat(on: device)
        NSLog("SF-cfg4: selectHDRFormat returned; wiring connection + frame rate")

        if let conn = dataOutput.connection(with: .video) {
            if conn.isVideoRotationAngleSupported(90) {
                conn.videoRotationAngle = 90
            }
        }

        try clampFrameRate(device: device, fps: targetFps)

        // Post-commit `availableVideoPixelFormatTypes` is the only
        // reliable query point — log for diagnostics only (no preflight).
        // The actual format verification lives in the delegate on the
        // first sample buffer.
        Self.log.debug(
            "[capture] availableVideoPixelFormatTypes (pre-commit, diagnostic only): \(Self.formatList(self.dataOutput.availableVideoPixelFormatTypes), privacy: .public)"
        )
    }

    /// Probe-and-set HDR format selection for iPhone 17 Pro / iOS 26.
    ///
    /// Picks a format whose **native mediaSubType is x420** AND whose
    /// data-output side (`availableVideoCVPixelFormatTypes`) actually
    /// lists x420 once the format is active. This is the load-bearing
    /// distinction on iPhone 17 Pro / iOS 26: large x420 formats
    /// (3840×2160) often deliver ONLY `btp2`
    /// (`kCVPixelFormatType_96VersatileBayerPacked12`) on the data
    /// output because the ISP can't do the btp2→YUV conversion at that
    /// resolution. Smaller x420 formats (HD-class) deliver real x420.
    ///
    /// Algorithm: build `(format, colorSpace)` candidate tuples for
    /// the cross of x420 + (HLG_BT2020 ∪ P3_D65). Sort by (HLG-before-P3,
    /// area ascending) so the smallest format that gives us HLG wins.
    /// Inside one `lockForConfiguration` scope, set each candidate as
    /// activeFormat, then query
    /// `dataOutput.availableVideoCVPixelFormatTypes`. Accept the first
    /// candidate that lists x420. Throw `noHLGOrP3FormatAvailable` if
    /// all candidates are output-excluded (btp2-trapped or worse).
    ///
    /// Per-candidate probe is NOT cheap: each `device.activeFormat =` /
    /// `device.activeColorSpace =` assignment is a real ISP reconfiguration
    /// (tens-to-hundreds of ms total across the ~9 candidates on iPhone 17 Pro).
    /// This is why `CaptureSession.init` must NOT run on the main actor — the
    /// caller (`CaptureViewModel.buildCaptureStack`) now constructs the session
    /// off-main so this loop can't block the first SwiftUI frame.
    ///
    /// Sources:
    ///   - Flutter issue #175828 + PR #11106 — same btp2 bug on
    ///     iPhone 17 Pro, validated workaround.
    ///   - Apple `videoSettings` docs — native delivery requires nil
    ///     videoSettings (the caller already leaves it unset).
    ///   - WWDC21 10047 / TN3121 — mediaSubType is the device-side
    ///     selector; this method adds the output-side probe Apple
    ///     didn't document for iOS 26.
    ///
    /// **Caller order** — must run AFTER `session.addOutput(dataOutput)`;
    /// `availableVideoCVPixelFormatTypes` only reflects the activeFormat
    /// once the output is connected to the session input.
    private func selectHDRFormat(on device: AVCaptureDevice) throws {
        let allFormats = device.formats
        let want10Bit: OSType = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        Self.log.debug("[capture] Scanning \(allFormats.count, privacy: .public) device formats for x420 (10-bit YCbCr 4:2:0) at \(self.targetFps, privacy: .public) fps…")

        // 1. Restrict to x420 formats at the target fps.
        let x420Candidates: [AVCaptureDevice.Format] = allFormats.filter { fmt in
            let st = CMFormatDescriptionGetMediaSubType(fmt.formatDescription)
            guard st == want10Bit else { return false }
            return fmt.videoSupportedFrameRateRanges.contains {
                Double(self.targetFps) >= $0.minFrameRate && Double(self.targetFps) <= $0.maxFrameRate
            }
        }

        // 2. Build (format, colorSpace) tuples for the cross of x420
        //    candidates × supported HLG/P3 color spaces. A single
        //    format can appear twice (once per supported color space).
        func area(_ f: AVCaptureDevice.Format) -> Int32 {
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            return Int32(d.width) * Int32(d.height)
        }
        struct Candidate {
            let format: AVCaptureDevice.Format
            let colorSpace: AVCaptureColorSpace
            let label: String
            let priority: Int   // 0 = HLG, 1 = P3
            let area: Int32
        }
        var hlgCount = 0
        var p3Count = 0
        var candidates: [Candidate] = []
        for fmt in x420Candidates {
            let a = area(fmt)
            if fmt.supportedColorSpaces.contains(.HLG_BT2020) {
                hlgCount += 1
                candidates.append(Candidate(format: fmt, colorSpace: .HLG_BT2020,
                                            label: "HLG_BT2020", priority: 0, area: a))
            }
            if fmt.supportedColorSpaces.contains(.P3_D65) {
                p3Count += 1
                candidates.append(Candidate(format: fmt, colorSpace: .P3_D65,
                                            label: "P3_D65", priority: 1, area: a))
            }
        }
        Self.log.debug("[capture] Found \(x420Candidates.count, privacy: .public) x420 formats at \(self.targetFps, privacy: .public) fps; \(hlgCount, privacy: .public) support HLG, \(p3Count, privacy: .public) support P3")

        // Sort by (priority ASC, area ASC) — HLG beats P3; within
        // bucket, smallest format wins. Small formats are the
        // btp2-trap-free zone on iPhone 17 Pro (the ISP can do the
        // btp2→YUV conversion when bandwidth allows).
        candidates.sort { a, b in
            if a.priority != b.priority { return a.priority < b.priority }
            return a.area < b.area
        }

        // 3. Probe each candidate inside one lockForConfiguration:
        //    set activeFormat + activeColorSpace, query
        //    availableVideoCVPixelFormatTypes; accept first that
        //    lists x420. Track excluded count for diagnostic.
        NSLog("SF-hdr1: \(x420Candidates.count) x420 formats, \(candidates.count) candidates; locking + probing")
        try device.lockForConfiguration()
        var accepted: Candidate? = nil
        var excludedCount = 0
        for cand in candidates {
            // The prime device-only suspects: ObjC property setters that can raise
            // NSInvalidArgumentException (uncatchable by Swift `try`) for a format/colour-space
            // combo this physical device rejects. Run them through the ObjC @try/@catch shim so an
            // exception becomes a thrown Swift error instead of aborting the process. Unlock on throw
            // (the lock is held here; later throw sites unlock manually too).
            NSLog("SF-hdr2: set activeFormat \(cand.label)")
            do {
                try SFObjC.catching {
                    device.activeFormat = cand.format
                    device.activeColorSpace = cand.colorSpace
                }
            } catch {
                device.unlockForConfiguration()
                Self.log.error("[capture] activeFormat/colorSpace setter raised: \(String(describing: error), privacy: .public)")
                throw error
            }
            // Post-assignment bracket: a device-only EXC_BAD_ACCESS inside the AVFoundation setter
            // is a Mach null-deref the ObjC @try/@catch shim CANNOT catch, so it prints SF-hdr2 with
            // NO following SF-hdr2b — localizing the exact probe step from the device Console.
            NSLog("SF-hdr2b: activeFormat/colorSpace set OK \(cand.label)")
            // Swift maps ObjC `availableVideoCVPixelFormatTypes` to
            // `availableVideoPixelFormatTypes` (the `CV` is stripped
            // by AVFoundation.apinotes rename). Same underlying
            // property — returns the formats the output can deliver
            // for the currently-set activeFormat. Per Apple header:
            // "This list can change if the activeFormat of the
            // AVCaptureDevice connected to the receiver changes."
            let available = dataOutput.availableVideoPixelFormatTypes
            let dims = CMVideoFormatDescriptionGetDimensions(cand.format.formatDescription)
            if available.contains(want10Bit) {
                Self.log.debug(
                    "[capture] Probing \(dims.width, privacy: .public)×\(dims.height, privacy: .public) \(cand.label, privacy: .public) → available=\(Self.formatList(available), privacy: .public): x420 OK; selecting."
                )
                accepted = cand
                break
            } else {
                excludedCount += 1
                Self.log.debug(
                    "[capture] Probing \(dims.width, privacy: .public)×\(dims.height, privacy: .public) \(cand.label, privacy: .public) → available=\(Self.formatList(available), privacy: .public): no x420; excluding."
                )
            }
        }

        guard let chosen = accepted else {
            device.unlockForConfiguration()
            Self.log.error("[capture] No x420 + (HLG|P3) candidate had x420 in availableVideoCVPixelFormatTypes after probe. \(excludedCount, privacy: .public) candidates output-excluded (likely btp2-trapped).")
            throw CaptureError.noHLGOrP3FormatAvailable(
                scannedFormats: allFormats.count,
                x420Count: x420Candidates.count,
                hlgCount: hlgCount,
                p3Count: p3Count,
                outputExcludedCount: excludedCount
            )
        }

        // 4. Read-back activeColorSpace while still inside the lock.
        //    AVFoundation can briefly return a stale value if read
        //    after unlock, but in-lock reads are stable.
        let actualColorSpace = device.activeColorSpace
        let actualLabel: String
        switch actualColorSpace {
        case .HLG_BT2020:
            self.activeColorSpaceTag = .hlgBT2020
            actualLabel = "HLG_BT2020"
        case .P3_D65:
            self.activeColorSpaceTag = .p3
            actualLabel = "P3_D65"
        default:
            let unknown = "rawValue=\(actualColorSpace.rawValue)"
            Self.log.error("[capture] activeColorSpace readback mismatch: requested=\(chosen.label, privacy: .public) actual=\(unknown, privacy: .public)")
            device.unlockForConfiguration()
            throw CaptureError.activeColorSpaceMismatch(
                requested: chosen.label,
                actualRawValue: actualColorSpace.rawValue
            )
        }
        device.unlockForConfiguration()
        Self.log.debug(
            "[capture] Active color space: \(actualLabel, privacy: .public) (requested \(chosen.label, privacy: .public))"
        )
        Self.log.debug("[capture] colorSpaceTag=\(self.activeColorSpaceTag.label, privacy: .public)")
    }

    /// Tag passed to the Metal kernel so the YCbCr10 → linear-sRGB
    /// kernel knows which transfer function + primary matrix to apply.
    /// Read by `MetalPipeline.colorSpaceTag` after `CaptureSession` init.
    /// Raw values are the buffer(2) uniform `cropDownsampleLinearizeKernel`
    /// reads; they must stay in sync with the switch in `Shaders.metal`.
    enum ActiveColorSpaceTag: UInt8, Sendable, Codable {
        case rec709    = 0
        case hlgBT2020 = 1
        case appleLog  = 2
        case p3        = 3
        var label: String {
            switch self {
            case .rec709:    return "Rec.709"
            case .hlgBT2020: return "HLG BT.2020"
            case .appleLog:  return "Apple Log"
            case .p3:        return "Display P3"
            }
        }
    }

    /// The color-space tag the most recent `configure()` settled on.
    /// Defaults to `.rec709` until configure runs; the Metal pipeline
    /// reads it during bootstrap.
    private(set) var activeColorSpaceTag: ActiveColorSpaceTag = .rec709

    private func clampFrameRate(device: AVCaptureDevice, fps: Int) throws {
        let duration = CMTime(value: 1, timescale: CMTimeScale(fps))
        let ranges = device.activeFormat.videoSupportedFrameRateRanges
        let supports = ranges.contains { Double(fps) >= $0.minFrameRate && Double(fps) <= $0.maxFrameRate }
        guard supports else { throw CaptureError.fpsNotSupported(fps) }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        // Frame-duration setters can also raise NSException for an unsupported value; shim them.
        // The defer above releases the lock on the thrown path.
        try SFObjC.catching {
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
        }
    }

    // MARK: - Run / stop

    func startPreview() {
        // LIVE-LADDER (Feature.liveLadder): construct the persistent preview head BEFORE
        // frames flow. Display-only, so a smaller crop (256) halves the per-frame
        // colorimetry + the persistent rgb10Scratch vs the burst head's crop. OFF ⇒ nil
        // ⇒ the ladder ingest in `tryEnqueuePreviewFrame` is statically inert.
        if Feature.liveLadder, previewColorHead == nil {
            previewColorHead = ColorHead(cropSide: 256)
        }
        // OPTICAL-EV (Feature.opticalEV): build the real exposure-bracket driver + its
        // display-only head BEFORE frames flow. OFF ⇒ both nil ⇒ the optical branch in
        // captureOutput is statically inert and the normal preview path runs unchanged.
        if Feature.opticalEV, exposureDriver == nil, let device {
            exposureDriver = ExposureBracketDriver(device: device)
            opticalColorHead = ColorHead(cropSide: 256)
        }
        // One-time device capability report for optical-EV bracketing (Console: "SF-probe").
        // Pure query, real-device only; tells us this iPhone's actual shutter/ISO envelope so
        // the duration-bracket driver calibrates to real limits, not guessed ones.
        NSLog("%@", probeCameraCapabilities())
        Task.detached { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stopPreview() {
        // Drop the preview head on `delegateQueue` (its only mutation site) so a nil
        // never races an in-flight ingest.
        delegateQueue.async { [weak self] in
            self?.previewColorHead = nil
            self?.exposureDriver?.end()   // restore continuous AE
            self?.exposureDriver = nil
            self?.opticalColorHead = nil
        }
        Task.detached { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    // MARK: - AE / AWB / Focus lock

    enum LockResult: Sendable { case settled(ms: Int), timedOut(ms: Int) }

    /// Set exposure, white balance, and focus to .locked and poll until the device
    /// reports it's no longer adjusting any of them. Hard cap = `timeoutMs` (default 400 ms).
    func lockExposureAndWhiteBalance(timeoutMs: Int = 400) async -> LockResult {
        guard let device else { return .timedOut(ms: 0) }
        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
            if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
            if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
            device.unlockForConfiguration()
        } catch {
            Self.log.error("lockForConfiguration failed: \(String(describing: error))")
            return .timedOut(ms: 0)
        }

        let start = ContinuousClock().now
        let deadline = start.advanced(by: .milliseconds(timeoutMs))
        while ContinuousClock().now < deadline {
            if !device.isAdjustingExposure
                && !device.isAdjustingWhiteBalance
                && !device.isAdjustingFocus {
                let elapsed = Self.elapsedMilliseconds(from: start)
                Self.log.debug("Lock settled in \(elapsed) ms")
                return .settled(ms: elapsed)
            }
            try? await Task.sleep(for: .milliseconds(15))
        }
        Self.log.warning("Lock did not settle in \(timeoutMs) ms — proceeding anyway")
        return .timedOut(ms: timeoutMs)
    }

    /// Robust elapsed-milliseconds conversion from a `ContinuousClock` instant.
    /// Avoids the open-coded `seconds * 1000 + attoseconds / 1e15` pattern that
    /// loses precision and silently overflows for large windows.
    private static func elapsedMilliseconds(from start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock().now - start
        let (seconds, attoseconds) = elapsed.components
        let secMs = seconds &* 1_000
        let attoMs = Int(attoseconds / 1_000_000_000_000_000)  // 1 ms = 1e15 as
        return Int(secMs) + attoMs
    }

    /// Restore continuous AE / AWB / Focus after a burst. Best-effort, never throws.
    func unlockExposureAndWhiteBalance() {
        guard let device else { return }
        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            device.unlockForConfiguration()
        } catch {
            Self.log.error("unlock failed: \(String(describing: error))")
        }
    }

    /// PRE-LOCK exposure expression (QoL 2026-07-03): bias the continuous AE target by
    /// `ev` stops, clamped to the device's own range. The burst-lock invariant is
    /// untouched — the burst still locks AE at capture start; this lets the user choose
    /// WHAT gets locked (place highlights/shadows deliberately, then shoot). Best-effort.
    func setExposureBias(_ ev: Float) {
        guard let device else { return }
        let clamped = min(max(ev, device.minExposureTargetBias), device.maxExposureTargetBias)
        do {
            try device.lockForConfiguration()
            device.setExposureTargetBias(clamped)
            device.unlockForConfiguration()
        } catch {
            Self.log.error("setExposureBias failed: \(String(describing: error))")
        }
    }

    /// Set focus + exposure point of interest in normalized device coords (0..1).
    /// Triggers a one-shot auto-focus/exposure at that point.
    func focusAndExpose(at point: CGPoint) {
        guard let device else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                }
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                if device.isExposureModeSupported(.autoExpose) {
                    device.exposureMode = .autoExpose
                }
            }
            device.unlockForConfiguration()
        } catch {
            Self.log.error("focusAndExpose failed: \(String(describing: error))")
        }
    }

    /// Capture exactly `targetFrameCount` frames, processing each through `pipeline`.
    func captureBurst(into pipeline: MetalPipeline) async throws -> BurstResult {
        try await withCheckedThrowingContinuation { cont in
            delegateQueue.async { [weak self] in
                guard let self else { cont.resume(throwing: CaptureError.cancelled); return }
                if self.collecting {
                    cont.resume(throwing: CaptureError.alreadyCapturing)
                    return
                }
                self.collected.removeAll(keepingCapacity: true)
                self.collected.reserveCapacity(self.targetFrameCount)
                self.ptsSeconds.removeAll(keepingCapacity: true)
                self.ptsSeconds.reserveCapacity(self.targetFrameCount)
                self.submittedCount = 0
                self.droppedFrameCount = 0
                self.pipelineRef = pipeline
                // INDEPENDENT LADDER (gated): build the burst weave driver ON-QUEUE
                // (its confinement rule) from the metered base exposure — the
                // viewmodel's AE lock just settled, so device.exposureDuration/iso
                // are a stable reference — and the ACTIVE format's real envelope.
                // The driver's first stop is programmed here so the ISP starts
                // settling before frame 0; setExposureModeCustom simply replaces
                // the .locked mode (the burst's continuous-AE restore in the
                // viewmodel defer still tears everything down on every path).
                self.weaveDriver = Feature.multiScaleLadder ? self.makeWeaveDriver() : nil
                if let driver = self.weaveDriver, let stop = driver.firstStop,
                   let device = self.device {
                    _ = MultiScaleLadder.applyExposure(to: device, stop: stop)
                }
                // V2.1 (gated): allocate the per-burst camera-box histogram buffer. If the allocation
                // fails (memory pressure), v21HistBuffer stays nil and the export falls back to the
                // index-cube proxy field, so capture is never blocked by it.
                // GATED OFF while the weave driver runs: the histogram accumulates
                // linearized values assuming ONE exposure across the burst; EV-cycled
                // frames would silently skew the probability field (additive gate —
                // the v21 path is untouched whenever the ladder is off).
                self.v21HistBuffer = (Feature.v21Capture && self.weaveDriver == nil)
                    ? pipeline.makeV21HistBuffer(frames: self.targetFrameCount, nLevels: self.v21Levels)
                    : nil
                self.v21BufferState = self.v21HistBuffer != nil ? .allocated : .none
                // Stamp the generation this burst's finishBurst will mint (the
                // same `burstGeneration + 1` convention the telemetry pulses
                // use), so a stale flow-job completion can't downgrade it.
                self.v21BufferGeneration = self.burstGeneration + 1
                if self.v21HistBuffer != nil { self.publishSystemTelemetry() }
                // YIN-YANG (gated): a fresh ladder per burst. cropSide 512 keeps the
                // per-tick Swift colorimetry ≈256k px (~ms in release), well inside
                // the 50 ms tick budget on delegateQueue.
                // GATED OFF while the weave driver runs: the derived head's exact
                // u64 sums / t-band pairs / GCT assume uniform exposure — EV-cycled
                // frames would corrupt them. The head is gated, never deleted; with
                // the ladder off this line is byte-for-byte today's behaviour.
                self.colorHead = (Feature.yinYangBands && self.weaveDriver == nil)
                    ? ColorHead(cropSide: 512) : nil
                self.continuation = cont
                self.firstFrameVerified = false
                self.collecting = true
                Self.log.debug("Burst started: target \(self.targetFrameCount) frames @ \(self.targetFps) fps")
            }
        }
    }

    enum CaptureError: Error, CustomStringConvertible {
        case noCamera
        case cantAddInput
        case cantAddOutput
        case fpsNotSupported(Int)
        case alreadyCapturing
        case cancelled
        /// No x420 (10-bit YCbCr 4:2:0 video-range) format on this
        /// device supports either HLG_BT2020 or P3_D65 at the target
        /// fps *and* delivers x420 through the data output. Genuinely
        /// impossible on iPhone 17 Pro / iOS 26 in normal operation.
        /// `outputExcludedCount` counts candidates that passed the
        /// device-side x420 filter but were rejected during the
        /// probe-and-set loop because `availableVideoPixelFormatTypes`
        /// for that activeFormat didn't include x420 (likely
        /// btp2-only, the iOS 26 packed-Bayer trap on high-res
        /// formats).
        case noHLGOrP3FormatAvailable(
            scannedFormats: Int,
            x420Count: Int,
            hlgCount: Int,
            p3Count: Int,
            outputExcludedCount: Int
        )
        /// `lockForConfiguration` succeeded and we assigned
        /// activeFormat + activeColorSpace, but the read-back returned
        /// a color space outside our priority list. iOS sometimes
        /// silently refuses an assignment when the system is in a
        /// protected state (Continuity Camera handoff, etc.).
        case activeColorSpaceMismatch(requested: String, actualRawValue: Int)
        /// First sample buffer's mediaSubType is not x420. AVFoundation
        /// negotiated a different format despite our
        /// `videoSettings = [pixelFormat: x420]` request. The Metal
        /// pipeline can't decode anything else; surfacing this as a
        /// loud failure beats silently producing garbage frames.
        case firstFramePixelFormatMismatch(expected: OSType, actual: OSType)

        var description: String {
            switch self {
            case .noCamera: return "No back camera available."
            case .cantAddInput: return "Cannot add camera input to session."
            case .cantAddOutput: return "Cannot add video data output to session."
            case .fpsNotSupported(let fps): return "Frame rate \(fps) fps not supported by the active format."
            case .alreadyCapturing: return "A burst is already in progress."
            case .cancelled: return "Capture cancelled."
            case .noHLGOrP3FormatAvailable(let scanned, let x420, let hlg, let p3, let excluded):
                return "Camera HDR formats can't deliver 10-bit YCbCr on this build of iOS. "
                     + "Scanned \(scanned) formats: \(x420) are x420 (10-bit YCbCr) at the target fps; "
                     + "\(hlg) support HLG_BT2020, \(p3) support P3_D65; "
                     + "\(excluded) candidates were rejected during the output-side probe "
                     + "(likely btp2-trapped — high-res formats that only deliver Bayer-packed data). "
                     + "Restart the device and try again."
            case .activeColorSpaceMismatch(let requested, let actual):
                return "Camera silently refused the requested color space \(requested) "
                     + "(returned rawValue=\(actual)). Restart the app and try again."
            case .firstFramePixelFormatMismatch(let expected, let actual):
                return "Camera returned \(CaptureSession.fourCC(actual)) instead of "
                     + "\(CaptureSession.fourCC(expected)) (x420). Another app may be "
                     + "holding the camera in a conflicting mode — close other camera "
                     + "apps and retry."
            }
        }
    }

    /// Render a list of `OSType` four-character codes as a human-readable
    /// string for log output (e.g. `[420v, BGRA]`).
    static func formatList(_ types: [OSType]) -> String {
        let names = types.map { Self.fourCC($0) }
        return "[" + names.joined(separator: ", ") + "]"
    }

    private static func fourCC(_ v: OSType) -> String {
        let bytes: [UInt8] = [
            UInt8((v >> 24) & 0xff),
            UInt8((v >> 16) & 0xff),
            UInt8((v >> 8) & 0xff),
            UInt8(v & 0xff),
        ]
        let chars = bytes.map { (b: UInt8) -> Character in
            (b >= 0x20 && b < 0x7f) ? Character(UnicodeScalar(b)) : "?"
        }
        return String(chars)
    }

    // MARK: - The independent ladder + telemetry (delegate queue)

    /// Build the burst weave driver from the metered base exposure (the AE lock
    /// just settled, so `exposureDuration`/`iso` are the scene's reference) and
    /// the ACTIVE format's real sensor envelope. The exposure-TIME axis is
    /// capped at the pinned frame duration (1/20 s — the hardware cadence is
    /// never touched; `lawCadenceSpreadNeedsGainToTile` says the remaining
    /// stops come from GAIN, which `MultiScaleLadder.schedule` already encodes).
    /// Called only on `delegateQueue` (the driver's confinement rule).
    private func makeWeaveDriver() -> BurstWeaveDriver? {
        guard let device else { return nil }
        let fmt = device.activeFormat
        let frameDur = 1.0 / Double(targetFps)
        let sensor = MultiScaleLadder.SensorLimits(
            minISO: Double(fmt.minISO),
            maxISO: Double(fmt.maxISO),
            minDurationSeconds: CMTimeGetSeconds(fmt.minExposureDuration),
            maxDurationSeconds: min(CMTimeGetSeconds(fmt.maxExposureDuration), frameDur))
        let meteredDur = CMTimeGetSeconds(device.exposureDuration)
        let meteredISO = Double(device.iso)
        let stops = MultiScaleLadder.schedule(
            evSpreadStops: 4,   // ≤2 stops of TIME headroom at 20 fps; the rest is gain
            sensor: sensor,
            referenceDuration: meteredDur > 0 ? meteredDur : frameDur / 4,
            referenceISO: meteredISO > 0 ? meteredISO : Double(fmt.minISO))
        return BurstWeaveDriver(plan: MultiScaleLadder.weavePlan(frameCount: targetFrameCount),
                                stops: stops, cropSide: 512)
    }

    /// One SystemTelemetry snapshot from the current delegate-queue state,
    /// delivered when `Feature.rungTelemetry` is on. Callers are the CHANGE
    /// sites only: v21 buffer lifecycle transitions, pressure-level changes,
    /// and the once-per-burst seam — never the per-tick path.
    private func publishSystemTelemetry() {
        guard Feature.rungTelemetry, let cb = systemTelemetryCallback else { return }
        let mean = tickCpuCount > 0 ? Int(tickCpuTotalUs) / tickCpuCount : 0
        cb(SystemTelemetry(tickCpuMeanUs: mean,
                           tickCpuMaxUs: Int(tickCpuMaxUs),
                           tickCount: tickCpuCount,
                           tickBudgetUs: 50_000,
                           v21Buffer: v21BufferState,
                           pressureLevel: pressureRaw))
    }

    /// Map `AVCaptureDevice.SystemPressureState.Level` to the telemetry's
    /// 0…4 scale (nominal → shutdown); -1 for anything unknown.
    private static func pressureLevelRaw(_ level: AVCaptureDevice.SystemPressureState.Level) -> Int {
        switch level {
        case .nominal: return 0
        case .fair: return 1
        case .serious: return 2
        case .critical: return 3
        case .shutdown: return 4
        default: return -1
        }
    }

    // MARK: - Burst completion (on delegate queue)

    private func finishBurst() {
        precondition(collected.count == targetFrameCount)
        burstGeneration += 1
        let generation = burstGeneration
        let timing = Self.computeTiming(
            ptsSeconds: ptsSeconds,
            targetFps: targetFps,
            droppedFrameCount: droppedFrameCount
        )
        Self.log.debug("Burst complete: \(timing.summary)")
        // [perf] the delegate-queue CPU spent inside the ladder tick, against the
        // 50 ms tick budget — the first number to read when frames start dropping.
        if tickCpuCount > 0 {
            let meanMs = Double(tickCpuTotalUs) / Double(tickCpuCount) / 1000.0
            let maxMs = Double(tickCpuMaxUs) / 1000.0
            Self.log.log("[perf] yin-yang tick CPU: \(self.tickCpuCount) ticks, mean \(meanMs, format: .fixed(precision: 2)) ms, max \(maxMs, format: .fixed(precision: 2)) ms (50 ms tick budget)")
        }
        // SYSTEM TELEMETRY: publish the burst's tick-CPU aggregate BEFORE the
        // counters reset (burst-boundary publish, never per tick).
        publishSystemTelemetry()
        tickCpuTotalUs = 0
        tickCpuMaxUs = 0
        tickCpuCount = 0
        // INDEPENDENT LADDER + RUNG TELEMETRY snapshots — the `recordSums16`
        // pattern: take everything the record phase needs HERE, before the
        // driver/head are released. The derived branch reads the colorHead
        // before the yin-yang block below consumes it.
        var recordRungCubes: RungCubes?
        var recordRungTelemetry: RungTelemetry?
        var recordWeaveWord: [UInt64] = []
        if let driver = weaveDriver {
            recordRungCubes = driver.cubesSnapshot()
            recordWeaveWord = MultiScaleLadder.weaveWord(driver.plan)
            if Feature.rungTelemetry {
                recordRungTelemetry = driver.telemetrySnapshot(generation: generation)
            }
            // [perf] once-per-burst per-rung arrival/N summary (never per tick).
            if let t = recordRungTelemetry {
                for r in t.rungs {
                    Self.log.log("[perf] rung \(r.side)²: \(r.arrivals)/\(r.expectedArrivals) owned, \(r.skipped) skipped, N=\(r.sampleVolume), EV \(r.evCentistops)c, comove \(r.comovementPermilleVsCoarser)‰")
                }
            }
            weaveDriver = nil
        } else if Feature.rungTelemetry, let ch = colorHead {
            recordRungTelemetry = RungTelemetry.derived(
                ticks: ch.tick, fineBinArea: ch.pixelsPerFineBin, generation: generation)
            // DERIVED-MODE cube for the record's v2 `c16`: the ColorHead's
            // retained 16-rung stream. cube64/cube32 stay empty — the
            // c16-only shape is the derived-provenance signature
            // (`Spec.CaptureRecord`: "derived mode writes c16 only").
            if ch.cube16Frames > 0 {
                recordRungCubes = RungCubes(cube64: [], frames64: 0,
                                            cube32: [], frames32: 0,
                                            cube16: ch.cube16, frames16: ch.cube16Frames)
            }
        }
        if let t = recordRungTelemetry { rungTelemetryCallback?(t) }
        // V2.1 (gated): pool the camera-box histogram over t into [y,x,3,256]. Safe to read here: the
        // last frame's command buffer (which carried the 64th hist pass) has completed, and a single
        // queue runs command buffers in order, so all 64 slices are written.
        // Recover the time axis OFF the seam: device-measured 2026-07-01, the flow
        // encode took ~19 s and blocked burst → review the whole time. The detached
        // task owns the per-frame buffer (freed with it); the flow arrives via
        // `flowCallback` → the engine publishes it → σ folds it (export is the only
        // consumer and builds its bundle late). `BurstResult.flow` is now always nil.
        // PERF 2026-07-08: the field pool (~201M Int32 adds) moved into the SAME
        // detached task — it was the largest remaining synchronous cost at the
        // shutter seam. Counts arrive via `v21CountsCallback`; `BurstResult.v21Counts`
        // is nil by design. The skip branch now drops the field along with the flow
        // (same memory-over-completeness call: the review bench falls back to the
        // proxy when counts are nil).
        if let buf = v21HistBuffer, let pipe = pipelineRef {
            if flowJobActive {
                // A previous burst's encode still holds its buffer: skip this one
                // (memory over completeness; the export falls back to the proxy).
                Self.log.log("V2.1 flow: SKIPPED (previous encode still running) — field + flow dropped")
            } else {
                flowJobActive = true
                let job = V21FlowJob(buffer: buf)
                let frames = targetFrameCount, tile = pipe.tileSide, levels = v21Levels
                let callback = flowCallback
                let countsCallback = v21CountsCallback
                let queue = delegateQueue
                Self.log.log("V2.1 flow: pooling + encoding async gen=\(generation)")
                Task.detached(priority: .userInitiated) { [weak self] in
                    let counts = MetalPipeline.poolV21Counts(buffer: job.buffer, frames: frames,
                                                             tileSide: tile, nLevels: levels)
                    Self.log.log("V2.1 field (async gen=\(generation)): pooled \(counts.count) counts")
                    countsCallback?(counts, generation)
                    let flow = MetalPipeline.encodeV21Flow(buffer: job.buffer, frames: frames,
                                                           tileSide: tile, nLevels: levels)
                    Self.log.log("V2.1 flow (async gen=\(generation)): \(flow == nil ? "nil (encode failed)" : "encoded \(flow!.maps.count) frames")")
                    callback?(flow, generation)
                    queue.async { [weak self] in
                        guard let self else { return }
                        self.flowJobActive = false
                        // SYSTEM TELEMETRY: the detached job released the last
                        // reference to the ~384 MiB hist buffer — lifecycle event.
                        // GENERATION-GUARDED: this can land mid-NEXT-burst; if a
                        // newer burst already stamped its own state (allocated or
                        // none), downgrading it to .freed here would misreport a
                        // live buffer as released. Only this job's own generation
                        // may be freed by this closure.
                        guard self.v21BufferGeneration == generation else { return }
                        self.v21BufferState = .freed
                        self.publishSystemTelemetry()
                    }
                }
                // SYSTEM TELEMETRY: the buffer is now HELD by the detached job.
                v21BufferState = .held
                publishSystemTelemetry()
            }
        }
        if v21BufferState == .allocated {
            // Not handed to a flow job (flag off, skip branch, or no pipeline):
            // dropping our reference below frees it — lifecycle event.
            v21BufferState = .freed
            publishSystemTelemetry()
        }
        v21HistBuffer = nil
        // V3.0 (gated): train this capture's somatic θ_up — burst tiles → Q16 volume →
        // [octant gather → SIMT descent → Q16 commit] in ONE GPU dispatch. OFF the seam
        // (QoL 2026-07-03, the encodeV21Flow precedent above): the synchronous train held
        // the capture screen for the whole dispatch — the felt post-capture delay. The
        // burst now resumes immediately; the gene arrives via `thetaUpCallback`
        // (generation-guarded; nil = the floor, never an error). The decide surface
        // starts on the floor arm and attaches the gene when it lands.
        if Feature.v3SomaticTrain {
            let tilesForTrain = collected
            let callback = thetaUpCallback
            let w0 = Feature.metaInitW0 ? MetaInit.deployedW0 : nil   // gated; nil = zero floor
            Task.detached(priority: .userInitiated) {
                let g = CaptureGene.train(tiles: tilesForTrain, w0: w0)
                // GATED-S ship decision (research report §4): deliver the gene ONLY when
                // its learning yielded work — it cleared the Q16 LSB AND explained enough
                // of the residual. A flat capture (nothing committed) or a noise capture
                // (residual unpredictable from coarse) ships the byte-exact floor instead,
                // so a marginal/floored gene never reaches the render.
                let shipped = (g?.yieldsWork() ?? false) ? g : nil
                if let g {
                    let verdict = g.yieldsWork() ? "SHIP" : "floor (no work: −\(Int((g.lossReduction * 100).rounded()))%, committed \(g.committed.contains { $0 != 0 } ? "≠0" : "=0"))"
                    Self.log.log("V3 somatic θ_up (async gen=\(generation)): \(verdict) — loss \(g.loss) vs floor \(g.floorLoss) (−\(Int((g.lossReduction * 100).rounded()))%) in \(Int(g.trainMillis)) ms")
                } else {
                    Self.log.log("V3 somatic θ_up (async gen=\(generation)): nil (unavailable) — the floor ships")
                }
                callback?(shipped, generation)
            }
        }
        // YIN-YANG (gated): train the S_t yang band head on THIS burst's own
        // manufactured t-band pairs — the yin ladder made the labels during the
        // burst; the drain (the single exact→float boundary) happens HERE on
        // delegateQueue (ColorHead is queue-confined), the plain-Metal descent
        // runs OFF the seam like θ_up above. Verdict semantics are the
        // YinYangCircuitTests conventions: floor = target variance; learned
        // ≈ finalMSE ≪ floor, floored ≈ finalMSE near floor (honest control).
        // Capture-record snapshot (Spec.CaptureRecord): the exact 16² sums and
        // the realized GCT must be taken here, before the head is released.
        var recordSums16: [UInt64]?
        var recordGCT: [UInt8]?
        if let ch = colorHead {
            recordSums16 = ch.latest16
            recordGCT = ch.latestGCT
            let pxPerBin = Int64(ch.cropSide / 64) * Int64(ch.cropSide / 64)
            // linear16 L-sums per fine bin: ~pxPerBin·65535 per channel at clip —
            // 1/(pxPerBin·65535) puts features at O(1) (the drain contract).
            let (f, y, w) = ch.drainTBandPairs(scale: 1.0 / (Float(pxPerBin) * 65535.0))
            // A1 (KinematicHaltPrior keystone): keep the FULL per-slot certified-order
            // vector, not a scalar count. It is the halting-depth budget AND survives to
            // the render/influence path via `bandHeadCallback`.
            let haltOrders = ch.haltFloor()
            let budget = ColorHead.haltingDepthBudget(haltOrders)
            let needsLearning = ColorHead.residualNeedsLearning(haltOrders)
            let certifiable = haltOrders.filter { $0 >= 0 }.count
            colorHead = nil
            let callback = bandHeadCallback
            if y.isEmpty {
                Self.log.log("YinYang S_t (gen=\(generation)): no pairs (ladder starved) — the floor ships")
                callback?(nil, haltOrders, generation)
            } else if !needsLearning {
                // The certified floor already ships the motion exactly (order ≤ 1
                // everywhere): predict with the derivatives we have, pay no S-packets.
                Self.log.log("YinYang S_t (gen=\(generation)): SKIP — halt budget \(budget) (\(certifiable)/256 certifiable) ≤ 1, kinematic floor is exact, no residual to learn")
                callback?(nil, haltOrders, generation)
            } else {
                Task.detached(priority: .userInitiated) {
                    // Subsample stride 16 for the single-thread kernel's budget
                    // (the YinYangCircuitTests convention).
                    var sf = [Float](), sy = [Float]()
                    sy.reserveCapacity(y.count / 16 + 1)
                    sf.reserveCapacity((y.count / 16 + 1) * w)
                    for i in Swift.stride(from: 0, to: y.count, by: 16) {
                        sf.append(contentsOf: f[(i * w)..<(i * w + w)])
                        sy.append(y[i])
                    }
                    let mean = sy.reduce(0, +) / Float(sy.count)
                    let floorVar = sy.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(sy.count)
                    let r = BandHeadTrainer.shared?.train(features: sf, targets: sy, featureWidth: w,
                                                          steps: 2500, eta: 0.4)
                    if let r {
                        let cut = floorVar > 0 ? Int(((1 - r.finalMSE / floorVar) * 100).rounded()) : 0
                        Self.log.log("YinYang S_t (async gen=\(generation)): \(sy.count) pairs, MSE \(r.initialMSE) → \(r.finalMSE) vs var-floor \(floorVar) (−\(cut)%), halt budget \(budget) (\(certifiable)/256 certifiable)")
                    } else {
                        Self.log.log("YinYang S_t (async gen=\(generation)): nil (Metal unavailable) — the floor ships")
                    }
                    callback?(r, haltOrders, generation)
                }
            }
        }
        // Per-frame intervals for the capture record, µs-exact, taken before
        // the timestamps are cleared. Negative gaps (PTS jitter) clamp to 0.
        let intervalsUs: [UInt64] = zip(ptsSeconds.dropFirst(), ptsSeconds).map {
            UInt64((Swift.max(0, $0 - $1) * 1_000_000).rounded())
        }
        let snapshot = collected
        let cont = continuation
        collected.removeAll(keepingCapacity: true)
        ptsSeconds.removeAll(keepingCapacity: true)
        submittedCount = 0
        droppedFrameCount = 0
        pipelineRef = nil
        continuation = nil
        collecting = false
        cont?.resume(returning: BurstResult(tiles: snapshot, timing: timing, v21Counts: nil,
                                            flow: nil, thetaUp: nil, intervalsUs: intervalsUs,
                                            sums16: recordSums16, gct: recordGCT,
                                            rungCubes: recordRungCubes,
                                            rungTelemetry: recordRungTelemetry,
                                            weaveWord: recordWeaveWord))
    }

    /// Pure aggregation of inter-frame timing — `static` and side-effect-free so
    /// it can be unit-tested with synthetic PTS arrays (see `BurstTimingTests`).
    /// Intervals come from the camera's own presentation clock (the real-time
    /// ground truth), so they reflect what actually happened, not the nominal fps.
    static func computeTiming(
        ptsSeconds: [Double],
        targetFps: Int,
        droppedFrameCount: Int
    ) -> BurstTiming {
        let target = 1000.0 / Double(targetFps)
        guard let first = ptsSeconds.first,
              let last = ptsSeconds.last,
              ptsSeconds.count >= 2 else {
            return BurstTiming(
                frameCount: ptsSeconds.count, durationMs: 0,
                meanIntervalMs: 0, stdIntervalMs: 0,
                minIntervalMs: 0, maxIntervalMs: 0,
                targetIntervalMs: target,
                worstAbsDeviationMs: 0,
                droppedFrameCount: droppedFrameCount
            )
        }
        let intervals: [Double] = zip(ptsSeconds.dropFirst(), ptsSeconds).map { ($0 - $1) * 1000.0 }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        let variance = intervals.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(intervals.count)
        let std = variance.squareRoot()
        let durationMs = (last - first) * 1000.0
        let worstAbsDeviation = intervals.map { abs($0 - target) }.max() ?? 0
        return BurstTiming(
            frameCount: ptsSeconds.count,
            durationMs: durationMs,
            meanIntervalMs: mean,
            stdIntervalMs: std,
            minIntervalMs: intervals.min() ?? 0,
            maxIntervalMs: intervals.max() ?? 0,
            targetIntervalMs: target,
            worstAbsDeviationMs: worstAbsDeviation,
            droppedFrameCount: droppedFrameCount
        )
    }
}

extension CaptureSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Always on delegateQueue.
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // If no burst is in progress, route to the live preview path
        // (throttled to ~10 fps). Burst capture has priority — when
        // `collecting == true` we skip preview entirely to keep the
        // GPU free for the burst pipeline.
        if !collecting {
            // OPTICAL-EV: when on, the exposure-bracket driver OWNS the preview — it cycles
            // real exposures and routes each settled frame to its tile. The normal index
            // preview is skipped (its per-frame exposure would flicker through the bracket).
            // onFrame() must be called every frame to advance the settle counter; it returns
            // a rung only on the settled frame of each exposure.
            if Feature.opticalEV, let driver = exposureDriver, let ch = opticalColorHead {
                if let rung = driver.onFrame(),
                   let sums = ch.poolSums64(fromX420: pixelBuffer),
                   let tile = ch.realizeSingleFrame(sums64: sums, side: rung.side) {
                    opticalTileCallback?(rung.side, tile)
                }
                return
            }
            tryEnqueuePreviewFrame(pixelBuffer: pixelBuffer)
            return
        }

        guard submittedCount < targetFrameCount else { return }
        guard let pipeline = pipelineRef else { return }

        // First-frame format verification — the only reliable signal
        // that AVFoundation honored our videoSettings = [pixelFormat:
        // x420] request. Preflight via availableVideoPixelFormatTypes
        // is unreliable inside beginConfiguration on iOS 26. The Metal
        // YCbCr10 texture cache would fail downstream on a mismatched
        // format anyway, but failing here gives a clearer error.
        if !firstFrameVerified {
            let want10Bit: OSType = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            let fmtDesc = CMSampleBufferGetFormatDescription(sampleBuffer)
            let actual = fmtDesc.map { CMFormatDescriptionGetMediaSubType($0) } ?? 0
            guard actual == want10Bit else {
                Self.log.error("[capture] First frame mediaSubType=\(Self.fourCC(actual), privacy: .public), expected x420. Aborting burst.")
                let cont = continuation
                continuation = nil
                pipelineRef = nil
                v21HistBuffer = nil
                v21BufferState = .none
                colorHead = nil
                weaveDriver = nil   // the viewmodel's defer restores continuous AE
                collecting = false
                cont?.resume(throwing: CaptureError.firstFramePixelFormatMismatch(
                    expected: want10Bit,
                    actual: actual
                ))
                return
            }
            firstFrameVerified = true
            Self.log.debug("[capture] frame 0 mediaSubType=x420 (verified)")
        }

        let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let seconds = CMTimeGetSeconds(ts)
        let nanos = UInt64(seconds * 1_000_000_000)

        // Per-frame timing (TROUBLESHOOT 2026-07-08): the routine cadence is
        // summarized ONCE at finishBurst (computeTiming), so the old
        // line-per-frame debug log paid 64 formatted lines a burst and buried
        // the signal. Only the ANOMALY logs now: a gap ≥ 1.5× the target
        // period is the late-frame event worth a line.
        if let prev = ptsSeconds.last {
            let dtMs = (seconds - prev) * 1000.0
            if dtMs >= 1500.0 / Double(targetFps) {
                Self.log.warning("[tick] LATE frame \(self.submittedCount): +\(dtMs, format: .fixed(precision: 2)) ms (target \(1000.0 / Double(self.targetFps), format: .fixed(precision: 0)) ms)")
            }
        } else {
            Self.log.debug("frame 0: t0 = \(seconds, format: .fixed(precision: 6)) s")
        }
        ptsSeconds.append(seconds)
        submittedCount += 1

        do {
            // V2.1 (gated): this frame's slice of the camera-box accumulation rides the same command
            // buffer. coarseFrame = submittedCount - 1 (0-based; submittedCount was just incremented),
            // always in 0..<targetFrameCount thanks to the guard above.
            let v21: MetalPipeline.V21HistDispatch? = v21HistBuffer.map {
                MetalPipeline.V21HistDispatch(buffer: $0, coarseFrame: submittedCount - 1, nLevels: v21Levels)
            }
            try pipeline.submitAsync(pixelBuffer: pixelBuffer, captureNanos: nanos, v21Hist: v21) { [weak self] tile in
                guard let self else { return }
                self.delegateQueue.async {
                    guard self.collecting else { return }
                    self.collected.append(tile)
                    // Surface each frame as it lands so the preview animates the
                    // capture live (one tick ≈ the 20 fps burst cadence) instead of
                    // freezing on the last live frame.
                    self.burstFrameCallback?(tile, self.collected.count)
                    if self.collected.count == self.targetFrameCount {
                        self.finishBurst()
                    }
                }
            }
        } catch {
            Self.log.error("submitAsync failed: \(String(describing: error))")
            let cont = continuation
            continuation = nil
            pipelineRef = nil
            v21HistBuffer = nil
            v21BufferState = .none
            colorHead = nil
            weaveDriver = nil   // the viewmodel's defer restores continuous AE
            collecting = false
            cont?.resume(throwing: error)
            return
        }

        // INDEPENDENT LADDER (gated) or YIN-YANG (gated): run the ladder tick
        // AFTER the GPU submission so the pipeline is never kept waiting on CPU
        // colorimetry. Synchronous on delegateQueue — frame ORDER is the whole
        // point (the weave word / tick pairing). A nil pool (unexpected
        // geometry) just starves the ladder; the floor ships. The two heads are
        // mutually exclusive by construction (captureBurst gates colorHead off
        // while the weave driver runs). TROUBLESHOOT: the tick's CPU cost
        // aggregates here and logs ONCE per burst in finishBurst — per-tick
        // logging is itself a hot-path cost.
        if let driver = weaveDriver {
            let t0 = DispatchTime.now().uptimeNanoseconds
            let tick = submittedCount - 1
            driver.ingest(tickIndex: tick, pixelBuffer: pixelBuffer)
            // Program the NEXT dwell's exposure at the boundary so its settle
            // ticks absorb the ISP latency (device-only; no-op in the sim).
            if let next = driver.exposureSwitchAfter(tick: tick), let device {
                _ = MultiScaleLadder.applyExposure(to: device, stop: next)
            }
            // COALESCED telemetry pulse at the 16-rung cadence (every 4th tick
            // = 5 Hz): one delivery carries all three rungs — never a per-frame
            // SwiftUI storm. Stamped with the generation finishBurst will mint.
            if Feature.rungTelemetry, (tick + 1) % 4 == 0, let cb = rungTelemetryCallback {
                cb(driver.telemetrySnapshot(generation: burstGeneration + 1))
            }
            let us = (DispatchTime.now().uptimeNanoseconds - t0) / 1000
            tickCpuTotalUs += us
            if us > tickCpuMaxUs { tickCpuMaxUs = us }
            tickCpuCount += 1
        } else if let ch = colorHead {
            let t0 = DispatchTime.now().uptimeNanoseconds
            if let sums = ch.poolSums64(fromX420: pixelBuffer) {
                ch.ingest(sums)
                // COALESCED derived-mode telemetry at the 16-rung cadence (every
                // 4th ingested tick = 5 Hz) — constants + counters, no computation
                // (the coarse rungs ARE exact pools; comovement is 1000‰ by
                // construction and reported so). Inside the ingest branch so a
                // starved ladder never republishes a stale snapshot per frame.
                if Feature.rungTelemetry, ch.tick % 4 == 0, let cb = rungTelemetryCallback {
                    cb(RungTelemetry.derived(ticks: ch.tick, fineBinArea: ch.pixelsPerFineBin,
                                             generation: burstGeneration + 1))
                }
                // FLUX BAR (E6): the fresh GCT at the same 16-rung realize cadence —
                // ≤ 5 Hz, one 768-byte value, inside the ingest branch (never stale).
                if ch.tick % 4 == 0, let gct = ch.latestGCT, let cb = gctCallback {
                    cb(gct)
                }
            }
            let us = (DispatchTime.now().uptimeNanoseconds - t0) / 1000
            tickCpuTotalUs += us
            if us > tickCpuMaxUs { tickCpuMaxUs = us }
            tickCpuCount += 1
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // The delegate callbacks are serialized on `delegateQueue`, so this read
        // and bump of `droppedFrameCount` is consistent with the burst state.
        // Count only drops that fall inside an active burst — those are the ones
        // that punch a ~2× gap into the captured cadence.
        if collecting {
            droppedFrameCount += 1
            // Charge the drop to the rung whose exposure was live — the
            // telemetry's honest `skipped` accounting.
            weaveDriver?.noteDropped(tickIndex: submittedCount)
        }
        Self.log.warning("Camera DROPPED a frame (kernel-side); dropped this burst = \(self.droppedFrameCount)")
    }

    /// Submit `pixelBuffer` through the same Metal pipeline used for
    /// burst capture, but solely for the live 64×64 preview. Throttled
    /// to ~10 fps (every other camera frame at 20 fps). Result is
    /// delivered to `previewCallback` from the GPU completion handler
    /// — receiver is responsible for dispatching to the main actor.
    ///
    /// Called only on `delegateQueue` when `collecting == false`. Burst
    /// capture has priority and short-circuits this path.
    private func tryEnqueuePreviewFrame(pixelBuffer: CVPixelBuffer) {
        guard let pipeline = previewPipeline, let callback = previewCallback else { return }
        // Throttle by mach time. clock_gettime_nsec_np is monotonic +
        // ~ns precision; ContinuousClock would also work but mach
        // avoids the wrapper allocation per frame.
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        if now - lastPreviewSubmitNanos < Self.previewMinIntervalNanos { return }
        lastPreviewSubmitNanos = now
        do {
            try pipeline.submitAsync(pixelBuffer: pixelBuffer, captureNanos: now) { tile in
                // GPU completion handler — runs on whatever queue Metal
                // picks. Hand off to the receiver immediately; they're
                // responsible for marshaling to the main actor.
                callback(tile)
            }
        } catch {
            // Preview failures are non-fatal — burst capture still
            // works. Log once per error to avoid spam.
            Self.log.debug("[capture] preview submit failed: \(String(describing: error), privacy: .public)")
        }

        // LIVE-LADDER (Feature.liveLadder): ingest the SAME x420 buffer into the persistent
        // preview head at the same throttle, realize the 32²/16² rungs, and publish them.
        // Guarded on `previewColorHead != nil` so with the flag OFF (head nil) nothing runs
        // — `ladderCallback` never fires and the pyramid stays the in-view pooling verbatim.
        // Independent of the per-burst `colorHead`; runs only on this idle preview path.
        if let ch = previewColorHead, let ladder = ladderCallback,
           let sums = ch.poolSums64(fromX420: pixelBuffer) {
            ch.ingest(sums)
            if let (rgb32, rgb16) = ch.realizeLadderSrgb8() {
                ladder(rgb32, rgb16)
            }
            // FLUX BAR (E6): the idle-path GCT pulse at the same 16-rung cadence.
            if ch.tick % 4 == 0, let gct = ch.latestGCT, let cb = gctCallback {
                cb(gct)
            }
        }
    }
}
