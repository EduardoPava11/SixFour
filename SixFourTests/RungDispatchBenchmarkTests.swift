import Testing
import Foundation
@testable import SixFour

/// PERFORMANCE BENCHMARK for the LIVE per-capture learner — the plain-Metal
/// `deviceTrainSimtKernel` behind `RungDispatch` (NOT MPSGraph; that path is the
/// test-only `DeviceTrainer` golden harness). This is the concrete answer to
/// "test the app's MPS performance in learning": it measures, at the REAL
/// per-capture batch size (a 64-frame × 64² burst = 32 768 octant pairs, the
/// `(frames/2)·(side/2)·(side/2)` count), for the θ_up head (21 params, L channel):
///
///   • GPU-only ms per dispatch (`RungDispatch.lastDispatchGPUSeconds` — the command
///     buffer's own `gpuEnd − gpuStart`, excluding CPU staging/readback), and
///   • wall-clock ms per dispatch (the number production logs as `trainMillis`), and
///   • the MARGINAL ms/step (the slope across a step sweep — this isolates the
///     per-step kernel cost from the fixed staging overhead a single reading hides), and
///   • the loss-convergence curve (final loss + lossReduction vs step count).
///
/// It also splits `trainOnVolume` (gather + descent — what a capture actually pays)
/// from `trainSimt` (descent only), so the octant-gather cost is visible.
///
/// This is NOT a correctness gate — those live in `RungDispatchTests` (byte-exact
/// vs the Zig oracle). It is heavy, so it is gated behind the `SIXFOUR_BENCH`
/// environment variable and skips in the normal suite. Run it on a PHYSICAL
/// iPhone 17 Pro (the simulator's single-threadgroup numbers are not the A19's,
/// and the simulator GPU timestamp is noisy — trust the wall-clock column there):
///
///   TEST_RUNNER_SIXFOUR_BENCH=1 xcodebuild test -scheme SixFour \
///     -destination 'platform=iOS,name=<your device>' \
///     -only-testing:SixFourTests/RungDispatchBenchmarkTests
///
/// NOTE the `TEST_RUNNER_` prefix: Xcode's XCTest runner forwards only
/// `TEST_RUNNER_*` variables into the test process (stripping the prefix), so a
/// bare `SIXFOUR_BENCH=1 xcodebuild …` sets a build setting and the gate stays OFF.
/// The results print to the test log (search "SF-BENCH").
struct RungDispatchBenchmarkTests {

    /// Gate: the benchmark runs only when `SIXFOUR_BENCH` is set in the environment.
    private static var benchEnabled: Bool {
        ProcessInfo.processInfo.environment["SIXFOUR_BENCH"] != nil
    }

    /// The real per-capture burst geometry (a full 64³ capture).
    private static let frames = 64
    private static let side = 64
    /// The step counts swept — the slope between the ends is the marginal ms/step.
    private static let stepSweep = [50, 100, 300, 600, 1200]
    /// Samples per step count; the MIN is the least-noisy estimate (fewest interrupts),
    /// the MEDIAN is the typical run. Warmup dispatch is discarded before sampling.
    private static let samples = 5

    // MARK: - deterministic synthetic capture

    /// xorshift64* — a replayable RNG (matches `RungDispatchTests.Rng`).
    private struct Rng {
        var state: UInt64
        mutating func next() -> UInt64 {
            state ^= state >> 12; state ^= state << 25; state ^= state >> 27
            return state &* 0x2545_F491_4F6C_DD1D
        }
    }

