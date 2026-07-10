//  MergeBoard.swift
//  THE MERGE — the hand-written Swift twin of `Spec.MergeBoard`.
//
//  2048 inverted: the capture opens as the all-coarse 16-board (a 4×4
//  partition of the 64² plane at rung depths 0/1/2 = 16/32/64) and the player
//  DECOMPOSES coarse color into fine with the three verbs S/K/I, spending
//  signal that arrives ONLY by pouring the burst's own 4-frame slices. The
//  ordered record of every ACCEPTED op is the DECISION WORD — provably the
//  whole game state (`lawWordReplaysBoard`: refusals are total no-ops and
//  accepted ops append exactly themselves, so replaying a board's own word
//  from the initial board reproduces the board, every field).
//
//  THE CONSTANTS ARE LAWS, NOT TUNING (all pinned in the spec):
//  • pourCap × pourDeposit = 16 × 4 = 64 = windowUnits = threshold32
//    (`lawEconomyIsTheWindow` — the pours deliver exactly one 320 cs window,
//    and the 32↔64 phase gate demands exactly one window of banked
//    32-evidence).
//  • splitCost(d) = 2^d (`lawSplitCostIsSTower` — stacking another S doubles
//    the substrate references, `Spec.WeaveOrder.lawSTowerCostsExponential`).
//  • A pour credits `bank32` only where the board ALREADY measures at ≥ 32
//    (`lawBankNeedsMeasurement` — the all-coarse board banks ZERO; evidence
//    is measured, never derived). Banked evidence never un-banks: K
//    withdraws the fine CLAIM, not the measurement (`lawUnlockMonotone`).
//
//  THE WIRE: `decisionWordCodes` emits the `.s4cr` v3 `dw` op-codes
//  (`Spec.CaptureRecord.gameOpCode`: 0 = pour, 1 + 3·region + verb with
//  S/K/I = 0/1/2) for `S4CaptureRecord.decisionWord`. Parity with the spec
//  is gated by `MergeBoardTests`: the canonical tight construction
//  (12 pours / 48 spent / signal 0) and a 22-op golden trace covering every
//  refusal family, both pinned from the Haskell authority.
//
//  Pure integer value type, zero dependencies (not even Foundation).

/// The three verbs on a region — the twin of `Spec.MergeBoard.MoveOp`.
/// Raw values ARE the wire verb codes (`gameOpCode`'s `fromEnum`).
enum S4MergeVerb: Int, CaseIterable, Sendable {
    /// SPLIT — reveal one rung finer; costs `splitCost(fromDepth)` signal.
    case s = 0
    /// MERGE BACK — pool one rung coarser; K keeps: never pays, never refunds.
    case k = 1
    /// HOLD — the explicit free no-op.
    case i = 2
}

/// One game op — the twin of `Spec.MergeBoard.GameOp`.
enum S4MergeOp: Equatable, Sendable {
    /// Bank the next 4-frame slice of the burst (+4 signal, credits bank32).
    case pour
    /// Play a verb on a region (raster index 0..15).
    case move(Int, S4MergeVerb)
}

/// Why a move was refused — the twin of `Spec.MergeBoard.Reject`.
/// Refusals are TOTAL NO-OPS: nothing changes, nothing is recorded.
enum S4MergeReject: Equatable, Sendable {
    case offBoard        // region outside 0..15
    case alreadyFinest   // S on a depth-2 region: the ceiling is honest
    case alreadyCoarsest // K on a depth-0 region
    case phaseLocked     // S from depth 1 before the window is banked
    case noSignal        // S without splitCost banked
    case poursExhausted  // pour past pourCap: the burst has no more slices
}

/// A move either happens (and is recorded) or is refused (and nothing
/// changes) — the twin of `Spec.MergeBoard.Verdict`.
enum S4MergeVerdict: Equatable, Sendable {
    case accept
    case rejected(S4MergeReject)
}

/// The whole game state — the twin of `Spec.MergeBoard.Board`.
struct S4MergeBoard: Equatable, Sendable {
    // MARK: Constants (pinned by the spec's law suite)

    /// Regions per side: the board is 4×4.
    static let boardSide = 4
    /// Total regions: 16.
    static let regionCount = 16
    /// GIF pixels per region side: 64 / 4 = 16.
    static let regionSide = 16
    /// The spatial plane side of the honest ceiling: 64.
    static let planeSide = 64
    /// The coarsest depth (the 16-rung; CubeBrush depth 0).
    static let minDepth = 0
    /// The finest depth (the 64-rung, the ceiling; CubeBrush depth 2).
    static let maxDepth = 2
    /// Frame-units one pour deposits: one 4-frame slice.
    static let pourDeposit = 4
    /// Pours per capture: the 64-frame burst in 4-frame slices.
    static let pourCap = 16
    /// Banked 32-evidence that unlocks 32↔64: one full window (= windowUnits).
    static let threshold32 = 64

    /// The price of splitting FROM depth d: 2^d — the S-tower price.
    static func splitCost(_ d: Int) -> Int { 1 << max(0, d) }

    // MARK: State (read-only outside; `step` is the only writer)

