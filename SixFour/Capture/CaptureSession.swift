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
    private var pipelineRef: MetalPipeline?
    private var continuation: CheckedContinuation<BurstResult, Error>?
    /// Per-burst latch — the first delivered sample buffer's
    /// `CMFormatDescription` is checked against x420; subsequent frames
    /// skip the read since pixel-format negotiation is fixed at
    /// addOutput time. Reset to `false` at every `captureBurst` start.
    private var firstFrameVerified = false

    /// Result of a completed 64-frame burst.
    struct BurstResult: Sendable {
        let tiles: [OKLabTile]
        let timing: BurstTiming
    }

    /// Aggregate statistics over the 63 inter-frame intervals (in ms).
    struct BurstTiming: Sendable {
        let frameCount: Int
        let durationMs: Double
        let meanIntervalMs: Double
        let stdIntervalMs: Double
        let minIntervalMs: Double
        let maxIntervalMs: Double
        let targetIntervalMs: Double
        var summary: String {
            String(
                format: "%d frames in %.1f ms — interval mean %.2f ms (target %.2f), σ %.2f, min %.2f, max %.2f",
                frameCount, durationMs,
                meanIntervalMs, targetIntervalMs,
                stdIntervalMs, minIntervalMs, maxIntervalMs
            )
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
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            Self.log.error("[capture] No back wide-angle camera available")
            throw CaptureError.noCamera
        }
        self.device = device
        Self.log.info("[capture] Device: \(device.localizedName, privacy: .public) modelID=\(device.modelID, privacy: .public)")

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
        try selectHDRFormat(on: device)

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
        Self.log.info(
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
    /// Per-candidate probe cost is sub-millisecond — set+query inside
    /// the lock; we probe up to ~9 candidates total on iPhone 17 Pro.
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
        Self.log.info("[capture] Scanning \(allFormats.count, privacy: .public) device formats for x420 (10-bit YCbCr 4:2:0) at \(self.targetFps, privacy: .public) fps…")

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
        Self.log.info("[capture] Found \(x420Candidates.count, privacy: .public) x420 formats at \(self.targetFps, privacy: .public) fps; \(hlgCount, privacy: .public) support HLG, \(p3Count, privacy: .public) support P3")

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
        try device.lockForConfiguration()
        var accepted: Candidate? = nil
        var excludedCount = 0
        for cand in candidates {
            device.activeFormat = cand.format
            device.activeColorSpace = cand.colorSpace
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
                Self.log.info(
                    "[capture] Probing \(dims.width, privacy: .public)×\(dims.height, privacy: .public) \(cand.label, privacy: .public) → available=\(Self.formatList(available), privacy: .public): x420 OK; selecting."
                )
                accepted = cand
                break
            } else {
                excludedCount += 1
                Self.log.info(
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
        Self.log.info(
            "[capture] Active color space: \(actualLabel, privacy: .public) (requested \(chosen.label, privacy: .public))"
        )
        Self.log.info("[capture] colorSpaceTag=\(self.activeColorSpaceTag.label, privacy: .public)")
    }

    /// Tag passed to the Metal kernel so the YCbCr10 → linear-sRGB
    /// kernel knows which transfer function + primary matrix to apply.
    /// Read by `MetalPipeline.colorSpaceTag` after `CaptureSession` init.
    /// Raw values are the buffer(2) uniform `cropDownsampleLinearizeKernel`
    /// reads; they must stay in sync with the switch in `Shaders.metal`.
    enum ActiveColorSpaceTag: UInt8, Sendable {
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
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
    }

    // MARK: - Run / stop

    func startPreview() {
        Task.detached { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stopPreview() {
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
                Self.log.info("Lock settled in \(elapsed) ms")
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
                self.pipelineRef = pipeline
                self.continuation = cont
                self.firstFrameVerified = false
                self.collecting = true
                Self.log.info("Burst started: target \(self.targetFrameCount) frames @ \(self.targetFps) fps")
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

    // MARK: - Burst completion (on delegate queue)

    private func finishBurst() {
        precondition(collected.count == targetFrameCount)
        let timing = computeTiming(ptsSeconds: ptsSeconds, targetFps: targetFps)
        Self.log.info("Burst complete: \(timing.summary)")
        let snapshot = collected
        let cont = continuation
        collected.removeAll(keepingCapacity: true)
        ptsSeconds.removeAll(keepingCapacity: true)
        submittedCount = 0
        pipelineRef = nil
        continuation = nil
        collecting = false
        cont?.resume(returning: BurstResult(tiles: snapshot, timing: timing))
    }

    private func computeTiming(ptsSeconds: [Double], targetFps: Int) -> BurstTiming {
        let target = 1000.0 / Double(targetFps)
        guard let first = ptsSeconds.first,
              let last = ptsSeconds.last,
              ptsSeconds.count >= 2 else {
            return BurstTiming(
                frameCount: ptsSeconds.count, durationMs: 0,
                meanIntervalMs: 0, stdIntervalMs: 0,
                minIntervalMs: 0, maxIntervalMs: 0,
                targetIntervalMs: target
            )
        }
        let intervals: [Double] = zip(ptsSeconds.dropFirst(), ptsSeconds).map { ($0 - $1) * 1000.0 }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        let variance = intervals.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(intervals.count)
        let std = variance.squareRoot()
        let durationMs = (last - first) * 1000.0
        return BurstTiming(
            frameCount: ptsSeconds.count,
            durationMs: durationMs,
            meanIntervalMs: mean,
            stdIntervalMs: std,
            minIntervalMs: intervals.min() ?? 0,
            maxIntervalMs: intervals.max() ?? 0,
            targetIntervalMs: target
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
        guard collecting else { return }
        guard submittedCount < targetFrameCount else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
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
                collecting = false
                cont?.resume(throwing: CaptureError.firstFramePixelFormatMismatch(
                    expected: want10Bit,
                    actual: actual
                ))
                return
            }
            firstFrameVerified = true
            Self.log.info("[capture] frame 0 mediaSubType=x420 (verified)")
        }

        let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let seconds = CMTimeGetSeconds(ts)
        let nanos = UInt64(seconds * 1_000_000_000)

        // Per-frame timing log.
        if let prev = ptsSeconds.last {
            let dtMs = (seconds - prev) * 1000.0
            Self.log.debug("frame \(self.submittedCount): +\(dtMs, format: .fixed(precision: 2)) ms")
        } else {
            Self.log.debug("frame 0: t0 = \(seconds, format: .fixed(precision: 6)) s")
        }
        ptsSeconds.append(seconds)
        submittedCount += 1

        do {
            try pipeline.submitAsync(pixelBuffer: pixelBuffer, captureNanos: nanos) { [weak self] tile in
                guard let self else { return }
                self.delegateQueue.async {
                    guard self.collecting else { return }
                    self.collected.append(tile)
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
            collecting = false
            cont?.resume(throwing: error)
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        Self.log.warning("Camera DROPPED a frame (kernel-side)")
    }
}
