import Foundation
import Metal
import MetalPerformanceShaders
import MetalPerformanceShadersGraph

/// V3.0 ON-DEVICE per-capture training (workflow B1, `docs/V3-BUILD-WORKFLOW.md`).
///
/// Trains the up-rung detail inventor `f_θ : coarse → detail` (the 21-param
/// `Spec.DetailPredictor` head — 7 bands × φ(v) = [1, ṽ, ṽ²]) on supervision pairs
/// the capture itself manufactures: `(coarse, detail) = octantLift(fineBlock)` is
/// the EXACT reversible pool (`SixFourNative.octantLift` = `s4_octant_lift` =
/// `OctreeCell.liftOct`), so every burst carries its own ground truth and no
/// corpus ever crosses to the phone (`Spec.DeviceTrainStep.supervisionPair`).
///
/// The contract is `Generated/DeviceTrainGolden.swift` (emitted by
/// `Codegen.DeviceTrain`): manufacture the pair from `fineBlock`, descend the
/// MEAN gradient with the same η/steps, and commit — through the single
/// sanctioned Q16 crossing, `round-half-to-even(raw · 65536)` — to EXACTLY
/// `DeviceTrainGolden.committed`. Float trajectories legitimately differ across
/// backends (Haskell Double, MLX float64, fp32 here); the POST-COMMIT bytes may
/// not. The fixture is fp32-robust by construction (integer targets in Q16
/// units; converged raw error ≪ the 0.5 rounding margin).
///
/// Two backends, one golden:
///   * `DeviceTrainStepCPU` — the hand-written Swift reference twin (Double).
///     Runs everywhere (simulator included); the math gate.
///   * `DeviceTrainer` — the MPSGraph trainer (the `AtlasTrainer` pattern:
///     `gradients(of:with:)` + `stochasticGradientDescent` + `assign`, fp32,
///     an OS framework, zero third-party deps). Physical hardware only; this is
///     the substrate that scales to the real per-capture batches (thousands of
///     octant pairs), and the one `contractDeviceGoldenUnrunOnHardware`
///     discharges. Metal-4 tensor fusion (B2) gates against the same bytes.
///
/// Concurrency: `DeviceTrainer` is NOT Sendable — confine an instance to one
/// queue/actor. `train` runs synchronously; each step blocks until the GPU
/// completes (the Atlas precedent measured 12.4 ms/step for a far larger graph).
enum DeviceTrainStepCPU {

    /// One supervision pair in device integers: the coarse value and the 7
    /// ground-truth detail bands the lift manufactured.
    struct Pair {
        let coarse: Int
        let detail: [Int]   // 7 bands
    }

    static let bands = 7
    static let featureCount = 3
    static let paramCount = bands * featureCount   // = DeviceTrainGolden.paramCount

    private static let q16 = 65536.0

    /// φ(v) = [1, ṽ, ṽ²] on the Q16-normalised coarse value (`DetailPredictor.features`).
    static func features(_ coarse: Int) -> [Double] {
        let v = Double(coarse) / q16
        return [1, v, v * v]
    }

    /// The Mac-side raw band readouts θⱼ·φ(v) (before the Q16 crossing).
    /// `theta` is flat row-major: θ₀ ++ θ₁ ++ … ++ θ₆ (7 rows × 3).
    static func rawBands(theta: [Double], coarse: Int) -> [Double] {
        let phi = features(coarse)
        return (0 ..< bands).map { j in
            (0 ..< featureCount).reduce(0) { acc, k in
                acc + theta[j * featureCount + k] * phi[k]
            }
        }
    }

    /// The single sanctioned float→device crossing:
    /// `quantizeQ16(raw) = round-half-to-even(raw · 65536)` (`ByteCarrier.reenterQ16`,
    /// the same idiom as `MaskedBandForward`).
    static func quantizeQ16(_ raw: Double) -> Int {
        Int((raw * q16).rounded(.toNearestOrEven))
    }

