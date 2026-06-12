import Foundation
import Observation
import simd

/// COLOR ATLAS — the on-device training session (the VISIBLE flywheel,
/// docs/COLOR-ATLAS.md §1: every user decision is a logged, replayable training
/// example; this object makes the loop's turning observable in the cell-grid UI).
///
/// Architecture (Swift 6 strict concurrency):
///
///   MainActor: this @Observable session — published telemetry snapshots,
///     running/sweeping flags, V(A)/V(B) readouts. The UI reads ONLY this.
///        │  Sendable [Float] batches down · Sendable Step records up
///        ▼
///   AtlasTrainerWorker (a dedicated actor): owns the NON-Sendable AtlasTrainer
///     (MPSGraph is confined to this one executor for its whole life — built,
///     trained, and evaluated there, never escaping).
///
/// Training data (the flywheel rule, honest about its tier):
///   * ≥ `minimumLogPairs` Compare records in the user's real decision log ⇒
///     train on THOSE pairs (`.decisionLog`). Genomes: the current candidates'
///     hashes resolve to real leaf embeddings; older hashes (whose leaves the
///     log does not store) expand to deterministic hash-seeded pseudo-genomes —
///     a stable identity embedding, so the net learns the user's recorded
///     preference ORDER even where palette content is gone.
///   * otherwise ⇒ clearly-labeled synthetic pairs (`.synthetic`), the exact
///     deterministic xorshift teacher of AtlasTrainerTests (a fixed 384-D taste
///     direction θ*; winner = larger ⟨θ*, g⟩), so the widget demonstrates the
///     loop before the user has played 8 Compares.
///
/// Simulator: `AtlasTrainer.isSupported` is compile-time false there; `start`
/// guards on it and NEVER constructs the trainer — the widget renders the inert
/// labeled state instead (no MPSGraph call ever happens off-device).
@MainActor
@Observable
final class AtlasTrainingSession {

    // MARK: Tuning constants

    /// Real Compare pairs needed before the log (not synthesis) feeds training.
    static let minimumLogPairs = 8
    /// Cap on log pairs per batch (feed memory: 128 × 24,576 × 4 B ≈ 12.6 MB).
    static let maxLogPairs = 128
    /// Synthetic-fallback batch size (small ⇒ fast steps, visible loss curve).
    static let syntheticPairs = 32
    /// SGD steps per worker hop — the UI's refresh granularity (~12 ms/step on
    /// an A19 Pro ⇒ ~150 ms per chunk, a live-feeling cadence).
    static let stepsPerChunk = 12

    /// Whether this process can train at all (false on the simulator — the
    /// widget renders the inert state and the session never starts).
    static var isSupported: Bool { AtlasTrainer.isSupported }

    // MARK: What the trainer is learning from

    enum DataSource: Equatable, Sendable {
        /// No batch prepared yet.
        case none
        /// The user's real Compare records (count = pairs in the batch).
        case decisionLog(pairs: Int)
        /// Deterministic synthetic pairs — the log is still too small.
        case synthetic(pairs: Int)
    }

    // MARK: Published state (the widget's read surface)

    /// True while the training loop Task is live.
    private(set) var running = false
    /// True once the worker holds a built trainer (V readouts become meaningful).
    private(set) var prepared = false
    /// Ring buffer of step records — the sparkline's data, snapshot-copied here
    /// after every chunk (value type; one struct copy crosses the actor).
    private(set) var telemetry = AtlasTrainingTelemetry(capacity: 256)
    /// What the current batch was built from.
    private(set) var dataSource: DataSource = .none
    /// Trainable parameter count, once the graph is built (29,249 for the spike).
    private(set) var parameterCount: Int?
    /// V(candidateA) / V(candidateB) under the CURRENT weights — refreshed after
    /// every chunk (and once right after prepare, showing the untrained prior).
    private(set) var valueA: Float?
    private(set) var valueB: Float?
    /// STRETCH — the [16,16,16] value-sensitivity field (flat 4096, ΔV of
    /// toggling each bin's kill state), nil until a sweep completes.
    private(set) var saliency: [Float]?
    /// True while a saliency sweep is in flight.
    private(set) var sweeping = false

    /// Total SGD steps taken this session (survives ring-buffer wrap).
    var currentStep: Int { telemetry.totalRecorded }
    var latestLoss: Float? { telemetry.latest?.loss }
    var latestMsPerStep: Double? { telemetry.latest?.msPerStep }

    // MARK: Confined internals

