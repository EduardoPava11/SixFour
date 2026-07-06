import Foundation
import Metal

/// Host surface for the V3.0 rung-cascade Metal kernels (workflow B2 —
/// `Metal/DeviceTrainShaders.metal`): the byte-exact INTEGER twins of the Zig
/// rung ops (`octantLiftKernel`/`octantUnliftKernel`, gated against
/// `SixFourNative.octantLift` in `RungDispatchTests`) and the FUSED rung
/// training dispatch (`deviceTrainFusedKernel`: int lift → fp32 θ_up descent →
/// Q16 commit, one command buffer, no CPU round trip).
///
/// Plain Metal compute — runs in the simulator too (unlike MPSGraph), so the
/// whole cascade is CI-checkable; the physical-device run additionally proves
/// the A19. Gates on the SAME bytes as every other backend:
/// `DeviceTrainGolden.committed`.
///
/// Concurrency: not Sendable — confine to one queue/actor. All calls block on
/// `waitUntilCompleted` (these are millisecond-scale dispatches).
final class RungDispatch {

    /// Must mirror `FusedTrainParams` in DeviceTrainShaders.metal.
    private struct FusedTrainParams {
        var n: UInt32
        var steps: UInt32
        var eta: Float
    }

    /// The fused kernel's compile-time batch bound (`kMaxFusedPairs`).
    static let maxFusedPairs = 64

    /// The SIMT kernel's threadgroup width (`kSimtThreads`).
    static let simtThreads = 256

    private let ctx: GPUContext
    private let liftPSO: any MTLComputePipelineState
    private let unliftPSO: any MTLComputePipelineState
    private let fusedPSO: any MTLComputePipelineState
    private let simtPSO: any MTLComputePipelineState
    private let gatherPSO: any MTLComputePipelineState
    private let expandPSO: any MTLComputePipelineState

    /// GPU-only wall time (seconds) of the LAST `runSimtPass` dispatch — the command
    /// buffer's own `gpuEndTime − gpuStartTime`, valid after `waitUntilCompleted`. This
    /// EXCLUDES the CPU staging (buffer alloc + upload) and readback that the wall-clock
    /// `trainMillis` includes, so it isolates the descent kernel itself. Telemetry only;
    /// zero until the first dispatch. Read after `trainSimt`/`trainOnVolume` (queue-confined,
    /// like the rest of this class). Used by `RungDispatchBenchmarkTests`.
    private(set) var lastDispatchGPUSeconds: Double = 0

    /// Fails (nil) where Metal compute is unavailable — the failable-hook
    /// house pattern.
    init?() {
        do {
            let ctx = try GPUContext(queueLabel: "device-train-rung")
            self.ctx = ctx
            self.liftPSO = try ctx.pso("octantLiftKernel")
            self.unliftPSO = try ctx.pso("octantUnliftKernel")
            self.fusedPSO = try ctx.pso("deviceTrainFusedKernel")
            self.simtPSO = try ctx.pso("deviceTrainSimtKernel")
            self.gatherPSO = try ctx.pso("captureOctantsKernel")
            self.expandPSO = try ctx.pso("cubeExpandRungKernel")
        } catch {
            return nil
        }
    }

    /// N octant lifts on-GPU: `blocks` is N×8 fine cells (Morton lane order);
    /// returns N×8 `[coarse, g0, b0, t0, g1, b1, t1, dz]` rows — byte-exact to
    /// `SixFourNative.octantLift` per row.
    func liftOctants(blocks: [Int32]) -> [Int32]? {
        runTwin(pso: liftPSO, input: blocks)
    }

    /// N octant unlifts on-GPU (the exact inverse; the reversibility twin).
    func unliftOctants(bands: [Int32]) -> [Int32]? {
        runTwin(pso: unliftPSO, input: bands)
    }

    /// Must mirror `CubeExpandParams` in DeviceTrainShaders.metal.
    private struct CubeExpandParams {
        var side: UInt32
        var hasDetails: UInt32
    }

