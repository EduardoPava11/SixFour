import Foundation
import Metal
import MetalPerformanceShaders
import MetalPerformanceShadersGraph

/// COLOR ATLAS — on-device training SPIKE (docs/ON-DEVICE-TRAINING.md Answer 1).
///
/// Proves the verdict of the research report: the Atlas value path can train
/// on-device with MPSGraph alone (`gradients(of:with:)` reverse-mode autodiff +
/// `stochasticGradientDescent` + `assign` update ops — the official Apple
/// "Training a neural network using MPSGraph" sample pattern), zero third-party
/// dependencies (MetalPerformanceShadersGraph is an OS framework, iOS 14+).
///
/// The graph is the VALUE PATH of docs/COLOR-ATLAS.md §4.2, spike-simplified:
///
///   board [B,4096,6] ──(per-bin 6→64 linear, mean-pool over bins, tanh)──┐
///                                                                        ├─ ctx [B,128]
///   genome [B,384] ───(384→64 linear, tanh — the genome encoder)─────────┘
///                                                                        │
///   ctx ──(128→32 tanh ── 32→1)── V(board, genome)                       ▼
///
/// trained with the Bradley–Terry pairwise logistic loss on Compare pairs
/// (docs/COLOR-ATLAS.md §3.1 `Compare` — pure training signal):
///
///   loss = mean softplus(−(V(board, gWinner) − V(board, gLoser)))
///        = mean −log σ(V_w − V_l)
///
/// Honest deviations from the §4.2 production heads, acceptable for a backward-
/// pass + speed spike: no σ-masks on the stored weights, no σ-invariant 24-D
/// projection before the value MLP (ctx feeds it directly), and the board enters
/// through a per-bin linear + mean-pool instead of the φ′ token / L4 recursion
/// pathway. Shapes and FLOPs are representative (the [B·4096,6]×[6,64] matmul
/// stands in for the ≤4096-token φ′ matmul); the policy heads (node 127 +
/// delta 12 + BC cross-entropy) are follow-up work once this spike's numbers
/// hold on hardware.
///
/// fp32 weights throughout (the report's recommendation). Deterministic init
/// (xorshift64 from `Config.seed`) so test runs are replayable.
///
/// Concurrency: NOT Sendable — confine an instance to one queue/actor (the
/// future BGProcessingTask worker). `train` runs synchronously on the calling
/// thread; MPSGraph `run` blocks until the GPU completes each step.
final class AtlasTrainer {

    // MARK: Pinned dimensions (docs/COLOR-ATLAS.md §2 tensor table)

    /// 16³ board bins (`AtlasBoard16.binCount`).
    static var boardBins: Int { AtlasBoard16.binCount }
    /// Board channels ch0–ch5.
    static let boardChannels = 6
    /// σ-pair genome DOF — the generated contract's 384, never a free literal.
    static var genomeDim: Int { SixFourNetIO.lookSigmaPairDOF }
    /// Hidden model width (mirrors the LookNet MODEL_DIM = 64).
    static let modelDim = 64
    /// Fused context = board ‖ genome encodings.
    static var ctxDim: Int { 2 * modelDim }
    /// Value MLP hidden width (§4.2 value head's 32).
    static let valueHiddenDim = 32

    /// Floats per board sample (`boardBins × boardChannels` = 24,576).
    static var boardElementCount: Int { boardBins * boardChannels }

    // MARK: Config

    struct Config: Sendable {
        /// Compare pairs per training step (the graph is built for this fixed
        /// batch — full-batch overfit for the spike).
        var pairsPerBatch: Int = 100
        /// Plain SGD learning rate (the MPSGraph `stochasticGradientDescent` op).
        var learningRate: Float = 0.25
        /// Deterministic weight-init seed (xorshift64).
        var seed: UInt64 = 0x6174_6C61_7331_3238

        init(pairsPerBatch: Int = 100, learningRate: Float = 0.25,
             seed: UInt64 = 0x6174_6C61_7331_3238) {
            self.pairsPerBatch = pairsPerBatch
            self.learningRate = learningRate
            self.seed = seed
        }
    }