    /// The committed detail bands f_θ(v) — `rawBands` re-entered to Q16.
    /// Zero θ commits to the all-zero floor by arithmetic (no sentinel).
    static func predictCommitted(theta: [Double], coarse: Int) -> [Int] {
        rawBands(theta: theta, coarse: coarse).map(quantizeQ16)
    }

    /// Mean-gradient full-batch GD from the zero-param floor — the line-for-line
    /// twin of `Spec.DeviceTrainStep.trainDevice` (η = `DeviceTrainGolden.eta`,
    /// batch-size-independent step). Targets are Q16-normalised inside.
    static func trainDevice(steps: Int, eta: Double, pairs: [Pair]) -> [Double] {
        var theta = [Double](repeating: 0, count: paramCount)
        guard !pairs.isEmpty, steps > 0 else { return theta }
        let m = Double(pairs.count)
        for _ in 0 ..< steps {
            var grad = [Double](repeating: 0, count: paramCount)
            for pair in pairs {
                let phi = features(pair.coarse)
                let raws = rawBands(theta: theta, coarse: pair.coarse)
                for j in 0 ..< bands {
                    let err = raws[j] - Double(pair.detail[j]) / q16
                    for k in 0 ..< featureCount {
                        grad[j * featureCount + k] += err * phi[k]
                    }
                }
            }
            for i in 0 ..< paramCount {
                theta[i] -= eta * grad[i] / m
            }
        }
        return theta
    }

    /// The supervised loss (½ Σ squared raw-vs-target error, summed over pairs) —
    /// `Spec.DeviceTrainStep.deviceLossSum`, for trajectory telemetry.
    static func lossSum(theta: [Double], pairs: [Pair]) -> Double {
        pairs.reduce(0) { acc, pair in
            let raws = rawBands(theta: theta, coarse: pair.coarse)
            let e = (0 ..< bands).reduce(0.0) { s, j in
                let d = raws[j] - Double(pair.detail[j]) / q16
                return s + d * d
            }
            return acc + 0.5 * e
        }
    }
}

/// The MPSGraph on-device trainer for `f_θ` (see the header above). Built for a
/// FIXED batch size (MPSGraph is static-shape); per-capture batches build one
/// trainer for the capture's pair count.
final class DeviceTrainer {