    /// A STRUCTURED OKLab-Q16 volume (`frames × side × side × 3` interleaved, the
    /// capture/`captureOctantsKernel` layout) with a **coarse-predictable** fine detail —
    /// the property that makes the convergence curve honest.
    ///
    /// Structure matters (your own `floored-is-data-not-architecture` finding): a flat or
    /// pure-noise volume drives lossReduction to ~0 because the octant detail bands are
    /// then unpredictable from the coarse pool, so the optimal θ is ≈0 and the descent
    /// correctly reduces nothing. Here the construction guarantees learnability: a smooth
    /// coarse field `B` on the 32³ grid, and every fine voxel = `B · (1 + amp·w[corner])`
    /// where `w` is a FIXED within-octant corner pattern. The 2×2×2 lift bands are then
    /// linear in `B` — exactly what the up-rung's `φ(v)=[1,ṽ,ṽ²]` linear term can fit — so
    /// the descent has real, above-noise-floor detail to explain and the loss genuinely drops.
    /// A hair of deterministic jitter keeps a small irreducible residual (a realistic floor).
    private static func syntheticVolume() -> [Int32] {
        var v = [Int32](repeating: 0, count: frames * side * side * 3)
        var rng = Rng(state: 0x5158_464F_5552_3634)
        let twoPi = 2.0 * Double.pi
        // FIXED within-octant corner pattern (constant across octants ⇒ bands are linear
        // in the coarse value ⇒ predictable). Zero-mean so it perturbs, not shifts.
        let w: [Double] = [0.9, -0.7, -0.5, 0.6, -0.8, 0.4, 0.5, -0.4]
        let amp = 0.12
        for f in 0 ..< frames {
            for r in 0 ..< side {
                for c in 0 ..< side {
                    // The smooth COARSE field B, sampled at the octant this voxel belongs to.
                    let ct = Double(f / 2) / Double(frames / 2)
                    let cy = Double(r / 2) / Double(side / 2)
                    let cx = Double(c / 2) / Double(side / 2)
                    let base = 0.5
                        + 0.25 * sin(twoPi * cx) * cos(twoPi * cy)
                        + 0.05 * sin(twoPi * ct)
                    let corner = (f & 1) * 4 + (r & 1) * 2 + (c & 1)
                    let jitter = (Double(rng.next() >> 40) / Double(1 << 24) - 0.5) * 0.003
                    let val = base * (1 + amp * w[corner]) + jitter
                    let q = Int32((val * 65535.0).rounded())
                    let clamped = min(65535, max(0, q))
                    let p = ((f * side + r) * side + c) * 3
                    v[p] = clamped; v[p + 1] = clamped; v[p + 2] = clamped
                }
            }
        }
        return v
    }

    // MARK: - measurement

    private struct Sample {
        var wallMs: Double
        var gpuMs: Double
        var loss: Float
        var lossReduction: Double
    }

    /// The zero-param floor loss on the manufactured pairs — ½ Σ t̃² over the 7 detail
    /// bands of each pair (the same reference `CaptureGene` uses to make `loss` readable).
    private static func floorLoss(pairs: [Int32]) -> Double {
        var sse = 0.0
        for i in stride(from: 0, to: pairs.count, by: 8) {
            for j in 1 ... 7 {
                let t = Double(pairs[i + j]) / 65536.0
                sse += t * t
            }
        }
        return 0.5 * sse
    }

    private static func median(_ xs: [Double]) -> Double {
        let s = xs.sorted()
        return s.isEmpty ? 0 : s[s.count / 2]
    }

    /// Run `steps` `samples` times through `run`, returning one summarised `Sample`
    /// (min wall/gpu ms, plus the loss from the final run). One warmup is discarded.
    private func measure(steps: Int,
                         run: (Int) -> (pairs: [Int32], theta: [Float],
                                        committed: [Int], loss: Float, gpuMs: Double)?)
        -> (min: Sample, median: Sample)?
    {
        _ = run(steps)   // warmup — pays first-touch page-in / clock ramp, discarded
        var walls = [Double](), gpus = [Double]()
        var last: (pairs: [Int32], loss: Float)?
        for _ in 0 ..< Self.samples {
            let t0 = DispatchTime.now().uptimeNanoseconds
            guard let r = run(steps) else { return nil }
            let wall = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
            walls.append(wall)
            gpus.append(r.gpuMs)
            last = (r.pairs, r.loss)
        }
        guard let last else { return nil }
        let floor = Self.floorLoss(pairs: last.pairs)
        let red = floor > 0 ? 1 - Double(last.loss) / floor : 0
        let mn = Sample(wallMs: walls.min() ?? 0, gpuMs: gpus.min() ?? 0,
                        loss: last.loss, lossReduction: red)
        let md = Sample(wallMs: Self.median(walls), gpuMs: Self.median(gpus),
                        loss: last.loss, lossReduction: red)
        return (mn, md)
    }