    private let worker = AtlasTrainerWorker()
    private var trainTask: Task<Void, Never>?
    /// The current board tensor + candidate genomes, kept for V readouts/sweeps.
    private var evalBoard: [Float] = []
    private var genomeA: [Float] = []
    private var genomeB: [Float] = []

    // MARK: Start / stop

    /// Toggle the loop — the train/pause button's single entry point.
    func toggle(with atlas: AtlasState) {
        if running { stop() } else { start(with: atlas) }
    }

    /// Build the batch from the live atlas (real log if big enough, else
    /// synthetic), hand it to the worker, and run chunked SGD until `stop()`.
    /// Pausing and restarting with an UNCHANGED pair count resumes the same
    /// weights; a changed batch size rebuilds the graph (fresh deterministic init).
    func start(with atlas: AtlasState) {
        guard Self.isSupported, !running, trainTask == nil else { return }
        guard let batch = makeBatch(from: atlas) else { return }
        running = true

        trainTask = Task { [weak self, worker] in
            let params = await worker.prepare(batch)
            guard let self else { return }
            guard let params else {
                self.running = false
                self.trainTask = nil
                return
            }
            self.parameterCount = params
            self.prepared = true
            await self.refreshCandidateValues()

            var base = self.currentStep
            while !Task.isCancelled, self.running {
                let steps = await worker.run(steps: Self.stepsPerChunk, baseStep: base)
                guard !steps.isEmpty else { break }
                base += steps.count
                for s in steps { self.telemetry.record(s) }
                await self.refreshCandidateValues()
                await Task.yield()
            }
            self.running = false
            self.trainTask = nil
        }
    }

    /// Pause after the in-flight chunk; weights stay live on the worker.
    func stop() {
        running = false
        trainTask?.cancel()
    }

    // MARK: V(A) / V(B)

    /// Re-read both candidates' value under the current weights (one batch-2
    /// forward pass; no training side effects).
    private func refreshCandidateValues() async {
        guard prepared, !evalBoard.isEmpty, !genomeA.isEmpty, !genomeB.isEmpty else { return }
        let values = await worker.evaluate(
            boards: evalBoard + evalBoard, genomes: genomeA + genomeB, count: 2)
        if let values, values.count == 2 {
            valueA = values[0]
            valueB = values[1]
        }
    }

    // MARK: Saliency sweep (STRETCH)

    /// Compute the [16,16,16] value-sensitivity field: for each of the 4096
    /// bins, ΔV of toggling its kill state (ch4 — exactly what a ToggleBin move
    /// edits), batched through the forward-only graph in 256-variant chunks.
    /// Uses the picked Compare winner's genome (candidate A before any pick).
    func sweep(with atlas: AtlasState) {
        guard Self.isSupported, prepared, !sweeping, !evalBoard.isEmpty else { return }
        let genome = atlas.pickedHash == AtlasState.fnv1a32(atlas.candidateB)
            ? genomeB : genomeA
        guard !genome.isEmpty else { return }
        sweeping = true
        let board = evalBoard
        Task { [weak self, worker] in
            let field = await worker.saliency(board: board, genome: genome)
            guard let self else { return }
            if let field { self.saliency = field }
            self.sweeping = false
        }
    }

    // MARK: Batch construction (MainActor — reads AtlasState, emits Sendable)

    private func makeBatch(from atlas: AtlasState) -> AtlasTrainerWorker.Batch? {
        // The shared eval inputs (board + candidate genomes) refresh on every start.
        evalBoard = Self.boardTensor(atlas.board)
        genomeA = Self.genome(fromLeavesQ16: atlas.candidateA)
        genomeB = Self.genome(fromLeavesQ16: atlas.candidateB)
        guard !genomeA.isEmpty, !genomeB.isEmpty else { return nil }

        let compares = atlas.log.entries.filter { $0.tag == 3 }.suffix(Self.maxLogPairs)
        if compares.count >= Self.minimumLogPairs {
            // Real data: the user's recorded picks. Current candidates' hashes
            // resolve to their true leaf embeddings; unknown (older) hashes get
            // stable hash-seeded pseudo-genomes (identity embeddings).
            var genomeByHash: [UInt32: [Float]] = [
                AtlasState.fnv1a32(atlas.candidateA): genomeA,
                AtlasState.fnv1a32(atlas.candidateB): genomeB,
            ]
            func genome(for hash: UInt32) -> [Float] {
                if let known = genomeByHash[hash] { return known }
                let g = Self.pseudoGenome(hash: hash)
                genomeByHash[hash] = g
                return g
            }
            var boards = [Float]()
            boards.reserveCapacity(compares.count * AtlasTrainer.boardElementCount)
            var winners = [Float]()
            winners.reserveCapacity(compares.count * AtlasTrainer.genomeDim)
            var losers = [Float]()
            losers.reserveCapacity(compares.count * AtlasTrainer.genomeDim)
            for record in compares {
                boards.append(contentsOf: evalBoard)   // Compare is state-identity
                winners.append(contentsOf: genome(for: record.winHash))
                losers.append(contentsOf: genome(for: record.loseHash))
            }
            dataSource = .decisionLog(pairs: compares.count)
            return .init(boards: boards, winners: winners, losers: losers,
                         pairs: compares.count)
        }

        // Synthetic fallback — the AtlasTrainerTests teacher, batch-sized down.
        let synth = Self.syntheticBatch(pairs: Self.syntheticPairs,
                                        seed: 0x5158_4F52_3634_4C41)
        dataSource = .synthetic(pairs: Self.syntheticPairs)
        return synth
    }

