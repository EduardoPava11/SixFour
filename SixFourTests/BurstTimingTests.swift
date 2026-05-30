import Testing
import Foundation
@testable import SixFour

/// Unit tests for `CaptureSession.computeTiming` — the pure aggregation behind
/// the "measure & warn" timing policy. The function is `static` and consumes a
/// synthetic PTS (presentation-timestamp) array, so these tests need no camera
/// and run in the Simulator test bundle.
///
/// The contract under test: report the real inter-frame cadence honestly so the
/// UI can warn when frames are NOT truly 20 fps (50 ms) apart. No burst is
/// rejected — these numbers are diagnostics, not a gate.
struct BurstTimingTests {

    /// Build a PTS array (seconds) of `count` frames spaced exactly `intervalMs`.
    private func evenPTS(count: Int, intervalMs: Double, startSeconds: Double = 100.0) -> [Double] {
        (0..<count).map { startSeconds + Double($0) * (intervalMs / 1000.0) }
    }

    @Test("Perfect 20fps cadence: mean 50ms, zero deviation")
    func perfectCadence() {
        let pts = evenPTS(count: 64, intervalMs: 50.0)
        let t = CaptureSession.computeTiming(ptsSeconds: pts, targetFps: 20, droppedFrameCount: 0)
        #expect(t.frameCount == 64)
        #expect(abs(t.meanIntervalMs - 50.0) < 1e-6)
        #expect(t.stdIntervalMs < 1e-6)
        #expect(abs(t.minIntervalMs - 50.0) < 1e-6)
        #expect(abs(t.maxIntervalMs - 50.0) < 1e-6)
        #expect(t.worstAbsDeviationMs < 1e-6)
        #expect(t.droppedFrameCount == 0)
        #expect(abs(t.targetIntervalMs - 50.0) < 1e-6)
        // 63 intervals × 50 ms = 3150 ms total span.
        #expect(abs(t.durationMs - 3150.0) < 1e-6)
    }

    @Test("A dropped frame opens a ~100ms gap and shows up in worstAbsDeviation")
    func droppedFrameGap() {
        // 64 evenly-spaced timestamps, then stretch one interval to 100 ms by
        // shifting every timestamp after index 31 forward by 50 ms — simulating
        // one missing frame in the middle of the burst.
        var pts = evenPTS(count: 64, intervalMs: 50.0)
        for i in 32..<pts.count { pts[i] += 0.050 }
        let t = CaptureSession.computeTiming(ptsSeconds: pts, targetFps: 20, droppedFrameCount: 1)
        #expect(abs(t.maxIntervalMs - 100.0) < 1e-6)   // the stretched interval
        #expect(abs(t.worstAbsDeviationMs - 50.0) < 1e-6) // |100 - 50|
        #expect(t.droppedFrameCount == 1)
    }

    @Test("droppedFrameCount passes through even when intervals look clean")
    func dropCountPassthrough() {
        let pts = evenPTS(count: 64, intervalMs: 50.0)
        let t = CaptureSession.computeTiming(ptsSeconds: pts, targetFps: 20, droppedFrameCount: 3)
        #expect(t.droppedFrameCount == 3)
        #expect(t.worstAbsDeviationMs < 1e-6) // intervals themselves are perfect
    }

    @Test("worstAbsDeviation tracks the largest single jitter, not the mean")
    func worstDeviationIsMaxNotMean() {
        // Mostly perfect, with one short (44 ms) and one long (56 ms) interval.
        var pts = evenPTS(count: 10, intervalMs: 50.0)
        // Make interval index 2 shorter: pull frame 3 back by 6 ms, push all after.
        for i in 3..<pts.count { pts[i] -= 0.006 }
        // Make interval index 6 longer: push frame 7 onward forward by 6 ms.
        for i in 7..<pts.count { pts[i] += 0.006 }
        let t = CaptureSession.computeTiming(ptsSeconds: pts, targetFps: 20, droppedFrameCount: 0)
        // The two perturbed intervals are 44 ms and 56 ms → worst |Δ| = 6 ms.
        #expect(abs(t.worstAbsDeviationMs - 6.0) < 1e-6)
        #expect(abs(t.minIntervalMs - 44.0) < 1e-6)
        #expect(abs(t.maxIntervalMs - 56.0) < 1e-6)
    }

    @Test("Degenerate burst (<2 frames) yields zeroed stats, never a crash")
    func degenerateBurst() {
        let one = CaptureSession.computeTiming(ptsSeconds: [100.0], targetFps: 20, droppedFrameCount: 0)
        #expect(one.frameCount == 1)
        #expect(one.durationMs == 0)
        #expect(one.meanIntervalMs == 0)
        #expect(one.worstAbsDeviationMs == 0)
        #expect(abs(one.targetIntervalMs - 50.0) < 1e-6)

        let none = CaptureSession.computeTiming(ptsSeconds: [], targetFps: 20, droppedFrameCount: 2)
        #expect(none.frameCount == 0)
        #expect(none.droppedFrameCount == 2) // still reported in the degenerate path
    }

    @Test("Pre-existing bundles (missing the new fields) still decode, defaulting to 0")
    func backCompatDecode() throws {
        // A BurstTiming JSON saved before worstAbsDeviationMs/droppedFrameCount existed.
        let json = """
        {"frameCount":64,"durationMs":3150.0,"meanIntervalMs":50.0,"stdIntervalMs":0.3,\
        "minIntervalMs":49.5,"maxIntervalMs":50.5,"targetIntervalMs":50.0}
        """.data(using: .utf8)!
        let t = try JSONDecoder().decode(CaptureSession.BurstTiming.self, from: json)
        #expect(t.frameCount == 64)
        #expect(t.worstAbsDeviationMs == 0)   // defaulted, not keyNotFound
        #expect(t.droppedFrameCount == 0)
    }

    @Test("Summary string includes worst-deviation and dropped-frame fields")
    func summaryMentionsNewFields() {
        let pts = evenPTS(count: 64, intervalMs: 50.0)
        let t = CaptureSession.computeTiming(ptsSeconds: pts, targetFps: 20, droppedFrameCount: 0)
        #expect(t.summary.contains("worst Δ"))
        #expect(t.summary.contains("dropped 0"))
    }
}
