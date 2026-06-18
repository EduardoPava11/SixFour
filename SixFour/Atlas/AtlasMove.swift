import Foundation
import simd

/// COLOR ATLAS — the curation Move ADT + the replay fold (docs/COLOR-ATLAS.md §3).
///
/// Swift mirror (UI-track stub) of the PLANNED spec module `SixFour.Spec.AtlasMove`.
/// ALL FOUR interaction modes are move types; every user decision is a logged,
/// replayable training example (the flywheel rule). The laws this stub honours by
/// construction (to be golden-pinned once the spec module lands):
///
///   * `lawToggleInvolutive`        — ToggleBin twice = identity.
///   * `lawWeightAdditiveCommutative` — WeightRegion deltas add.
///   * `lawPinIdempotent`           — PinAnchor twice = once.
///   * `lawCompareIdentity`         — Compare mutates NOTHING (pure training signal).
///   * `lawBaseChannelsUntouched`   — ch0–ch2 are never edited by a move.
///   * `lawReplayDeterminism`       — same log ⇒ bit-identical board (`boardFromLog`).
///   * totality                     — an out-of-range bin is identity.
enum CurationMove: Equatable, Sendable {
    /// Keep/kill a 16³ bin (involutive flip of ch4).
    case toggleBin(AtlasBinIdx)
    /// Boost/suppress a bin: signed i16 Q8.8 delta, additive/commutative on ch3.
    case weightRegion(AtlasBinIdx, Int16)
    /// The global palette MUST contain this colour (OKLab Q16); sets ch5 + anchorColors.
    case pinAnchor(AtlasBinIdx, SIMD3<Int32>)
    /// User picked between two candidate palettes — Bradley-Terry pairwise signal.
    /// State-identity; hashes identify the candidate genomes/palettes.
    case compare(winner: UInt32, loser: UInt32)
}

/// Apply one curation move to the board — TOTAL (out-of-range bin ⇒ identity),
/// pure, and touching ch3–ch5 + anchorColors only. Mirrors the planned
/// `applyCuration :: CurationMove -> Board16 -> Board16`.
func applyCuration(_ move: CurationMove, _ board: AtlasBoard16) -> AtlasBoard16 {
    var b = board
    switch move {
    case .toggleBin(let bin):
        guard bin.inRange else { return board }
        b.killMask[bin.flat] = b.killMask[bin.flat] > 0.5 ? 0 : 1
    case .weightRegion(let bin, let deltaQ88):
        guard bin.inRange else { return board }
        b.weightField[bin.flat] += Float(deltaQ88) / 256   // Q8.8 → float
    case .pinAnchor(let bin, let colorQ16):
        guard bin.inRange else { return board }
        b.anchorMask[bin.flat] = 1
        b.anchorColors[bin.flat] = colorQ16
    case .compare:
        return board   // lawCompareIdentity — pure training signal
    }
    return b
}

// MARK: - The replay record (the doc's DECN entry, as Codable)

/// One decision-log entry — the Codable twin of the SF64 container's fixed
/// 32-byte DECN record (docs/COLOR-ATLAS.md §3.3):
/// `tag u8 | bin x,y,z 3×u8 | wDelta i16 Q8.8 | flags u16 | anchor 3×i32 Q16 |
///  winHash u32 | loseHash u32 | pad u32 = 0`.
/// The binary SF64 encoder is the spec track's job; the app logs the SAME fields
/// as Codable JSON so the device log is replayable today and losslessly
/// transcodable to SF64 later. Unused fields are zero, `pad` is asserted zero on
/// decode (the explicit named-pad resolution).
struct AtlasDecisionRecord: Codable, Equatable, Sendable {
    /// Move tag: 0 = ToggleBin, 1 = WeightRegion, 2 = PinAnchor, 3 = Compare.
    var tag: UInt8
    /// Bin coordinates (l, a, b) — the DECN x,y,z bytes. Zero for Compare.
    var x: UInt8 = 0
    var y: UInt8 = 0
    var z: UInt8 = 0
    /// WeightRegion delta, i16 Q8.8. Zero otherwise.
    var wDelta: Int16 = 0
    /// Reserved flags (forward-compat).
    var flags: UInt16 = 0
    /// PinAnchor colour, OKLab Q16. Zero otherwise.
    var anchorL: Int32 = 0
    var anchorA: Int32 = 0
    var anchorB: Int32 = 0
    /// Compare pair (candidate palette hashes). Zero otherwise.
    var winHash: UInt32 = 0
    var loseHash: UInt32 = 0
    /// Explicit pad — always zero (pinned in the SF64 sum check).
    var pad: UInt32 = 0

    /// The winner / loser 770-D `atlasEmbedding` frozen at pick time (Compare only) —
    /// the `PreferenceUpdate.btUpdate` input, stored so replay is self-contained (no
    /// genome-resolution dependency). The SF64 binary twin is the additive `CMPE`
    /// chunk (`Spec.DecisionLog`, version-stable). `nil` on non-Compare or pre-embedding
    /// records; Codable decodes old logs (missing keys) straight to `nil` — backward
    /// compatible, no version bump (debt step 2b: DECN v2 = embeddings).
    var winEmbedding: [Float]?
    var loseEmbedding: [Float]?

    /// Encode a move as a record (lossless for the four-move alphabet).
    init(_ move: CurationMove) {
        switch move {
        case .toggleBin(let bin):
            tag = 0
            (x, y, z) = (UInt8(clamping: bin.l), UInt8(clamping: bin.a), UInt8(clamping: bin.b))
        case .weightRegion(let bin, let delta):
            tag = 1
            (x, y, z) = (UInt8(clamping: bin.l), UInt8(clamping: bin.a), UInt8(clamping: bin.b))
            wDelta = delta
        case .pinAnchor(let bin, let color):
            tag = 2
            (x, y, z) = (UInt8(clamping: bin.l), UInt8(clamping: bin.a), UInt8(clamping: bin.b))
            (anchorL, anchorA, anchorB) = (color.x, color.y, color.z)
        case .compare(let winner, let loser):
            tag = 3
            winHash = winner
            loseHash = loser
        }
    }

    /// Decode back to the move — `nil` for an unknown tag (forward-compat skip)
    /// or a non-zero pad (corruption tripwire).
    var move: CurationMove? {
        guard pad == 0 else { return nil }
        let bin = AtlasBinIdx(l: Int(x), a: Int(y), b: Int(z))
        switch tag {
        case 0: return .toggleBin(bin)
        case 1: return .weightRegion(bin, wDelta)
        case 2: return .pinAnchor(bin, SIMD3<Int32>(anchorL, anchorA, anchorB))
        case 3: return .compare(winner: winHash, loser: loseHash)
        default: return nil   // unknown-tag forward-compat skip
        }
    }
}

/// THE replay-determinism fold: rebuild the curation channels by folding every
/// decoded record over the base board, in log order. Same log ⇒ bit-identical
/// board (mirrors the planned `boardFromLog`). Unknown tags are skipped.
func boardFromLog(base: AtlasBoard16, records: [AtlasDecisionRecord]) -> AtlasBoard16 {
    records.reduce(base) { board, record in
        guard let move = record.move else { return board }
        return applyCuration(move, board)
    }
}
