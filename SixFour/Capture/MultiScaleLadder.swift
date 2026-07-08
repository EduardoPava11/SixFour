import Foundation
import os
#if canImport(AVFoundation)
import AVFoundation
#endif

/// THE LOOM's capture scheduler — the interleaved-exposure EV ladder that produces
/// three INDEPENDENT volumes (16³/32³/64³), plus the drivers that assemble and fuse
/// them through the golden-gated Zig core (`SixFourNative.multiScaleIntegrate` /
/// `SixFourNative.renderSelect`).
///
/// This is the device-side realization of the proven spec chain
/// (`Spec.CaptureDiversity` → `MultiScaleCapture` → `RenderSelect`): each scale is a
/// SEPARATE exposure on the shared 64@20 / 32@10 / 16@5 cadence, spread across the
/// scene's dynamic range so the streams are independent (not pools of one source).
///
/// Split by testability:
///   * `schedule(...)` and `assembleVolumes(...)` and `fuse(...)` are PURE Swift —
///     compile-checked and unit-testable off-device.
///   * `applyExposure(to:stop:)` calls `AVCaptureDevice` custom exposure and only
///     RUNS on hardware (custom exposure is ignored/unavailable in the Simulator);
///     it is guarded so the module still builds for a generic simulator slice.
///
/// Gated by `Feature.multiScaleLadder` (OFF until validated on an iPhone 17 Pro);
/// with it off this type is unreferenced and the live capture path is untouched.
enum MultiScaleLadder {

    private static let log = Logger(subsystem: "com.sixfour.SixFour", category: "loom.ladder")

    /// The three scales, coarse → fine. `raw` doubles as the depth code that
    /// `RenderSelect`/`s4_render_select` reads (0 = 16³, 1 = 32³, 2 = 64³).
    enum Scale: Int, CaseIterable {
        case coarse16 = 0
        case mid32 = 1
        case fine64 = 2

        /// Frames this scale captures over the 3.2 s burst (its cadence: 5/10/20 fps).
        var frameCount: Int { [16, 32, 64][rawValue] }
        /// Spatial side of this scale's own (binned) read.
        var side: Int { [16, 32, 64][rawValue] }
        /// On-sensor binning that yields this scale's resolution from a 64-native sensor.
        var binning: Int { [4, 2, 1][rawValue] }
        /// GIF89a cadence (fps) — the shared-clock rate for this scale.
        var fps: Int { [5, 10, 20][rawValue] }
    }

    /// One rung of the exposure ladder: the capture config for a single scale.
    /// `durationSeconds` × `iso` set the scale's total EV; the coarse scale sits
    /// LONG + HIGH-GAIN (shadows), the fine scale SHORT + LOW-GAIN (highlights).
    struct Stop: Equatable {
        let scale: Scale
        let durationSeconds: Double
        let iso: Double
        /// The scale's EV offset in stops relative to the fine (reference) exposure —
        /// positive = dimmer luminances captured (more exposure/gain). The three
        /// offsets TILE the dynamic range (`Spec.CaptureDiversity.lawTilingMaximizesCoverage`).
        let evOffsetStops: Double

        /// The offset as SIGNED centistops — the integer the telemetry publishes
        /// and the capture record's zigzag carries (`Spec.CaptureRecord` v2 units).
        var evCentistops: Int { Int((evOffsetStops * 100).rounded()) }

        /// Duration in exact integer microseconds (the record/telemetry unit).
        var durationUs: Int64 { Int64((durationSeconds * 1_000_000).rounded()) }

        /// Gain in ISO milli-units (ISO 100 = 100_000 — the record/telemetry unit).
        var isoMilli: Int64 { Int64((iso * 1000).rounded()) }
    }

    /// The sensor envelope the schedule must stay within (device-reported bounds).
    struct SensorLimits {
        let minISO: Double
        let maxISO: Double
        let minDurationSeconds: Double
        let maxDurationSeconds: Double
    }