    // MARK: Deterministic encoders (static, Sendable-out, unit-testable)

    /// AtlasBoard16 → the trainer's [4096,6] row-major (bin × channel) feed.
    static func boardTensor(_ board: AtlasBoard16) -> [Float] {
        let bins = AtlasBoard16.binCount
        let ch = AtlasTrainer.boardChannels
        var out = [Float](repeating: 0, count: bins * ch)
        for i in 0 ..< bins {
            let o = i * ch
            out[o + 0] = board.binMassPalettes[i]
            out[o + 1] = board.binMassPixels[i]
            out[o + 2] = board.globalCoverage[i]
            out[o + 3] = board.weightField[i]
            out[o + 4] = board.killMask[i]
            out[o + 5] = board.anchorMask[i]
        }
        return out
    }

    /// 256 σ-paired Q16 leaves → a 384-float genome stand-in: the 128
    /// even-index generators × 3 OKLab floats (the σ-pair generator view of
    /// docs/COLOR-ATLAS.md §4.0 — 384 = `SixFourNetIO.lookSigmaPairDOF`).
    /// Empty leaves ⇒ empty (the caller treats the candidate as absent).
    static func genome(fromLeavesQ16 leaves: [SIMD3<Int32>]) -> [Float] {
        guard !leaves.isEmpty else { return [] }
        let dim = AtlasTrainer.genomeDim          // 384
        let generators = dim / 3                  // 128
        var g = [Float](repeating: 0, count: dim)
        for i in 0 ..< generators {
            let leaf = leaves[min(2 * i, leaves.count - 1)]
            g[3 * i + 0] = Float(leaf.x) / 65536
            g[3 * i + 1] = Float(leaf.y) / 65536
            g[3 * i + 2] = Float(leaf.z) / 65536
        }
        return g
    }

    /// A stable 384-float identity embedding for a candidate hash whose leaves
    /// are no longer recoverable (older log entries) — deterministic xorshift64
    /// expansion, so the same hash always maps to the same point.
    static func pseudoGenome(hash: UInt32) -> [Float] {
        var prng = Xorshift64(seed: 0x6861_7368 &+ (UInt64(hash) &* 0x9E37_79B9_7F4A_7C15))
        return (0 ..< AtlasTrainer.genomeDim).map { _ in prng.symmetric(0.5) }
    }

    /// The deterministic synthetic teacher (the AtlasTrainerTests pattern): a
    /// fixed 384-D taste direction θ*; of each random genome pair the winner is
    /// the one with the larger ⟨θ*, g⟩; boards are sparse random curation states.
    static func syntheticBatch(pairs: Int, seed: UInt64) -> AtlasTrainerWorker.Batch {
        var prng = Xorshift64(seed: seed)
        let gDim = AtlasTrainer.genomeDim
        let taste = (0 ..< gDim).map { _ in prng.symmetric(1) }

        var boards = [Float]()
        boards.reserveCapacity(pairs * AtlasTrainer.boardElementCount)
        var winners = [Float]()
        winners.reserveCapacity(pairs * gDim)
        var losers = [Float]()
        losers.reserveCapacity(pairs * gDim)

        for _ in 0 ..< pairs {
            var board = [Float](repeating: 0, count: AtlasTrainer.boardElementCount)
            for _ in 0 ..< 256 {
                let bin = Int(prng.next() % UInt64(AtlasTrainer.boardBins))
                let channel = Int(prng.next() % UInt64(AtlasTrainer.boardChannels))
                board[bin * AtlasTrainer.boardChannels + channel] = prng.uniform()
            }
            boards.append(contentsOf: board)

            let gA = (0 ..< gDim).map { _ in prng.symmetric(0.5) }
            let gB = (0 ..< gDim).map { _ in prng.symmetric(0.5) }
            let scoreA = zip(taste, gA).reduce(Float(0)) { $0 + $1.0 * $1.1 }
            let scoreB = zip(taste, gB).reduce(Float(0)) { $0 + $1.0 * $1.1 }
            winners.append(contentsOf: scoreA >= scoreB ? gA : gB)
            losers.append(contentsOf: scoreA >= scoreB ? gB : gA)
        }
        return .init(boards: boards, winners: winners, losers: losers, pairs: pairs)
    }
}

