import Testing
@testable import SixFour

/// The B2 cascade gates (`Metal/DeviceTrainShaders.metal` via `RungDispatch`):
///
///   1. TWIN PARITY — the Metal integer octant lift must be byte-exact to the
///      Zig oracle (`SixFourNative.octantLift` = `s4_octant_lift`) on random
///      blocks INCLUDING negatives (the floor-division sign path — C `/`
///      truncates, the spec floors; `fdiv2` is the porting hazard this pins).
///   2. REVERSIBILITY — unlift(lift(x)) == x on-GPU.
///   3. THE FUSED DISPATCH — [int lift → fp32 θ_up descent → Q16 commit] in one
///      command buffer commits EXACTLY `DeviceTrainGolden.committed`: the third
///      backend (after Haskell and the Swift CPU twin) gated on the same bytes.
///
/// Plain Metal compute — all three run in the simulator; the device run proves
/// the A19.
struct RungDispatchTests {

    /// Deterministic xorshift64* so the random-block sweep is replayable.
    private struct Rng {
        var state: UInt64
        mutating func next() -> UInt64 {
            state ^= state >> 12; state ^= state << 25; state ^= state >> 27
            return state &* 0x2545_F491_4F6C_DD1D
        }
        /// Uniform in -bound...bound (exercises the negative floor-div path).
        mutating func int32(bound: Int32) -> Int32 {
            Int32(truncatingIfNeeded: next() % UInt64(2 * bound + 1)) - bound
        }
    }

    private func randomBlocks(count: Int, seed: UInt64) -> [Int32] {
        var rng = Rng(state: seed)
        return (0 ..< count * 8).map { _ in rng.int32(bound: 60000) }
    }

    @Test func metalLiftIsByteExactToZigOracle() throws {
        let rung = try #require(RungDispatch())
        let blocks = randomBlocks(count: 256, seed: 0x5158_464F_5552_3634)
            + DeviceTrainGolden.fineBlock.map(Int32.init)   // the golden block too
        let metal = try #require(rung.liftOctants(blocks: blocks))
        for i in 0 ..< blocks.count / 8 {
            let block = Array(blocks[i * 8 ..< i * 8 + 8])
            let zig = try #require(SixFourNative.octantLift(block: block))
            #expect(Array(metal[i * 8 ..< i * 8 + 8]) == zig, "octant \(i)")
        }
    }

    @Test func metalRoundTripIsIdentity() throws {
        let rung = try #require(RungDispatch())
        let blocks = randomBlocks(count: 256, seed: 0x6465_7669_6365_3634)
        let bands = try #require(rung.liftOctants(blocks: blocks))
        let back = try #require(rung.unliftOctants(bands: bands))
        #expect(back == blocks)
    }