    private func report(_ title: String, rows: [(steps: Int, min: Sample, median: Sample)]) {
        print("SF-BENCH ── \(title) ──────────────────────────────")
        print("SF-BENCH  steps | gpuMs(min) gpuMs(med) | wallMs(min) wallMs(med) | loss        Δ%floor")
        for row in rows {
            let s = String(format: "SF-BENCH  %5d | %9.3f %9.3f | %10.3f %10.3f | %10.4g  %5.1f%%",
                           row.steps, row.min.gpuMs, row.median.gpuMs,
                           row.min.wallMs, row.median.wallMs,
                           Double(row.min.loss), row.min.lossReduction * 100)
            print(s)
        }
        // Marginal ms/step = slope of GPU time across the sweep ends (isolates the
        // per-step kernel cost from the fixed staging that a single reading hides).
        if let lo = rows.first, let hi = rows.last, hi.steps > lo.steps {
            let slope = (hi.min.gpuMs - lo.min.gpuMs) / Double(hi.steps - lo.steps)
            let fixedGpu = lo.min.gpuMs - slope * Double(lo.steps)     // GPU fixed cost
            let stagingWall = lo.min.wallMs - lo.min.gpuMs             // CPU staging+readback
            print(String(format: "SF-BENCH  → marginal %.4f ms/GPU-step · fixed GPU %.3f ms · CPU staging+readback ~%.3f ms",
                         slope, max(0, fixedGpu), max(0, stagingWall)))
            let per600 = fixedGpu + slope * 600 + stagingWall
            print(String(format: "SF-BENCH  → modelled per-capture (600 steps, gather excluded): ~%.1f ms wall", per600))
        }
        print("SF-BENCH ─────────────────────────────────────────────")
    }

    // MARK: - the benchmarks

    /// DESCENT ONLY: `trainSimt` on the gathered blocks of a real-size structured burst.
    /// This is the pure `deviceTrainSimtKernel` cost — the single-threadgroup ceiling.
    @Test(.enabled(if: RungDispatchBenchmarkTests.benchEnabled))
    func benchmarkDescentOnly() throws {
        let rung = try #require(RungDispatch(), "Metal compute unavailable")
        let volume = Self.syntheticVolume()
        // Gather once on-GPU to get realistic structured blocks (Morton lane order);
        // the descent is then measured in isolation from the gather stage.
        let blocks = try #require(
            rung.gatherOctants(volume: volume, frames: Self.frames,
                               side: Self.side, channel: 0),
            "octant gather failed")
        let nPairs = blocks.count / 8
        print("SF-BENCH descent-only: \(nPairs) octant pairs (\(Self.frames)f × \(Self.side)² burst), 21 params, 1 threadgroup × \(RungDispatch.simtThreads) threads")
        var rows: [(steps: Int, min: Sample, median: Sample)] = []
        for steps in Self.stepSweep {
            guard let m = measure(steps: steps, run: { s in
                guard let r = rung.trainSimt(blocks: blocks, steps: s) else { return nil }
                return (r.pairs, r.theta, r.committed, r.loss, rung.lastDispatchGPUSeconds * 1000)
            }) else { Issue.record("trainSimt returned nil at steps=\(steps)"); return }
            rows.append((steps, m.min, m.median))
        }
        report("DESCENT ONLY (trainSimt)", rows: rows)
    }

    /// GATHER + DESCENT: `trainOnVolume` — exactly what `CaptureGene.train` runs per
    /// capture. The wall-clock gap vs `benchmarkDescentOnly` at the same step count is
    /// the octant-gather cost that a real capture additionally pays.
    @Test(.enabled(if: RungDispatchBenchmarkTests.benchEnabled))
    func benchmarkGatherPlusDescent() throws {
        let rung = try #require(RungDispatch(), "Metal compute unavailable")
        let volume = Self.syntheticVolume()
        print("SF-BENCH gather+descent: full \(Self.frames)f × \(Self.side)² volume → trainOnVolume (the per-capture path)")
        var rows: [(steps: Int, min: Sample, median: Sample)] = []
        for steps in Self.stepSweep {
            guard let m = measure(steps: steps, run: { s in
                guard let r = rung.trainOnVolume(volume: volume, frames: Self.frames,
                                                 side: Self.side, channel: 0, steps: s)
                else { return nil }
                return (r.pairs, r.theta, r.committed, r.loss, rung.lastDispatchGPUSeconds * 1000)
            }) else { Issue.record("trainOnVolume returned nil at steps=\(steps)"); return }
            rows.append((steps, m.min, m.median))
        }
        report("GATHER + DESCENT (trainOnVolume, the per-capture path)", rows: rows)
    }
}