// MARK: - The confined worker

/// The ONE executor the non-Sendable `AtlasTrainer` (MPSGraph) lives on. Every
/// method takes and returns only Sendable values; the trainer never escapes.
/// `train` blocks this actor's thread for ~`stepsPerChunk` GPU-synchronous steps
/// per hop (~150 ms) — acceptable for the debug-gated instrument; a custom
/// executor / BGProcessingTask worker is the production follow-up.
actor AtlasTrainerWorker {

    /// One full-batch training feed (all Sendable flats).
    struct Batch: Sendable {
        var boards: [Float]
        var winners: [Float]
        var losers: [Float]
        var pairs: Int
    }

    private var trainer: AtlasTrainer?
    private var batch: Batch?

    /// Build (or keep) the trainer for this batch size and stage the feed.
    /// Returns the graph's parameter count, or nil when unsupported here
    /// (simulator / no MPS device) — the failable-hook house pattern.
    func prepare(_ batch: Batch) -> Int? {
        guard AtlasTrainer.isSupported else { return nil }
        if trainer == nil || trainer?.config.pairsPerBatch != batch.pairs {
            trainer = AtlasTrainer(config: .init(pairsPerBatch: batch.pairs))
        }
        self.batch = batch
        return trainer?.parameterCount
    }

    /// Run one chunk of SGD steps; step indices are re-based so the session's
    /// counter keeps climbing across chunks.
    func run(steps: Int, baseStep: Int) -> [AtlasTrainingTelemetry.Step] {
        guard let trainer, let batch, steps > 0 else { return [] }
        var out = [AtlasTrainingTelemetry.Step]()
        out.reserveCapacity(steps)
        trainer.train(
            boards: batch.boards,
            winnerGenomes: batch.winners,
            loserGenomes: batch.losers,
            steps: steps
        ) { s in
            out.append(.init(step: baseStep + s.step, loss: s.loss, msPerStep: s.msPerStep))
        }
        return out
    }

    /// Forward-only V for `count` (board, genome) samples under current weights.
    func evaluate(boards: [Float], genomes: [Float], count: Int) -> [Float]? {
        trainer?.evaluate(boards: boards, genomes: genomes, count: count)
    }

    /// STRETCH — the value-sensitivity sweep: V of the base board, then 4096
    /// variants (each toggling one bin's ch4 kill state — the ToggleBin edit)
    /// in 256-variant batched forward passes. Returns the flat ΔV field.
    func saliency(board: [Float], genome: [Float]) -> [Float]? {
        guard let trainer else { return nil }
        let bins = AtlasTrainer.boardBins
        let ch = AtlasTrainer.boardChannels
        guard board.count == bins * ch, genome.count == AtlasTrainer.genomeDim
        else { return nil }

        guard let baseV = trainer.evaluate(boards: board, genomes: genome, count: 1).first,
              baseV.isFinite else { return nil }

        let chunk = 256
        var delta = [Float](repeating: 0, count: bins)
        var start = 0
        while start < bins {
            let n = min(chunk, bins - start)
            var boards = [Float]()
            boards.reserveCapacity(n * bins * ch)
            var genomes = [Float]()
            genomes.reserveCapacity(n * genome.count)
            for i in 0 ..< n {
                var variant = board
                let idx = (start + i) * ch + 4              // ch4 — killMask
                variant[idx] = variant[idx] > 0.5 ? 0 : 1   // the ToggleBin flip
                boards.append(contentsOf: variant)
                genomes.append(contentsOf: genome)
            }
            let values = trainer.evaluate(boards: boards, genomes: genomes, count: n)
            for i in 0 ..< n { delta[start + i] = values[i] - baseV }
            start += n
        }
        return delta
    }
}