    /// Per-region depth, raster order (0 = 16, 1 = 32, 2 = 64).
    private(set) var depths: [Int]
    /// Banked, unspent frame-units.
    private(set) var signal: Int
    /// Frame-units spent on splits (monotone).
    private(set) var spent: Int
    /// Pours ingested (≤ pourCap).
    private(set) var pours: Int
    /// Banked 32-evidence frame-units (monotone — never un-banks).
    private(set) var bank32: Int
    /// THE DECISION WORD: accepted ops in play order.
    private(set) var word: [S4MergeOp]

    /// The opening board: all-coarse, zero ledger, empty word.
    init() {
        depths = [Int](repeating: Self.minDepth, count: Self.regionCount)
        signal = 0
        spent = 0
        pours = 0
        bank32 = 0
        word = []
    }

    // MARK: Derived

    /// Is the fine phase open? Monotone in the game history.
    var phase2Unlocked: Bool { bank32 >= Self.threshold32 }

    /// The win: every region at the ceiling — the 64³ is constructed.
    var fullyConstructed: Bool { depths.allSatisfy { $0 == Self.maxDepth } }

    /// How many regions sit at depth ≥ d — the pour's crediting count.
    func count(atLeast d: Int) -> Int { depths.lazy.filter { $0 >= d }.count }

    /// The region owning a plane pixel: raster blocks of `regionSide`.
    static func regionOfPixel(x: Int, y: Int) -> Int {
        (y / regionSide) * boardSide + (x / regionSide)
    }

    /// The board's depth field on the plane — constant on regions; the
    /// per-region scale field renderSelect draws.
    func depthAtPixel(x: Int, y: Int) -> Int {
        depths[Self.regionOfPixel(x: x, y: y)]
    }

    // MARK: The step (total; the twin of `Spec.MergeBoard.step`)

    /// Apply one op. Guard order for S: ceiling, then phase, then price.
    /// A pour credits `bank32` against the PRE-pour depths: evidence lands
    /// where the board is measuring when the slice arrives.
    @discardableResult
    mutating func step(_ op: S4MergeOp) -> S4MergeVerdict {
        switch op {
        case .pour:
            guard pours < Self.pourCap else { return .rejected(.poursExhausted) }
            signal += Self.pourDeposit
            pours += 1
            bank32 += Self.pourDeposit * count(atLeast: 1)
        case .move(let r, let verb):
            guard (0..<Self.regionCount).contains(r) else { return .rejected(.offBoard) }
            switch verb {
            case .i:
                break
            case .k:
                guard depths[r] > Self.minDepth else { return .rejected(.alreadyCoarsest) }
                depths[r] -= 1
            case .s:
                guard depths[r] < Self.maxDepth else { return .rejected(.alreadyFinest) }
                if depths[r] == 1 && !phase2Unlocked { return .rejected(.phaseLocked) }
                let cost = Self.splitCost(depths[r])
                guard signal >= cost else { return .rejected(.noSignal) }
                depths[r] += 1
                signal -= cost
                spent += cost
            }
        }
        word.append(op)
        return .accept
    }

    /// Fold a whole op list from the opening board (refusals are no-ops).
    static func playAll(_ ops: [S4MergeOp]) -> S4MergeBoard {
        var b = S4MergeBoard()
        for op in ops { b.step(op) }
        return b
    }

    // MARK: The wire (the `.s4cr` v3 `dw` key)

    /// One op as its wire code — the twin of `Spec.CaptureRecord.gameOpCode`:
    /// 0 = pour, 1 + 3·region + verb. Off-board regions clamp (harmless: a
    /// real word never contains one — the board refuses them unrecorded).
    static func opCode(_ op: S4MergeOp) -> UInt64 {
        switch op {
        case .pour:
            return 0
        case .move(let r, let verb):
            let clamped = min(regionCount - 1, max(0, r))
            return UInt64(1 + 3 * clamped + verb.rawValue)
        }
    }

    /// Decode one wire code — the twin of `Spec.CaptureRecord.gameOpFromCode`;
    /// refuses anything past the board's last verb (48).
    static func op(fromCode code: UInt64) -> S4MergeOp? {
        if code == 0 { return .pour }
        guard code >= 1, code <= UInt64(3 * regionCount) else { return nil }
        let m = Int(code - 1)
        guard let verb = S4MergeVerb(rawValue: m % 3) else { return nil }
        return .move(m / 3, verb)
    }

    /// The decision word as `.s4cr` v3 op-codes — what
    /// `S4CaptureRecord.decisionWord` carries at ACCEPT.
    var decisionWordCodes: [UInt64] { word.map(Self.opCode) }

    // MARK: The pinned tight construction (the twin of `canonicalConstruction`)

    /// Pour once, open four regions at 32, bank the threshold in four pours,
    /// open the rest, fund the fine phase in seven pours, construct:
    /// 12 pours, 48 spent, ends at signal 0 (`lawCanonicalRunConstructs`).
    static let canonicalConstruction: [S4MergeOp] =
        [.pour]
        + (0...3).map { .move($0, .s) }
        + [S4MergeOp](repeating: .pour, count: 4)
        + (4...15).map { .move($0, .s) }
        + [S4MergeOp](repeating: .pour, count: 7)
        + (0...15).map { .move($0, .s) }
}