    /// ONE volume up-rung on-GPU (the export-rung operator, L1.2): `volume` is a
    /// side³ scalar cube in the device layout ((t·side + r)·side + c); `details`
    /// nil = the zero-detail deterministic floor, else side³×7 voxel-major
    /// COMMITTED Q16 bands (the θ float layer stays outside — the sandwich).
    /// Returns the (2·side)³ fine cube — byte-exact to the Zig oracle
    /// `SixFourNative.cubeExpandRung` (gated in `RungDispatchTests`).
    func expandRung(volume: [Int32], side: Int, details: [Int32]?) -> [Int32]? {
        let n = side * side * side
        guard side > 0, volume.count == n,
              details.map({ $0.count == n * 7 }) ?? true else { return nil }
        let device = ctx.device
        let fineCount = 8 * n
        guard
            let volBuf = makeBuffer(device, volume),
            let detBuf = makeBuffer(device, details ?? [0]),   // dummy when floor
            let outBuf = device.makeBuffer(length: fineCount * 4, options: .storageModeShared),
            let cmd = ctx.queue.makeCommandBuffer(),
            let enc = cmd.makeComputeCommandEncoder()
        else { return nil }

        var params = CubeExpandParams(side: UInt32(side),
                                      hasDetails: details == nil ? 0 : 1)
        enc.setComputePipelineState(expandPSO)
        enc.setBuffer(volBuf, offset: 0, index: 0)
        enc.setBuffer(detBuf, offset: 0, index: 1)
        enc.setBuffer(outBuf, offset: 0, index: 2)
        enc.setBytes(&params, length: MemoryLayout<CubeExpandParams>.stride, index: 3)
        let w = min(expandPSO.maxTotalThreadsPerThreadgroup, 256)
        enc.dispatchThreads(MTLSize(width: n, height: 1, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: w, height: 1, depth: 1))
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        guard cmd.status == .completed else { return nil }
        return readInts(outBuf, count: fineCount)
    }

    /// THE FUSED RUNG DISPATCH: manufacture the pairs from `blocks` (int lift),
    /// descend θ_up (mean-gradient, fp32, from the zero floor), and Q16-commit
    /// at the first pair's coarse — all inside one GPU dispatch.
    ///
    /// Returns the manufactured pairs (N×8, for the Zig-oracle parity check),
    /// θ in the spec's flat row-major layout, and the committed bands (the
    /// `DeviceTrainGolden.committed` gate bytes). `blocks.count/8` must be in
    /// `1...maxFusedPairs`.
    func trainFused(blocks: [Int32],
                    steps: Int = DeviceTrainGolden.steps,
                    eta: Float = Float(DeviceTrainGolden.eta))
        -> (pairs: [Int32], theta: [Float], committed: [Int])?
    {
        let n = blocks.count / 8
        guard blocks.count % 8 == 0, n >= 1, n <= Self.maxFusedPairs, steps > 0 else { return nil }
        let device = ctx.device
        guard
            let blocksBuf = makeBuffer(device, blocks),
            let pairsBuf = device.makeBuffer(length: blocks.count * 4, options: .storageModeShared),
            let thetaBuf = device.makeBuffer(length: 21 * 4, options: .storageModeShared),
            let committedBuf = device.makeBuffer(length: 7 * 4, options: .storageModeShared),
            let cmd = ctx.queue.makeCommandBuffer(),
            let enc = cmd.makeComputeCommandEncoder()
        else { return nil }

        var params = FusedTrainParams(n: UInt32(n), steps: UInt32(steps), eta: eta)
        enc.setComputePipelineState(fusedPSO)
        enc.setBuffer(blocksBuf, offset: 0, index: 0)
        enc.setBuffer(pairsBuf, offset: 0, index: 1)
        enc.setBuffer(thetaBuf, offset: 0, index: 2)
        enc.setBuffer(committedBuf, offset: 0, index: 3)
        enc.setBytes(&params, length: MemoryLayout<FusedTrainParams>.stride, index: 4)
        enc.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        guard cmd.status == .completed else { return nil }

        let pairs = readInts(pairsBuf, count: blocks.count)
        let theta = readFloats(thetaBuf, count: 21)
        let committed = readInts(committedBuf, count: 7).map(Int.init)
        return (pairs, theta, committed)
    }

    /// THE DETERMINISTIC-SIMT BATCH TRAINER (B2.2): the real per-capture regime —
    /// thousands of octant pairs in one dispatch. One threadgroup of
    /// `simtThreads`, strided lift + staging, fixed-order tree-reduced
    /// mean-gradient descent (bitwise-reproducible: same input bits → same output
    /// bits, asserted in `RungDispatchTests`), Q16 commit at pair 0's coarse.
    /// Also returns the final summed supervised loss (telemetry).
    func trainSimt(blocks: [Int32],
                   steps: Int = DeviceTrainGolden.steps,
                   eta: Float = Float(DeviceTrainGolden.eta),
                   w0: [Float]? = nil)
        -> (pairs: [Int32], theta: [Float], committed: [Int], loss: Float)?
    {
        let n = blocks.count / 8
        guard blocks.count % 8 == 0, n >= 1, steps > 0,
              let blocksBuf = makeBuffer(ctx.device, blocks),
              let cmd = ctx.queue.makeCommandBuffer()
        else { return nil }
        return runSimtPass(cmd: cmd, blocksBuf: blocksBuf, n: n, steps: steps, eta: eta, w0: w0)
    }