    /// Whether this process can run the training graph at all. The simulator is
    /// excluded at compile time (measured: MPSGraph BUILDS there, but wrapping
    /// the simulator GPU for execution raises an uncatchable
    /// NSInvalidArgumentException inside MPSGraphDevice — see the AtlasTrainer
    /// spike note; `MPSSupportsMTLDevice` is not a sufficient gate).
    static var isSupported: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        return MPSSupportsMTLDevice(device)
        #endif
    }

    let batch: Int
    let eta: Float

    private let graph: MPSGraph
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let phiPlaceholder: MPSGraphTensor
    private let targetPlaceholder: MPSGraphTensor
    private let lossTensor: MPSGraphTensor
    private let thetaVariable: MPSGraphTensor   // [3,7] = θᵀ (matmul-friendly)
    private let updateOps: [MPSGraphOperation]

    /// Fails (nil) when MPSGraph cannot execute here — callers treat the trainer
    /// as an optional capability (the failable-hook house pattern).
    init?(batch: Int, eta: Float = Float(DeviceTrainGolden.eta)) {
        guard batch > 0, Self.isSupported,
              let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.batch = batch
        self.eta = eta
        self.device = device
        self.commandQueue = queue

        let graph = MPSGraph()
        self.graph = graph
        let bands = DeviceTrainStepCPU.bands
        let feats = DeviceTrainStepCPU.featureCount

        // Feeds: φ rows [N,3] and Q16-normalised targets [N,7].
        let phiPH = graph.placeholder(
            shape: [NSNumber(value: batch), NSNumber(value: feats)],
            dataType: .float32, name: "phi")
        let tgtPH = graph.placeholder(
            shape: [NSNumber(value: batch), NSNumber(value: bands)],
            dataType: .float32, name: "target")
        self.phiPlaceholder = phiPH
        self.targetPlaceholder = tgtPH

        // θᵀ [3,7], ZERO-initialised: the descent starts AT the floor
        // (zero-genome == floor), deterministic across devices — no PRNG.
        let zeroTheta = Data(count: feats * bands * MemoryLayout<Float>.size)
        let thetaT = graph.variable(
            with: zeroTheta,
            shape: [NSNumber(value: feats), NSNumber(value: bands)],
            dataType: .float32, name: "thetaT")
        self.thetaVariable = thetaT

        // raw [N,7] = φ [N,3] × θᵀ [3,7]; loss = mean over pairs of ½‖raw − t̃‖²
        // (mean over axis 0 ONLY — the mean-gradient contract; never over bands).
        let raw = graph.matrixMultiplication(primary: phiPH, secondary: thetaT, name: nil)
        let err = graph.subtraction(raw, tgtPH, name: nil)
        let sq = graph.multiplication(err, err, name: nil)
        let perPair = graph.reductionSum(with: sq, axes: [1], name: nil)      // [N,1]
        let half = graph.constant(0.5, dataType: .float32)
        let loss = graph.multiplication(
            half, graph.mean(of: perPair, axes: [0], name: nil), name: "bandLoss")
        self.lossTensor = loss

        // Backward + SGD assign (the Apple sample / AtlasTrainer pattern).
        let grads = graph.gradients(of: loss, with: [thetaT], name: nil)
        let lr = graph.constant(Double(eta), dataType: .float32)
        var ops: [MPSGraphOperation] = []
        if let g = grads[thetaT] {
            let updated = graph.stochasticGradientDescent(
                learningRate: lr, values: thetaT, gradient: g, name: nil)
            ops.append(graph.assign(thetaT, tensor: updated, name: nil))
        }
        self.updateOps = ops
    }

    /// Run `steps` full-batch SGD steps on the pairs (feeds uploaded once).
    /// Returns the per-step loss series. `pairs.count` must equal `batch`.
    @discardableResult
    func train(pairs: [DeviceTrainStepCPU.Pair], steps: Int) -> [Float] {
        precondition(pairs.count == batch, "pairs: \(pairs.count) != batch \(batch)")
        let bands = DeviceTrainStepCPU.bands
        let feats = DeviceTrainStepCPU.featureCount

        var phi = [Float](); phi.reserveCapacity(batch * feats)
        var tgt = [Float](); tgt.reserveCapacity(batch * bands)
        for pair in pairs {
            phi.append(contentsOf: DeviceTrainStepCPU.features(pair.coarse).map(Float.init))
            tgt.append(contentsOf: pair.detail.map { Float($0) / 65536.0 })
        }
        let feeds: [MPSGraphTensor: MPSGraphTensorData] = [
            phiPlaceholder: tensorData(phi, shape: [NSNumber(value: batch), NSNumber(value: feats)]),
            targetPlaceholder: tensorData(tgt, shape: [NSNumber(value: batch), NSNumber(value: bands)]),
        ]

        var losses = [Float]()
        losses.reserveCapacity(steps)
        for _ in 0 ..< steps {
            let results = graph.run(
                with: commandQueue, feeds: feeds,
                targetTensors: [lossTensor], targetOperations: updateOps)
            var loss = Float.nan
            results[lossTensor]?.mpsndarray().readBytes(&loss, strideBytes: nil)
            losses.append(loss)
        }
        return losses
    }

    /// Read the CURRENT θ back from the live variable, in the spec's flat
    /// row-major layout (θ₀ ++ … ++ θ₆, 7 rows × 3) as Doubles for the commit.
    func readTheta() -> [Double] {
        let bands = DeviceTrainStepCPU.bands
        let feats = DeviceTrainStepCPU.featureCount
        let results = graph.run(
            with: commandQueue, feeds: [:],
            targetTensors: [thetaVariable], targetOperations: nil)
        var thetaT = [Float](repeating: .nan, count: feats * bands)
        results[thetaVariable]?.mpsndarray().readBytes(&thetaT, strideBytes: nil)
        var theta = [Double](repeating: 0, count: feats * bands)
        for j in 0 ..< bands {
            for k in 0 ..< feats {
                theta[j * feats + k] = Double(thetaT[k * bands + j])
            }
        }
        return theta
    }

    // MPSNDArray-backed feeds (the AtlasTrainer note: the MPSGraphDevice wrapper
    // path raises on the simulator GPU; MPSNDArray sidesteps it).
    private func tensorData(_ values: [Float], shape: [NSNumber]) -> MPSGraphTensorData {
        let descriptor = MPSNDArrayDescriptor(dataType: .float32, shape: shape)
        let array = MPSNDArray(device: device, descriptor: descriptor)
        values.withUnsafeBufferPointer { ptr in
            array.writeBytes(UnsafeMutableRawPointer(mutating: ptr.baseAddress!),
                             strideBytes: nil)
        }
        return MPSGraphTensorData(array)
    }
}

