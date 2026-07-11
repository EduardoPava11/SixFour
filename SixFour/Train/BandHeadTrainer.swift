import Foundation
import Metal

/// THE YANG HEADS TRAIN ON THE IPHONE — plain-Metal fused gradient descent for
/// the tiny linear band heads (`BandHeadShaders.metal`), the RungDispatch
/// pattern: no MPSGraph, so it runs in the simulator; no MLX, no Mac in the
/// loop — the camera app trains itself, per capture, Apple-frameworks-only
/// (the Tier-2 contract).
///
/// The heads are theorem-sized (Spec.YinYangCNN: staged widths {1,2,4} per
/// block, x/y tied by integer symmetrization, S_t un-tied and causal), and
/// their inputs/targets come from the ColorHead ladder in exact integers —
/// this type owns only the float descent between those exact rails. Trained
/// weights re-enter the Zig Q16 floor before any GIF byte (the contract).
///
/// Determinism: the kernel descends sequentially on one GPU thread (fixed
/// accumulation order), so identical inputs give bit-identical weights and
/// losses across runs — gated by BandHeadTrainerTests, alongside the
/// on-simulator replication of the training-occurs proof (structured targets
/// learn to ~zero; noise targets floor; the design's claims, running on the
/// phone's own compute path).
/// @unchecked Sendable: both stored properties are immutable after init and the
/// Metal objects they hold (queue, PSO) are documented thread-safe; every
/// `train` call's mutable state is local buffers. That is what lets `shared`
/// cross into the per-burst detached task.
final class BandHeadTrainer: @unchecked Sendable {

    /// PERF 2026-07-08: the process-wide instance. The trainer used to be
    /// constructed fresh inside every burst's detached task — a new GPUContext
    /// (device + queue + library) and a PSO compile per capture for identical
    /// state. nil where Metal compute is unavailable, exactly like `init?`.
    static let shared = BandHeadTrainer()

    private struct BandHeadParams {
        var nPairs: UInt32
        var nFeatures: UInt32
        var steps: UInt32
        var eta: Float
    }

    private let ctx: GPUContext
    private let pso: any MTLComputePipelineState

    /// Fails (nil) where Metal compute is unavailable — the failable-hook
    /// house pattern.
    init?() {
        guard let ctx = try? GPUContext(queueLabel: "band-head-train"),
              let pso = try? ctx.pso("bandHeadTrainKernel") else { return nil }
        self.ctx = ctx
        self.pso = pso
    }

    struct Result {
        let initialMSE: Float
        let finalMSE: Float
        let weights: [Float]
    }

    /// One fused training run: full-batch GD from the given initial weights.
    /// `features` is row-major (pairs × width). Blocks on completion (these
    /// are millisecond-scale dispatches, the RungDispatch convention).
    func train(
        features: [Float], targets: [Float], featureWidth: Int,
        initialWeights: [Float]? = nil, steps: Int, eta: Float
    ) -> Result? {
        let n = targets.count
        guard n > 0, featureWidth > 0, features.count == n * featureWidth,
              steps >= 0 else { return nil }
        let w0 = initialWeights ?? [Float](repeating: 0, count: featureWidth)
        guard w0.count == featureWidth else { return nil }

        guard let fBuf = ctx.device.makeBuffer(
                bytes: features, length: features.count * 4, options: .storageModeShared),
              let tBuf = ctx.device.makeBuffer(
                bytes: targets, length: n * 4, options: .storageModeShared),
              let wBuf = ctx.device.makeBuffer(
                bytes: w0, length: featureWidth * 4, options: .storageModeShared),
              let lBuf = ctx.device.makeBuffer(length: 2 * 4, options: .storageModeShared)
        else { return nil }

        var params = BandHeadParams(
            nPairs: UInt32(n), nFeatures: UInt32(featureWidth),
            steps: UInt32(steps), eta: eta)

        guard let cmd = ctx.queue.makeCommandBuffer(),
              let enc = cmd.makeComputeCommandEncoder() else { return nil }
        enc.setComputePipelineState(pso)
        enc.setBuffer(fBuf, offset: 0, index: 0)
        enc.setBuffer(tBuf, offset: 0, index: 1)
        enc.setBuffer(wBuf, offset: 0, index: 2)
        enc.setBytes(&params, length: MemoryLayout<BandHeadParams>.stride, index: 3)
        enc.setBuffer(lBuf, offset: 0, index: 4)
        enc.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        // Honest-nil on GPU failure (the RungDispatch guard, device audit
        // 2026-07-11): the first real-corpus capture shipped weights=[0…],
        // MSE 0→0 — impossible on live targets — because a failed command
        // buffer (single-thread 2500-step dispatch at the burst seam; watchdog
        // territory on device, invisible on the simulator's Mac GPU) left the
        // zero-initialized buffers to be read back as a "trained" result.
        // nil = the floor ships and the corpus sidecar records absent, never
        // an invented outcome.
        guard cmd.status == .completed else {
            NSLog("BandHeadTrainer: GPU dispatch failed (\(String(describing: cmd.error))) — returning nil")
            return nil
        }

        let losses = lBuf.contents().assumingMemoryBound(to: Float.self)
        let wOut = wBuf.contents().assumingMemoryBound(to: Float.self)
        return Result(
            initialMSE: losses[0], finalMSE: losses[1],
            weights: (0..<featureWidth).map { wOut[$0] })
    }
}