    // MARK: - The schedule (pure — the CaptureDiversity recipe)

    /// Build the EV-tiled 3-stop bracket for a target spread of `evSpreadStops`
    /// (≈ the sensor's per-exposure window, from `Spec.CaptureDiversity`). The stops
    /// are spaced `evSpreadStops/2` apart (fine at 0, mid at half, coarse at full);
    /// the cadence affords ~2 stops via exposure TIME, the rest comes from GAIN
    /// (`lawCadenceSpreadNeedsGainToTile`), and everything is clamped to the sensor
    /// envelope. Pure and deterministic — the unit-testable core of the ladder.
    static func schedule(evSpreadStops: Double, sensor: SensorLimits,
                         referenceDuration: Double, referenceISO: Double) -> [Stop] {
        // Fine (reference) exposure = short + low gain (highlights).
        let refDur = clamp(referenceDuration, sensor.minDurationSeconds, sensor.maxDurationSeconds)
        let refISO = clamp(referenceISO, sensor.minISO, sensor.maxISO)

        return Scale.allCases.map { scale in
            // Fine = 0 stops, mid = spread/2, coarse = spread (the tiling).
            let ev = evSpreadStops * (Double(scale.rawValue == 2 ? 0 : (2 - scale.rawValue)) / 2.0)
            // Cadence affords ~1 stop per adjacent scale via exposure time; the rest via gain.
            let cadenceStops = min(ev, Double(scale.rawValue == 2 ? 0 : (2 - scale.rawValue)))
            let gainStops = ev - cadenceStops
            let dur = clamp(refDur * pow(2.0, cadenceStops), sensor.minDurationSeconds, sensor.maxDurationSeconds)
            let iso = clamp(refISO * pow(2.0, gainStops), sensor.minISO, sensor.maxISO)
            return Stop(scale: scale, durationSeconds: dur, iso: iso, evOffsetStops: ev)
        }
    }

    // MARK: - The burst weave (pure — the interleaved schedule over 64 ticks)

    /// One hardware tick of the woven burst plan.
    struct WeaveTick: Equatable {
        /// The scale whose exposure is LIVE on this tick.
        let scale: Scale
        /// True = the ISP has settled and this frame is OWNED by `scale`
        /// (routed into its independent volume). False = a settle tick right
        /// after an exposure switch — skipped honestly, counted per rung.
        let owned: Bool
    }

    /// The deterministic 64-tick weave of the 3.2 s burst: a repeating 16-tick
    /// super-cycle of dwells `fine64 ×8, mid32 ×5, coarse16 ×3`, the first
    /// `settleFrames` ticks of each dwell unsettled (the ISP pipeline clears in
    /// 1–3 frames; `ExposureBracketDriver` uses the same accounting). The dwell
    /// weights approximate the rungs' cadence ratio 4:2:1 within one sensor's
    /// 64 hardware ticks: with the default `settleFrames = 2` the owned counts
    /// are 24 / 12 / 4 per burst. Deterministic and pure — the owner word for
    /// the capture record falls straight out of it (`weaveWord`). The fine
    /// dwell leads so the burst opens at the reference (metered) exposure.
    static func weavePlan(frameCount: Int = 64, settleFrames: Int = 2) -> [WeaveTick] {
        let dwells: [(Scale, Int)] = [(.fine64, 8), (.mid32, 5), (.coarse16, 3)]
        let settle = max(1, settleFrames)
        var plan: [WeaveTick] = []
        plan.reserveCapacity(max(0, frameCount))
        while plan.count < frameCount {
            for (scale, len) in dwells {
                for i in 0..<len where plan.count < frameCount {
                    plan.append(WeaveTick(scale: scale, owned: i >= settle))
                }
            }
        }
        return plan
    }