    // ── B2.3: the capture fusion ────────────────────────────────────────────

    /// Gather every octant block of one channel of a captured OKLab Q16 volume
    /// (`frames × side × side × 3` interleaved, the `s4_synth_burst`/capture
    /// layout) on-GPU. Exposed for the I/O parity test; `trainOnVolume` chains
    /// the same kernel in front of the trainer.
    func gatherOctants(volume: [Int32], frames: Int, side: Int, channel: Int) -> [Int32]? {
        guard let staged = stageGather(volume: volume, frames: frames, side: side,
                                       channel: channel),
              let cmd = ctx.queue.makeCommandBuffer(),
              let enc = cmd.makeComputeCommandEncoder()
        else { return nil }
        encodeGather(enc, staged: staged)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        guard cmd.status == .completed else { return nil }
        return readInts(staged.blocksBuf, count: staged.nOct * 8)
    }

    /// THE B2.3 FUSED CAPTURE TRAINER: [octant gather] → [deterministic-SIMT
    /// descent] in ONE command buffer (two encoders; the blocks buffer never
    /// leaves the GPU). Input is the capture-shaped OKLab Q16 volume; output is
    /// the trained θ_up + the committed bands + loss telemetry. Byte-equivalent
    /// to gathering on CPU and calling `trainSimt` — asserted bitwise in
    /// `RungDispatchTests`.
    func trainOnVolume(volume: [Int32], frames: Int, side: Int, channel: Int = 0,
                       steps: Int = DeviceTrainGolden.steps,
                       eta: Float = Float(DeviceTrainGolden.eta),
                       w0: [Float]? = nil)
        -> (pairs: [Int32], theta: [Float], committed: [Int], loss: Float)?
    {
        guard steps > 0,
              let staged = stageGather(volume: volume, frames: frames, side: side,
                                       channel: channel),
              let cmd = ctx.queue.makeCommandBuffer(),
              let gatherEnc = cmd.makeComputeCommandEncoder()
        else { return nil }
        encodeGather(gatherEnc, staged: staged)
        gatherEnc.endEncoding()
        // Second encoder on the SAME command buffer: tracked-resource hazard
        // ordering makes the gathered blocks visible to the trainer, no CPU stop.
        return runSimtPass(cmd: cmd, blocksBuf: staged.blocksBuf, n: staged.nOct,
                           steps: steps, eta: eta, w0: w0)
    }

    // ── plumbing ────────────────────────────────────────────────────────────

    /// Must mirror `OctGatherParams` in DeviceTrainShaders.metal.
    private struct OctGatherParams {
        var frames: UInt32
        var side: UInt32
        var channel: UInt32
    }

    private struct StagedGather {
        var volumeBuf: any MTLBuffer
        var blocksBuf: any MTLBuffer
        var params: OctGatherParams
        var nOct: Int
    }

    /// Validate + upload a capture volume and allocate the on-GPU blocks buffer.
    private func stageGather(volume: [Int32], frames: Int, side: Int,
                             channel: Int) -> StagedGather? {
        guard frames >= 2, frames % 2 == 0, side >= 2, side % 2 == 0,
              (0 ..< 3).contains(channel),
              volume.count == frames * side * side * 3
        else { return nil }
        let nOct = (frames / 2) * (side / 2) * (side / 2)
        guard
            let volumeBuf = makeBuffer(ctx.device, volume),
            let blocksBuf = ctx.device.makeBuffer(length: nOct * 8 * 4,
                                                  options: .storageModeShared)
        else { return nil }
        return StagedGather(
            volumeBuf: volumeBuf, blocksBuf: blocksBuf,
            params: OctGatherParams(frames: UInt32(frames), side: UInt32(side),
                                    channel: UInt32(channel)),
            nOct: nOct)
    }

    private func encodeGather(_ enc: any MTLComputeCommandEncoder, staged: StagedGather) {
        var params = staged.params
        enc.setComputePipelineState(gatherPSO)
        enc.setBuffer(staged.volumeBuf, offset: 0, index: 0)
        enc.setBuffer(staged.blocksBuf, offset: 0, index: 1)
        enc.setBytes(&params, length: MemoryLayout<OctGatherParams>.stride, index: 2)
        let tg = min(staged.nOct, gatherPSO.maxTotalThreadsPerThreadgroup)
        enc.dispatchThreads(MTLSize(width: staged.nOct, height: 1, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: tg, height: 1, depth: 1))
    }

