import AVFoundation
import CoreMedia
import Foundation

/// REAL optical-EV bracketing for the three-view preview — NO digital gain anywhere.
///
/// One sensor holds ONE exposure per frame, so three real exposures are time-multiplexed:
/// the driver cycles `setExposureModeCustom(duration:iso:)` across a monotonic LIGHT LADDER
/// (default 64²=0 / 32²=+1 / 16²=+2 stops) that MIRRORS the temporal pooling — the 16² pools 4
/// frames, so +2 stops = 4× exposure = the same 4× light its pooling integrates; the 32² pools 2
/// frames = +1 stop = 2×; the 64² is the base single frame. Optical exposure and temporal factor
/// are the SAME number. After each change has had `holdFrames` to clear the ISP pipeline, the
/// settled frame is tagged with the tile it belongs to.
///
/// (Bright scenes: +2 on the 16² can clip highlights — that IS 4× the light. Duration clamps at
/// the format's exposure ceiling and tops up with ISO when it can't reach the stop by shutter.)
///
/// Self-calibrating: it snapshots the scene's metered `(duration, iso)` as the base and
/// brackets around it in real shutter time — duration-primary (the "color-time" knob), falling
/// back to ISO only when duration hits the format's exposure ceiling. Preview-only; the shipped
/// 64-frame burst→GIF path is untouched.
///
/// The cost is honest and inherent, not a bug: 3 levels × `holdFrames` frames per level at the
/// ~20 fps delegate rate ⇒ each tile refreshes at roughly framerate/(3·holdFrames) ≈ 1.5–2 fps.
/// One sensor can only wear one shutter at a time.
///
/// DEVICE-ONLY: the Simulator has no camera. `configure()`/exposure calls only run on real
/// hardware, so this is compile-verified here and behaviourally verified on an iPhone 17 Pro.
final class ExposureBracketDriver {

    enum Rung: Int {
        case r64 = 64, r32 = 32, r16 = 16
        var side: Int { rawValue }
    }
    private struct Level { let ev: Float; let rung: Rung }

    private let device: AVCaptureDevice
    private let holdFrames: Int
    private let schedule: [Level]

    // Base (metered) exposure, snapshot lazily once AE has settled on a value.
    private var baseDuration: Double = 0
    private var baseISO: Float = 0
    private var calibrated = false

    private var levelIndex = 0
    private var framesInLevel = 0

    /// - evByRung: stops per rung. Default = the monotonic LIGHT LADDER (0 / +1 / +2) matching
    ///   the temporal pooling factor (the 16² integrates 4× the light of the 64²). Change these
    ///   for a symmetric HDR bracket (e.g. (-1, 0, +1)) or any other mapping.
    /// - holdFrames: frames to hold each exposure so the ISP pipeline (1–3 frames) clears
    ///   before the frame is tagged; the last held frame is the "settled" one.
    init(device: AVCaptureDevice,
         evByRung: (r64: Float, r32: Float, r16: Float) = (0, +1, +2),
         holdFrames: Int = 4) {
        self.device = device
        self.holdFrames = max(2, holdFrames)
        self.schedule = [Level(ev: evByRung.r64, rung: .r64),
                         Level(ev: evByRung.r32, rung: .r32),
                         Level(ev: evByRung.r16, rung: .r16)]
    }

    /// Feed one delegate-queue preview frame. Returns the `Rung` whose SETTLED frame is THIS
    /// frame (pool + realize it into that tile), or nil while the ISP is settling / calibrating.
    /// Advances the schedule and programs the next real exposure when a level ends.
    func onFrame() -> Rung? {
        guard calibrateIfNeeded() else { return nil }
        framesInLevel += 1
        let settled = framesInLevel >= holdFrames
        let rung = schedule[levelIndex].rung
        if settled { advance() }
        return settled ? rung : nil
    }

    /// Restore continuous AE when optical mode ends (best-effort; delegate-queue safe).
    func end() {
        guard (try? device.lockForConfiguration()) != nil else { return }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        device.unlockForConfiguration()
    }

    // MARK: - internals

    private func calibrateIfNeeded() -> Bool {
        if calibrated { return true }
        let dur = CMTimeGetSeconds(device.exposureDuration)
        let iso = device.iso
        // Wait for a real, non-adjusting metered value before we take over.
        guard dur > 0, iso > 0, !device.isAdjustingExposure else { return false }
        baseDuration = dur
        baseISO = iso
        calibrated = true
        apply(schedule[0])
        framesInLevel = 0
        return true
    }

    private func advance() {
        levelIndex = (levelIndex + 1) % schedule.count
        framesInLevel = 0
        apply(schedule[levelIndex])
    }

    /// Program a REAL exposure for `level`: duration-primary (2^ev × base shutter), clamped to
    /// the active format's range; whatever stops the clamp couldn't deliver are topped up with
    /// ISO. A no-op (leaving the prior exposure) if the device lacks custom exposure.
    private func apply(_ level: Level) {
        guard device.isExposureModeSupported(.custom) else { return }
        let fmt = device.activeFormat
        let minDur = CMTimeGetSeconds(fmt.minExposureDuration)
        let maxDur = CMTimeGetSeconds(fmt.maxExposureDuration)
        let targetDur = baseDuration * pow(2.0, Double(level.ev))
        let dur = min(max(targetDur, minDur), maxDur)
        let durStops = baseDuration > 0 ? log2(dur / baseDuration) : 0
        let residual = Double(level.ev) - durStops
        let iso = min(max(Double(baseISO) * pow(2.0, residual),
                          Double(fmt.minISO)), Double(fmt.maxISO))
        let cmDur = CMTime(seconds: dur, preferredTimescale: 1_000_000_000)
        guard (try? device.lockForConfiguration()) != nil else { return }
        device.setExposureModeCustom(duration: cmDur, iso: Float(iso), completionHandler: nil)
        device.unlockForConfiguration()
    }
}