    @Test func fusedDispatchCommitsTheGoldenBytes() throws {
        let rung = try #require(RungDispatch())
        let out = try #require(rung.trainFused(
            blocks: DeviceTrainGolden.fineBlock.map(Int32.init)))

        // The in-dispatch lift manufactured exactly the golden pair.
        #expect(out.pairs.map(Int.init)
                == [DeviceTrainGolden.coarse] + DeviceTrainGolden.targetDetail)

        // THE GATE: the committed bands, bit-exact — same bytes as Haskell,
        // the CPU twin, and (on hardware) MPSGraph.
        #expect(out.committed == DeviceTrainGolden.committed)

        // fp32 θ within tolerance of the Haskell Double descent (reference only).
        for (a, b) in zip(out.theta, DeviceTrainGolden.theta) {
            #expect(abs(Double(a) - b) < 1e-5)
        }
    }

    // ── B2.2: the deterministic-SIMT batch trainer ──────────────────────────

    @Test func simtCommitsTheGoldenBytesOnTheFixture() throws {
        let rung = try #require(RungDispatch())
        let out = try #require(rung.trainSimt(
            blocks: DeviceTrainGolden.fineBlock.map(Int32.init)))
        #expect(out.pairs.map(Int.init)
                == [DeviceTrainGolden.coarse] + DeviceTrainGolden.targetDetail)
        #expect(out.committed == DeviceTrainGolden.committed)   // 4th backend, same bytes
        for (a, b) in zip(out.theta, DeviceTrainGolden.theta) {
            #expect(abs(Double(a) - b) < 1e-5)
        }
    }

    /// THE SIMT DETERMINISM CONTRACT: fp32 addition is non-associative, so
    /// reproducibility is a property of the reduction ORDER — the fixed tree
    /// pins it. Same input bits → same output bits, run after run.
    @Test func simtIsBitwiseReproducibleOnALargeBatch() throws {
        let rung = try #require(RungDispatch())
        let blocks = randomBlocks(count: 2048, seed: 0x7369_6D74_7370_696E)
        let a = try #require(rung.trainSimt(blocks: blocks))
        let b = try #require(rung.trainSimt(blocks: blocks))
        #expect(a.theta.map(\.bitPattern) == b.theta.map(\.bitPattern))
        #expect(a.loss.bitPattern == b.loss.bitPattern)
        #expect(a.committed == b.committed)
        #expect(a.pairs == b.pairs)
    }

    /// Input/output at the per-capture scale (2048 pairs): the strided in-dispatch
    /// lift is byte-exact to the Zig oracle for EVERY pair, and the SIMT descent
    /// agrees with the CPU Double twin (θ tolerance; loss relative tolerance;
    /// and it genuinely learned — loss well below the zero-param floor).
    @Test func simtLargeBatchMatchesTheCPUDoubleTwin() throws {
        let rung = try #require(RungDispatch())
        let blocks = randomBlocks(count: 2048, seed: 0x3634_5349_4D54_4c42)
        let out = try #require(rung.trainSimt(blocks: blocks))

        // Lift stage I/O: every manufactured pair == the Zig oracle.
        var pairs = [DeviceTrainStepCPU.Pair]()
        for i in 0 ..< 2048 {
            let block = Array(blocks[i * 8 ..< i * 8 + 8])
            let zig = try #require(SixFourNative.octantLift(block: block))
            #expect(Array(out.pairs[i * 8 ..< i * 8 + 8]) == zig, "octant \(i)")
            pairs.append(DeviceTrainStepCPU.Pair(
                coarse: Int(zig[0]), detail: zig[1...].map(Int.init)))
        }

        // Descent I/O vs the Double reference (same pairs, same η/steps).
        let cpuTheta = DeviceTrainStepCPU.trainDevice(
            steps: DeviceTrainGolden.steps, eta: DeviceTrainGolden.eta, pairs: pairs)
        for (a, b) in zip(out.theta, cpuTheta) {
            #expect(abs(Double(a) - b) < 2e-4)
        }
        let cpuLoss = DeviceTrainStepCPU.lossSum(theta: cpuTheta, pairs: pairs)
        #expect(abs(Double(out.loss) - cpuLoss) < 1e-3 * max(1, cpuLoss))

        // And the batch genuinely descended from the floor.
        let floorLoss = DeviceTrainStepCPU.lossSum(
            theta: [Double](repeating: 0, count: DeviceTrainStepCPU.paramCount),
            pairs: pairs)
        #expect(Double(out.loss) < floorLoss)
    }

    // ── B2.3: the capture fusion (volume → gather → SIMT, one command buffer) ──

    /// The host-side reference of `captureOctantsKernel`'s gather (same lane
    /// order: (df, drow, dcol), col fastest — near-t face first).
    private func cpuGather(volume: [Int32], frames: Int, side: Int, channel: Int) -> [Int32] {
        var out = [Int32]()
        out.reserveCapacity((frames / 2) * (side / 2) * (side / 2) * 8)
        for f in 0 ..< frames / 2 {
            for r in 0 ..< side / 2 {
                for c in 0 ..< side / 2 {
                    for df in 0 ... 1 {
                        for dr in 0 ... 1 {
                            for dc in 0 ... 1 {
                                let flat = (((2 * f + df) * side + (2 * r + dr)) * side
                                            + (2 * c + dc)) * 3 + channel
                                out.append(volume[flat])
                            }
                        }
                    }
                }
            }
        }
        return out
    }

    @Test func gatherMatchesTheCPUReferenceOnEveryChannel() throws {
        let rung = try #require(RungDispatch())
        let volume = try #require(SixFourNative.synthBurst(
            seed: 0x4232_3300, mode: 0, frameCount: 16, side: 16))
        for channel in 0 ..< 3 {
            let gpu = try #require(rung.gatherOctants(
                volume: volume, frames: 16, side: 16, channel: channel))
            #expect(gpu == cpuGather(volume: volume, frames: 16, side: 16,
                                     channel: channel), "channel \(channel)")
        }
    }

    /// Fusion introduces ZERO drift: [gather → SIMT] in one command buffer is
    /// bitwise-identical to gathering on the CPU and running the blocks path.
    @Test func volumeTrainingIsBitwiseEqualToTheBlocksPath() throws {
        let rung = try #require(RungDispatch())
        let volume = try #require(SixFourNative.synthBurst(
            seed: 0x4232_3301, mode: 0, frameCount: 16, side: 16))
        let fused = try #require(rung.trainOnVolume(
            volume: volume, frames: 16, side: 16, channel: 0, steps: 120))
        let blocks = cpuGather(volume: volume, frames: 16, side: 16, channel: 0)
        let staged = try #require(rung.trainSimt(blocks: blocks, steps: 120))
        #expect(fused.pairs == staged.pairs)
        #expect(fused.theta.map(\.bitPattern) == staged.theta.map(\.bitPattern))
        #expect(fused.loss.bitPattern == staged.loss.bitPattern)
        #expect(fused.committed == staged.committed)
    }

    /// THE FLAGSHIP: a real-shaped capture (64 frames × 64×64 OKLab Q16 via the
    /// same synth generator the Mac trainer uses) → 32,768 octant pairs → the
    /// full 600-step θ_up fine-tune, all in ONE command buffer. Learns (loss
    /// below the zero-param floor) and is bitwise-reproducible.
    @Test func realShapedCaptureTrainsInOneCommandBuffer() throws {
        let rung = try #require(RungDispatch())
        let volume = try #require(SixFourNative.synthBurst(
            seed: 0x4232_3302, mode: 0, frameCount: 64, side: 64))

        let a = try #require(rung.trainOnVolume(volume: volume, frames: 64, side: 64))
        #expect(a.pairs.count == 32768 * 8)

        // Learned: loss strictly below the zero-param floor (floor computed on
        // the CPU from the SAME pairs the dispatch manufactured).
        var pairs = [DeviceTrainStepCPU.Pair]()
        pairs.reserveCapacity(32768)
        for i in 0 ..< 32768 {
            pairs.append(DeviceTrainStepCPU.Pair(
                coarse: Int(a.pairs[i * 8]),
                detail: a.pairs[i * 8 + 1 ..< i * 8 + 8].map(Int.init)))
        }
        let floorLoss = DeviceTrainStepCPU.lossSum(
            theta: [Double](repeating: 0, count: DeviceTrainStepCPU.paramCount),
            pairs: pairs)
        #expect(floorLoss > 0)
        #expect(Double(a.loss) < floorLoss)

        // Deterministic-SIMT: run twice, same bits.
        let b = try #require(rung.trainOnVolume(volume: volume, frames: 64, side: 64))
        #expect(a.theta.map(\.bitPattern) == b.theta.map(\.bitPattern))
        #expect(a.loss.bitPattern == b.loss.bitPattern)
        #expect(a.committed == b.committed)
    }
}