    /// Encode the SIMT training pass on `cmd` (its own encoder), commit, wait,
    /// and read back. Shared by `trainSimt` (blocks from the host) and
    /// `trainOnVolume` (blocks from the in-buffer gather stage).
    private func runSimtPass(cmd: any MTLCommandBuffer, blocksBuf: any MTLBuffer,
                             n: Int, steps: Int, eta: Float, w0: [Float]? = nil)
        -> (pairs: [Int32], theta: [Float], committed: [Int], loss: Float)?
    {
        let device = ctx.device
        // The meta-INIT W₀ the descent starts from (buffer 7). Default = the zero floor,
        // so the un-meta path is byte-identical to the old `th = 0` init (the golden holds).
        let initTheta = (w0?.count == 21) ? w0! : [Float](repeating: 0, count: 21)
        guard
            let pairsBuf = device.makeBuffer(length: n * 8 * 4, options: .storageModeShared),
            let thetaBuf = device.makeBuffer(length: 21 * 4, options: .storageModeShared),
            let committedBuf = device.makeBuffer(length: 7 * 4, options: .storageModeShared),
            let scratchBuf = device.makeBuffer(length: n * 10 * 4, options: .storageModeShared),
            let lossBuf = device.makeBuffer(length: 4, options: .storageModeShared),
            let initBuf = initTheta.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: 21 * 4, options: .storageModeShared) }),
            let enc = cmd.makeComputeCommandEncoder()
        else { return nil }

        var params = FusedTrainParams(n: UInt32(n), steps: UInt32(steps), eta: eta)
        enc.setComputePipelineState(simtPSO)
        enc.setBuffer(blocksBuf, offset: 0, index: 0)
        enc.setBuffer(pairsBuf, offset: 0, index: 1)
        enc.setBuffer(thetaBuf, offset: 0, index: 2)
        enc.setBuffer(committedBuf, offset: 0, index: 3)
        enc.setBytes(&params, length: MemoryLayout<FusedTrainParams>.stride, index: 4)
        enc.setBuffer(scratchBuf, offset: 0, index: 5)
        enc.setBuffer(lossBuf, offset: 0, index: 6)
        enc.setBuffer(initBuf, offset: 0, index: 7)
        // ONE threadgroup — the whole problem synchronizes on threadgroup barriers.
        enc.dispatchThreadgroups(
            MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: Self.simtThreads, height: 1, depth: 1))
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        guard cmd.status == .completed else { return nil }
        // GPU-only time of the descent (excludes CPU staging/readback) — benchmark telemetry.
        lastDispatchGPUSeconds = cmd.gpuEndTime - cmd.gpuStartTime

        let pairs = readInts(pairsBuf, count: n * 8)
        let theta = readFloats(thetaBuf, count: 21)
        let committed = readInts(committedBuf, count: 7).map(Int.init)
        let loss = readFloats(lossBuf, count: 1)[0]
        return (pairs, theta, committed, loss)
    }

    /// Run one of the N×8 → N×8 integer twin kernels.
    private func runTwin(pso: any MTLComputePipelineState, input: [Int32]) -> [Int32]? {
        let n = input.count / 8
        guard input.count % 8 == 0, n >= 1 else { return nil }
        let device = ctx.device
        guard
            let inBuf = makeBuffer(device, input),
            let outBuf = device.makeBuffer(length: input.count * 4, options: .storageModeShared),
            let cmd = ctx.queue.makeCommandBuffer(),
            let enc = cmd.makeComputeCommandEncoder()
        else { return nil }

        var count = UInt32(n)
        enc.setComputePipelineState(pso)
        enc.setBuffer(inBuf, offset: 0, index: 0)
        enc.setBuffer(outBuf, offset: 0, index: 1)
        enc.setBytes(&count, length: MemoryLayout<UInt32>.stride, index: 2)
        let tg = min(n, pso.maxTotalThreadsPerThreadgroup)
        enc.dispatchThreads(MTLSize(width: n, height: 1, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: tg, height: 1, depth: 1))
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        guard cmd.status == .completed else { return nil }
        return readInts(outBuf, count: input.count)
    }

    private func makeBuffer(_ device: any MTLDevice, _ values: [Int32]) -> (any MTLBuffer)? {
        values.withUnsafeBufferPointer { ptr in
            device.makeBuffer(bytes: ptr.baseAddress!, length: values.count * 4,
                              options: .storageModeShared)
        }
    }

    private func readInts(_ buf: any MTLBuffer, count: Int) -> [Int32] {
        let p = buf.contents().bindMemory(to: Int32.self, capacity: count)
        return Array(UnsafeBufferPointer(start: p, count: count))
    }

    private func readFloats(_ buf: any MTLBuffer, count: Int) -> [Float] {
        let p = buf.contents().bindMemory(to: Float.self, capacity: count)
        return Array(UnsafeBufferPointer(start: p, count: count))
    }
}