/// The B1 discharge harness: run the `DeviceTrainGolden` fixture end-to-end on
/// THIS process and byte-compare every stage. Call it from a test (CPU + lift
/// stages run anywhere) or on the physical device (the graph stage — the
/// `contractDeviceGoldenUnrunOnHardware` obligation).
enum DeviceTrainGoldenCheck {

    struct Report {
        /// The native lift manufactured exactly (coarse, targetDetail) from fineBlock.
        let pairManufactureOK: Bool
        /// The hand-written CPU twin's committed bands == DeviceTrainGolden.committed.
        let cpuCommittedOK: Bool
        /// The MPSGraph trainer's committed bands == DeviceTrainGolden.committed
        /// (nil where MPSGraph cannot execute — simulator / no device).
        let graphCommittedOK: Bool?
        /// The graph's committed bands, for the failure log.
        let graphCommitted: [Int]?

        var allAvailableOK: Bool {
            pairManufactureOK && cpuCommittedOK && (graphCommittedOK ?? true)
        }
    }

    /// The golden pair, manufactured (never assumed) from `DeviceTrainGolden.fineBlock`
    /// via the byte-exact native lift. Returns nil if the lift refuses.
    static func manufacturedPair() -> DeviceTrainStepCPU.Pair? {
        let block = DeviceTrainGolden.fineBlock.map(Int32.init)
        guard let lifted = SixFourNative.octantLift(block: block) else { return nil }
        return DeviceTrainStepCPU.Pair(
            coarse: Int(lifted[0]), detail: lifted[1...].map(Int.init))
    }

    static func run() -> Report {
        // 1. Manufacture the pair on-device; it must equal the emitted contract.
        let pair = manufacturedPair()
        let pairOK = pair.map {
            $0.coarse == DeviceTrainGolden.coarse && $0.detail == DeviceTrainGolden.targetDetail
        } ?? false
        let goldenPair = pair ?? DeviceTrainStepCPU.Pair(
            coarse: DeviceTrainGolden.coarse, detail: DeviceTrainGolden.targetDetail)

        // 2. The hand-written CPU twin (runs everywhere).
        let cpuTheta = DeviceTrainStepCPU.trainDevice(
            steps: DeviceTrainGolden.steps, eta: DeviceTrainGolden.eta, pairs: [goldenPair])
        let cpuOK = DeviceTrainStepCPU.predictCommitted(
            theta: cpuTheta, coarse: goldenPair.coarse) == DeviceTrainGolden.committed

        // 3. The MPSGraph trainer (physical hardware only).
        var graphOK: Bool?
        var graphBands: [Int]?
        if let trainer = DeviceTrainer(batch: 1) {
            trainer.train(pairs: [goldenPair], steps: DeviceTrainGolden.steps)
            let bands = DeviceTrainStepCPU.predictCommitted(
                theta: trainer.readTheta(), coarse: goldenPair.coarse)
            graphBands = bands
            graphOK = bands == DeviceTrainGolden.committed
        }

        return Report(pairManufactureOK: pairOK, cpuCommittedOK: cpuOK,
                      graphCommittedOK: graphOK, graphCommitted: graphBands)
    }
}