    /// The weave WORD: per-tick owner depth code (0 = 16³, 1 = 32³, 2 = 64³ —
    /// `Scale.rawValue`, the same code `RenderSelect` reads). Settle ticks carry
    /// the scale whose exposure was live (the sensor WAS exposed at that stop;
    /// the frame just isn't evidence). This is the temporal ORDER
    /// `Spec.WeaveOrder` proves invisible to every conserved marginal — it must
    /// be persisted in the capture record or it is gone.
    static func weaveWord(_ plan: [WeaveTick]) -> [UInt64] {
        plan.map { UInt64($0.scale.rawValue) }
    }

    /// Frames the plan OWNS for `scale` — the independent-mode
    /// `expectedArrivals` of that rung's telemetry.
    static func plannedOwnedCount(_ plan: [WeaveTick], scale: Scale) -> Int {
        plan.lazy.filter { $0.scale == scale && $0.owned }.count
    }

    // MARK: - Assemble the three independent volumes (pure)

    /// Stack this scale's captured frames into its independent volume — a flat
    /// `frameCount × side × side` Int32 array (t-major, then y, then x), for ONE
    /// channel. Each frame must be `side × side` samples at the scale's resolution.
    /// This is the direct one-exposure-per-frame assembly; the sub-exposure
    /// accumulation variant routes through `SixFourNative.multiScaleIntegrate`.
    static func assembleVolume(scale: Scale, frames: [[Int32]]) -> [Int32]? {
        let n = scale.side
        guard frames.count == scale.frameCount, frames.allSatisfy({ $0.count == n * n }) else {
            log.error("assembleVolume: bad shape for \(scale.rawValue, privacy: .public)")
            return nil
        }
        var vol = [Int32](); vol.reserveCapacity(scale.frameCount * n * n)
        for f in frames { vol.append(contentsOf: f) }
        return vol
    }

    // MARK: - Fuse (the select render, per channel)

    /// Fuse the three independent volumes into one `side³` output by the per-region
    /// `depth` field (the paint's 16³ scale-choice), via the byte-exact
    /// `s4_render_select`. One channel; call per R/G/B. The device side is 64 (so the
    /// three volumes are 16³/32³/64³); the golden tests use 8.
    static func fuse(depth: [Int32], v16: [Int32], v32: [Int32], v64: [Int32],
                     side: Int = 64) -> [Int32]? {
        SixFourNative.renderSelect(v16: v16, v32: v32, v64: v64, depth: depth, side: side)
    }

    // MARK: - Device exposure application (hardware-only)

    #if canImport(AVFoundation)
    /// Apply one ladder stop to the capture device's custom exposure. RUNS ONLY on
    /// hardware — the Simulator has no camera and ignores custom exposure, so this is
    /// guarded out there. The caller locks the device for configuration and cycles
    /// the stops across the interleaved cadence; frames are then tagged with their
    /// scale for `assembleVolume`. Throws are surfaced by the caller's capture loop.
    @available(iOS 13.0, *)
    static func applyExposure(to device: AVCaptureDevice, stop: Stop) -> Bool {
        #if targetEnvironment(simulator)
        return false   // no custom exposure in the Simulator; the ladder is device-only
        #else
        guard device.isExposureModeSupported(.custom) else {
            log.error("custom exposure unsupported on this device")
            return false
        }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            let dur = CMTime(seconds: stop.durationSeconds, preferredTimescale: 1_000_000_000)
            // Clamp ISO to the ACTIVE format's real bounds (SensorLimits is advisory).
            let fmt = device.activeFormat
            let iso = Float(min(max(stop.iso, Double(fmt.minISO)), Double(fmt.maxISO)))
            device.setExposureModeCustom(duration: dur, iso: iso, completionHandler: nil)
            return true
        } catch {
            log.error("applyExposure lockForConfiguration failed: \(String(describing: error), privacy: .public)")
            return false
        }
        #endif
    }
    #endif

    // MARK: - util

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), hi)
    }
}
