import Testing
import Foundation
@testable import SixFour

/// MPSGraph on-device training SPIKE test (docs/ON-DEVICE-TRAINING.md Answer 1).
///
/// Proves the backward pass: ~100 synthetic Compare pairs (deterministic
/// xorshift64 synthesis — no Date/random nondeterminism), full-batch SGD via
/// `AtlasTrainer`'s MPSGraph `gradients(of:with:)` + `stochasticGradientDescent`
/// + `assign` graph, asserting the Bradley–Terry loss at least halves over the
/// run. Also measures ms/step into the test log via `AtlasTrainingTelemetry`.
///
/// The synthetic "taste": a fixed 384-D direction θ*; of each random genome
/// pair the winner is the one with the larger ⟨θ*, g⟩ — a linear teacher the
/// genome-encoder pathway can rank. Boards are random per pair and shared by
/// both sides (Compare is state-identity, docs/COLOR-ATLAS.md §3.1).
///
/// Gated on `AtlasTrainer.isSupported`: if this simulator/host has no
/// MPS-capable Metal device the test is skipped (disabled), and the spike's
/// numbers must come from a physical device run:
///   xcodebuild test -project SixFour.xcodeproj -scheme SixFour \
///     -destination 'platform=iOS,name=<iPhone 17 Pro>' \
///     -only-testing:SixFourTests/AtlasTrainerTests
struct AtlasTrainerTests {

    /// Synthesize `pairs` Compare examples, deterministically.
    private static func synthesize(
        pairs: Int, seed: UInt64
    ) -> (boards: [Float], winners: [Float], losers: [Float]) {
        var prng = Xorshift64(seed: seed)
        let gDim = AtlasTrainer.genomeDim

        // The fixed taste direction θ* the net must recover the ranking of.
        let taste = (0 ..< gDim).map { _ in prng.symmetric(1) }

        var boards = [Float]()
        boards.reserveCapacity(pairs * AtlasTrainer.boardElementCount)
        var winners = [Float]()
        winners.reserveCapacity(pairs * gDim)
        var losers = [Float]()
        losers.reserveCapacity(pairs * gDim)

        for _ in 0 ..< pairs {
            // Board: sparse random curation state — most bins empty, a few hot.
            var board = [Float](repeating: 0, count: AtlasTrainer.boardElementCount)
            for _ in 0 ..< 256 {
                let bin = Int(prng.next() % UInt64(AtlasTrainer.boardBins))
                let channel = Int(prng.next() % UInt64(AtlasTrainer.boardChannels))
                board[bin * AtlasTrainer.boardChannels + channel] = prng.uniform()
            }
            boards.append(contentsOf: board)

            // Two random genomes; winner = larger ⟨θ*, g⟩.
            let gA = (0 ..< gDim).map { _ in prng.symmetric(0.5) }
            let gB = (0 ..< gDim).map { _ in prng.symmetric(0.5) }
            let scoreA = zip(taste, gA).reduce(Float(0)) { $0 + $1.0 * $1.1 }
            let scoreB = zip(taste, gB).reduce(Float(0)) { $0 + $1.0 * $1.1 }
            winners.append(contentsOf: scoreA >= scoreB ? gA : gB)
            losers.append(contentsOf: scoreA >= scoreB ? gB : gA)
        }
        return (boards, winners, losers)
    }

    @Test(.enabled(if: AtlasTrainer.isSupported))
    func bradleyTerryLossHalvesOnSyntheticComparePairs() throws {
        let pairs = 100
        let steps = 300

        let data = Self.synthesize(pairs: pairs, seed: 0x5158_4F52_3634_4C41)
        let trainer = try #require(
            AtlasTrainer(config: .init(pairsPerBatch: pairs, learningRate: 0.25, seed: 42)),
            "isSupported was true but trainer init failed")

        var telemetry = AtlasTrainingTelemetry(capacity: steps)
        let losses = trainer.train(
            boards: data.boards,
            winnerGenomes: data.winners,
            loserGenomes: data.losers,
            steps: steps
        ) { telemetry.record($0) }

        #expect(losses.count == steps)
        #expect(telemetry.totalRecorded == steps)

        let series = telemetry.chronological
        let initial = try #require(series.first).loss
        let final = try #require(series.last).loss

        // The untrained net is a coin flip: loss ≈ ln 2. Sanity-check we
        // started near there (catches degenerate feeds), then require the
        // overfit halving the spike is about.
        #expect(initial.isFinite && final.isFinite)
        #expect(initial > 0.4, "initial BT loss \(initial) suspiciously low — degenerate synth?")
        #expect(final < 0.5 * initial,
                "BT loss failed to halve: \(initial) → \(final) after \(steps) steps")

        // The spike's headline numbers, into the test log.
        let totalMs = series.reduce(0.0) { $0 + $1.msPerStep }
        let avgMs = totalMs / Double(series.count)
        let tail = series.suffix(steps / 2)
        let steadyMs = tail.reduce(0.0) { $0 + $1.msPerStep } / Double(tail.count)
        print("""
        [AtlasTrainer spike] pairs=\(pairs) steps=\(steps) params=\(trainer.parameterCount)
        [AtlasTrainer spike] BT loss \(initial) → \(final) (\(String(format: "%.1f", 100 * final / initial))% of initial)
        [AtlasTrainer spike] ms/step avg=\(String(format: "%.2f", avgMs)) steady-state=\(String(format: "%.2f", steadyMs)) total=\(String(format: "%.0f", totalMs)) ms
        """)
    }

    /// The telemetry ring buffer's wrap behavior — capacity bounds, oldest-out,
    /// chronological order across the wrap point.
    @Test func telemetryRingBufferWraps() {
        var ring = AtlasTrainingTelemetry(capacity: 4)
        #expect(ring.latest == nil)
        #expect(ring.chronological.isEmpty)

        for i in 0 ..< 6 {
            ring.record(.init(step: i, loss: Float(i), msPerStep: 1))
        }
        #expect(ring.count == 4)
        #expect(ring.totalRecorded == 6)
        #expect(ring.latest?.step == 5)
        #expect(ring.chronological.map(\.step) == [2, 3, 4, 5])
    }
}
