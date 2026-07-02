import Testing
@testable import SixFour

/// Byte-exact gate for the V3.0 on-device per-capture training step (workflow B1).
///
/// `DeviceTrainGolden` is generated from `Spec.DeviceTrainStep` by
/// `cabal run spec-codegen`. Three stages, one golden:
///
///   1. PAIR MANUFACTURE — the native lift (`s4_octant_lift`) must produce
///      exactly (coarse, targetDetail) from fineBlock (integer math, no tolerance).
///   2. CPU TWIN — the hand-written mean-gradient descent must COMMIT to exactly
///      `committed` (the post-commit bytes; float paths compare by tolerance only).
///   3. MPSGRAPH — same bytes from the GPU trainer. Physical hardware only
///      (MPSGraph does not execute in the simulator); running this test on the
///      iPhone discharges `contractDeviceGoldenUnrunOnHardware`.
struct DeviceTrainGoldenTests {

    @Test func liftManufacturesTheGoldenPair() throws {
        let pair = try #require(DeviceTrainGoldenCheck.manufacturedPair())
        #expect(pair.coarse == DeviceTrainGolden.coarse)
        #expect(pair.detail == DeviceTrainGolden.targetDetail)
    }

    @Test func zeroParamsCommitToTheFloor() {
        let zero = [Double](repeating: 0, count: DeviceTrainStepCPU.paramCount)
        #expect(DeviceTrainStepCPU.predictCommitted(
            theta: zero, coarse: DeviceTrainGolden.coarse)
            == [Int](repeating: 0, count: DeviceTrainStepCPU.bands))
    }

    @Test func cpuTwinCommitsToTheGoldenBytes() {
        let pair = DeviceTrainStepCPU.Pair(
            coarse: DeviceTrainGolden.coarse, detail: DeviceTrainGolden.targetDetail)
        let theta = DeviceTrainStepCPU.trainDevice(
            steps: DeviceTrainGolden.steps, eta: DeviceTrainGolden.eta, pairs: [pair])

        // The gate: post-commit bytes, BIT-EXACT.
        #expect(DeviceTrainStepCPU.predictCommitted(theta: theta, coarse: pair.coarse)
                == DeviceTrainGolden.committed)

        // The reference: float θ within tolerance of the Haskell descent (same
        // algorithm in Double; summation order is the only slack).
        for (a, b) in zip(theta, DeviceTrainGolden.theta) {
            #expect(abs(a - b) < 1e-9)
        }

        // And the descent genuinely left the floor (loss ≪ floor loss).
        let floorLoss = DeviceTrainStepCPU.lossSum(
            theta: [Double](repeating: 0, count: DeviceTrainStepCPU.paramCount), pairs: [pair])
        #expect(DeviceTrainStepCPU.lossSum(theta: theta, pairs: [pair]) < 1e-6 * floorLoss)
    }

    /// THE HARDWARE OBLIGATION (`contractDeviceGoldenUnrunOnHardware`): the
    /// MPSGraph trainer reproduces the committed bytes on the physical device.
    /// Skipped wherever MPSGraph cannot execute (simulator / no Metal device).
    @Test(.enabled(if: DeviceTrainer.isSupported))
    func mpsGraphTrainerCommitsToTheGoldenBytes() throws {
        let report = DeviceTrainGoldenCheck.run()
        #expect(report.pairManufactureOK)
        #expect(report.cpuCommittedOK)
        let graphOK = try #require(report.graphCommittedOK)
        #expect(graphOK,
                "graph committed \(report.graphCommitted ?? []) != \(DeviceTrainGolden.committed)")
    }
}