    /// Whether this process can run the training graph at all.
    ///
    /// The simulator is excluded at compile time, measured fact (Xcode 17E192 /
    /// iOS 26 simulator, 2026-06-10): MPSGraph BUILDS the full graph there —
    /// variables, `gradients(of:with:)`, SGD + assign ops all construct — but
    /// any attempt to wrap the simulator GPU for execution
    /// (`MPSGraphDevice(mtlDevice:)`, and `MPSGraphTensorData(MPSNDArray)`
    /// which calls `+[MPSGraphDevice deviceWithMTLDevice:]` internally) raises
    /// an uncatchable NSInvalidArgumentException:
    /// `-[__NSArrayM insertObject:atIndex:]: object cannot be nil` inside
    /// `-[MPSGraphDeviceDescriptor initWithMPSGraphDevice:]` — the simulator
    /// GPU has no MPSGraph device descriptor. `MPSSupportsMTLDevice` returns
    /// TRUE for that device, so it is not a sufficient gate. Training runs on
    /// physical hardware only.
    static var isSupported: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        return MPSSupportsMTLDevice(device)
        #endif
    }

    // MARK: State (confined — none of this is Sendable)

    let config: Config
    /// Total trainable parameters in the graph.
    let parameterCount: Int

    private let graph: MPSGraph
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let boardPlaceholder: MPSGraphTensor
    private let winnerPlaceholder: MPSGraphTensor
    private let loserPlaceholder: MPSGraphTensor
    private let lossTensor: MPSGraphTensor
    private let updateOps: [MPSGraphOperation]

    // MARK: Init — build the training graph once

    /// Fails (nil) when MPSGraph cannot execute here (no Metal/MPS device, or
    /// the simulator — see `isSupported`) — callers treat the trainer as an
    /// optional capability (the failable-hook house pattern).
    init?(config: Config = Config()) {
        guard Self.isSupported,
              let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.config = config
        self.device = device
        self.commandQueue = queue

        let graph = MPSGraph()
        self.graph = graph

        let b = config.pairsPerBatch
        let bins = Self.boardBins
        let ch = Self.boardChannels
        let gDim = Self.genomeDim
        let mDim = Self.modelDim
        let cDim = Self.ctxDim
        let hDim = Self.valueHiddenDim

        // ── Placeholders (fp32 feeds) ──────────────────────────────────────
        let boardPH = graph.placeholder(
            shape: [NSNumber(value: b), NSNumber(value: bins), NSNumber(value: ch)],
            dataType: .float32, name: "board")
        let winPH = graph.placeholder(
            shape: [NSNumber(value: b), NSNumber(value: gDim)],
            dataType: .float32, name: "genomeWinner")
        let losePH = graph.placeholder(
            shape: [NSNumber(value: b), NSNumber(value: gDim)],
            dataType: .float32, name: "genomeLoser")
        self.boardPlaceholder = boardPH
        self.winnerPlaceholder = winPH
        self.loserPlaceholder = losePH

        // ── Variables: deterministic Xavier-uniform init, zero biases ──────
        var prng = Xorshift64(seed: config.seed)
        func variable(_ rows: Int, _ cols: Int, _ name: String) -> MPSGraphTensor {
            let bound = (6.0 / Float(rows + cols)).squareRoot()
            var values = [Float](repeating: 0, count: rows * cols)
            for i in values.indices { values[i] = prng.symmetric(bound) }
            return values.withUnsafeBufferPointer { ptr in
                graph.variable(
                    with: Data(buffer: ptr),
                    shape: [NSNumber(value: rows), NSNumber(value: cols)],
                    dataType: .float32, name: name)
            }
        }
        func bias(_ cols: Int, _ name: String) -> MPSGraphTensor {
            let values = [Float](repeating: 0, count: cols)
            return values.withUnsafeBufferPointer { ptr in
                graph.variable(
                    with: Data(buffer: ptr),
                    shape: [NSNumber(value: cols)],
                    dataType: .float32, name: name)
            }
        }

        let wBoard = variable(ch, mDim, "wBoard")     // per-bin 6→64
        let bBoard = bias(mDim, "bBoard")
        let wGenome = variable(gDim, mDim, "wGenome") // genome encoder 384→64
        let bGenome = bias(mDim, "bGenome")
        let w1 = variable(cDim, hDim, "wValue1")      // value MLP 128→32
        let b1 = bias(hDim, "bValue1")
        let w2 = variable(hDim, 1, "wValue2")         // value MLP 32→1
        let b2 = bias(1, "bValue2")
        let variables = [wBoard, bBoard, wGenome, bGenome, w1, b1, w2, b2]
        self.parameterCount =
            ch * mDim + mDim + gDim * mDim + mDim + cDim * hDim + hDim + hDim + 1

        // ── Shared board encoding (one board per pair, both branches) ──────
        // [B,4096,6] → [B·4096,6] × [6,64] → [B,4096,64] → mean over bins →
        // [B,64] → +bias → tanh.
        let boardFlat = graph.reshape(
            boardPH, shape: [NSNumber(value: b * bins), NSNumber(value: ch)], name: nil)
        let boardProj = graph.matrixMultiplication(
            primary: boardFlat, secondary: wBoard, name: nil)
        let boardCube = graph.reshape(
            boardProj,
            shape: [NSNumber(value: b), NSNumber(value: bins), NSNumber(value: mDim)],
            name: nil)
        let boardPooled = graph.reshape(
            graph.mean(of: boardCube, axes: [1], name: nil),
            shape: [NSNumber(value: b), NSNumber(value: mDim)], name: nil)
        let boardCtx = graph.tanh(
            with: graph.addition(boardPooled, bBoard, name: nil), name: nil)

        // ── V(board, genome): shared weights across winner/loser branches ──
        func value(of genome: MPSGraphTensor) -> MPSGraphTensor {
            let enc = graph.tanh(
                with: graph.addition(
                    graph.matrixMultiplication(primary: genome, secondary: wGenome, name: nil),
                    bGenome, name: nil),
                name: nil)
            let ctx = graph.concatTensors([boardCtx, enc], dimension: 1, name: nil)
            let h = graph.tanh(
                with: graph.addition(
                    graph.matrixMultiplication(primary: ctx, secondary: w1, name: nil),
                    b1, name: nil),
                name: nil)
            return graph.addition(
                graph.matrixMultiplication(primary: h, secondary: w2, name: nil),
                b2, name: nil)                                       // [B,1]
        }

        // ── Bradley–Terry loss: mean softplus(−(V_w − V_l)) ────────────────
        // Numerically stable softplus(x) = max(x,0) + log1p(exp(−|x|)).
        let margin = graph.subtraction(value(of: winPH), value(of: losePH), name: nil)
        let x = graph.negative(with: margin, name: nil)
        let zero = graph.constant(0, dataType: .float32)
        let one = graph.constant(1, dataType: .float32)
        let softplus = graph.addition(
            graph.maximum(x, zero, name: nil),
            graph.logarithm(
                with: graph.addition(
                    one,
                    graph.exponent(
                        with: graph.negative(with: graph.absolute(with: x, name: nil), name: nil),
                        name: nil),
                    name: nil),
                name: nil),
            name: nil)
        let loss = graph.mean(of: softplus, axes: [0, 1], name: "btLoss")
        self.lossTensor = loss

        // ── Backward pass + SGD assign ops (the Apple sample pattern) ──────
        let grads = graph.gradients(of: loss, with: variables, name: nil)
        let lr = graph.constant(Double(config.learningRate), dataType: .float32)
        var ops: [MPSGraphOperation] = []
        for v in variables {
            guard let g = grads[v] else { continue }
            let updated = graph.stochasticGradientDescent(
                learningRate: lr, values: v, gradient: g, name: nil)
            ops.append(graph.assign(v, tensor: updated, name: nil))
        }
        self.updateOps = ops
    }

    // MARK: Training

    /// Run `steps` full-batch SGD steps on one fixed batch of Compare pairs
    /// (the overfit spike). Feeds are uploaded once and reused, so `onStep`
    /// timing measures graph execution, not host marshalling.
    ///
    /// - `boards`: `pairsPerBatch × 24,576` floats — the [16,16,16,6] board of
    ///    each pair, row-major (`AtlasBinIdx.flat` × channel), shared by both
    ///    sides of its pair (Compare is state-identity).
    /// - `winnerGenomes`/`loserGenomes`: `pairsPerBatch × 384` floats each.
    /// - Returns the per-step loss series (also delivered via `onStep` as
    ///   telemetry records for the ring buffer / future cell-grid widget).
    @discardableResult
    func train(
        boards: [Float],
        winnerGenomes: [Float],
        loserGenomes: [Float],
        steps: Int,
        onStep: (AtlasTrainingTelemetry.Step) -> Void = { _ in }
    ) -> [Float] {
        let b = config.pairsPerBatch
        precondition(boards.count == b * Self.boardElementCount, "boards: \(boards.count)")
        precondition(winnerGenomes.count == b * Self.genomeDim, "winners: \(winnerGenomes.count)")
        precondition(loserGenomes.count == b * Self.genomeDim, "losers: \(loserGenomes.count)")

        // MPSNDArray-backed feeds: `MPSGraphTensorData(device:data:shape:dataType:)`
        // requires an MPSGraphDevice, and `MPSGraphDevice(mtlDevice:)` raises
        // NSInvalidArgumentException on the iOS-simulator GPU (its device
        // descriptor lookup returns nil) — MPSNDArray sidesteps that wrapper.
        func tensorData(_ values: [Float], shape: [NSNumber]) -> MPSGraphTensorData {
            let descriptor = MPSNDArrayDescriptor(dataType: .float32, shape: shape)
            let array = MPSNDArray(device: device, descriptor: descriptor)
            values.withUnsafeBufferPointer { ptr in
                array.writeBytes(UnsafeMutableRawPointer(mutating: ptr.baseAddress!),
                                 strideBytes: nil)
            }
            return MPSGraphTensorData(array)
        }
        let feeds: [MPSGraphTensor: MPSGraphTensorData] = [
            boardPlaceholder: tensorData(
                boards,
                shape: [NSNumber(value: b), NSNumber(value: Self.boardBins),
                        NSNumber(value: Self.boardChannels)]),
            winnerPlaceholder: tensorData(
                winnerGenomes,
                shape: [NSNumber(value: b), NSNumber(value: Self.genomeDim)]),
            loserPlaceholder: tensorData(
                loserGenomes,
                shape: [NSNumber(value: b), NSNumber(value: Self.genomeDim)]),
        ]

        var losses = [Float]()
        losses.reserveCapacity(steps)
        for step in 0 ..< steps {
            let t0 = DispatchTime.now().uptimeNanoseconds
            let results = graph.run(
                with: commandQueue, feeds: feeds,
                targetTensors: [lossTensor], targetOperations: updateOps)
            let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
            var loss = Float.nan
            results[lossTensor]?.mpsndarray().readBytes(&loss, strideBytes: nil)
            losses.append(loss)
            onStep(AtlasTrainingTelemetry.Step(step: step, loss: loss, msPerStep: ms))
        }
        return losses
    }
}

/// xorshift64 — the spike's deterministic PRNG (weight init). Zero seeds are
/// remapped (xorshift's sole fixed point).
struct Xorshift64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    /// Uniform in [0, 1) — 24 high-quality mantissa bits.
    mutating func uniform() -> Float {
        Float(next() >> 40) * (1.0 / 16_777_216.0)
    }

    /// Uniform in (−scale, scale).
    mutating func symmetric(_ scale: Float) -> Float {
        (uniform() * 2 - 1) * scale
    }
}
