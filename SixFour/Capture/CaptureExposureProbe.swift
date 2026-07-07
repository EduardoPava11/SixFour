import AVFoundation
import CoreMedia

/// DEVICE CAPABILITY PROBE for real optical-EV bracketing (no digital gain anywhere).
///
/// Answers, for the PHYSICAL device this runs on, the two questions that decide the
/// optical-EV design:
///   Q1 — can ONE camera give three real exposures? → `isExposureModeSupported(.custom)`
///        plus the actual shutter/ISO envelope, which sets the TRUE stop-spread we can
///        bracket (you cannot exceed the format's max exposure duration).
///   Q2 — can it open multiple cameras at once? → `AVCaptureMultiCamSession.isMultiCamSupported`
///        and which physical lenses exist. (Multicam = three DIFFERENT focal lengths / FOV,
///        i.e. three framings of the world — NOT three EVs of one scene. It is the wrong tool
///        for "same scene at three exposures"; the right tool is single-camera bracketing.)
///
/// Pure query — no capture, no device mutation. Safe to call any time `device` exists (after
/// `configure()`), and it runs only on a real device (the Simulator has no camera). It NSLogs
/// the report (grep the Console for "SF-probe") and also returns it.
extension CaptureSession {

    func probeCameraCapabilities() -> String {
        guard let device else { return "SF-probe: no device — call after configure()" }
        let fmt = device.activeFormat
        let minDur = CMTimeGetSeconds(fmt.minExposureDuration)
        let maxDur = CMTimeGetSeconds(fmt.maxExposureDuration)
        let curDur = CMTimeGetSeconds(device.exposureDuration)

        // The bracket the duration-ladder driver would use, self-calibrated to THIS device:
        // base = current shutter, then +1 stop (2×) and +2 stops (4×), each clamped to the
        // format's max exposure duration. The real achievable spread is log2(top / base) —
        // if maxDur is close to base (bright scene, already near the ceiling) the coarse tiles
        // cannot reach a full +2 stops via duration alone and the driver falls back to ISO.
        let base = min(max(curDur, minDur), maxDur)
        let mid = min(base * 2, maxDur)
        let long = min(base * 4, maxDur)
        let spreadStops = (long > 0 && base > 0) ? log2(long / base) : 0

        let backLenses = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
            mediaType: .video, position: .back).devices.map(\.localizedName)

        let report = """
        ===== SF-probe: camera capability =====
        device: \(device.localizedName)  [\(device.deviceType.rawValue)]
        --- Q1: one camera, three REAL exposures? ---
        custom exposure (.custom) supported: \(device.isExposureModeSupported(.custom))
        shutter range: \(Self.shutterLabel(minDur)) … \(Self.shutterLabel(maxDur))   (current \(Self.shutterLabel(curDur)))
        ISO range: \(fmt.minISO) … \(fmt.maxISO)   (current \(device.iso))
        exposureTargetBias range: \(device.minExposureTargetBias) … \(device.maxExposureTargetBias) EV
        self-calibrated duration bracket: 64²=\(Self.shutterLabel(base)) | 32²=\(Self.shutterLabel(mid)) (+1) | 16²=\(Self.shutterLabel(long)) (+2)
        REAL achievable spread base→16²: \(String(format: "%.2f", spreadStops)) stops \(spreadStops < 1.9 ? "(duration-capped → driver adds ISO)" : "")
        --- Q2: multiple cameras at once? ---
        AVCaptureMultiCamSession.isMultiCamSupported: \(AVCaptureMultiCamSession.isMultiCamSupported)
        back lenses present: \(backLenses.joined(separator: ", "))
        (multicam = 3 focal lengths / FOV, NOT 3 EVs of one scene → wrong tool here)
        =======================================
        """
        NSLog("%@", report)
        return report
    }

    /// Human shutter label: "1/120s" for sub-second, "0.50s" for long.
    static func shutterLabel(_ seconds: Double) -> String {
        guard seconds > 0 else { return "0" }
        return seconds >= 1 ? String(format: "%.2fs", seconds)
                            : "1/\(Int((1.0 / seconds).rounded()))s"
    }
}
