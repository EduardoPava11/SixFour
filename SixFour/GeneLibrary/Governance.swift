import Foundation

// Hand-written port of SixFour.Spec.Governance + SixFour.Spec.GuildScale (the swap-economy
// governance layer). Integer/enum-exact — no floating point, no identity binding, no persistence —
// and verified list-exact against the spec golden `GovernanceContract` (Codegen.Governance) in
// GovernanceGoldenTests. A guild picks one Constitution; `govern` IS its self-rule, run over a roster
// that is itself a fold of the trade ledger (prestige = demand, tenure = seniority, grades = ballots).

/// An ordinal majority-judgment ballot grade (0 = reject … 4 = excellent).
enum Grade: Int, Comparable, CaseIterable, Sendable {
    case reject = 0, poor, fair, good, excellent
    static func < (a: Grade, b: Grade) -> Bool { a.rawValue < b.rawValue }
}

/// A rankable guild member. Every field is derivable from the trade ledger; here it is the input a
/// constitution ranks over.
struct Member: Equatable, Sendable {
    let id: Int          // creator identity (a Game Center player-id binding, later)
    let prestige: Int    // demand: trades taken — the rank scalar
    let tenure: Int      // epochs since first publish — the seniority scalar
    let reliability: Double // trust in [0,1] — the gate scalar (unused by ordering; carried for gating)
    let grades: [Grade]  // ballots received (an accepted trade is a graded ballot)
}

/// The four simplest socio-political forms a guild can adopt. Each is a total ranking function.
enum Constitution: Equatable, Sendable {
    case meritocracy         // order by prestige
    case gerontocracy        // order by tenure
    case majorityJudgment    // order by median grade (tie-free on an odd panel)
    case monarchy(Int)       // a fixed sovereign (by member id) on top, the rest by prestige
}

/// The governance layer: derived sizes + the constitution ranking. Namespaced, stateless, pure.
enum Governance {
    // ── Derived social-body sizes (SixFour.Spec.GuildScale) ──
    /// The odd council size (largest odd within Miller's deliberation span).
    static let councilSize = 7
    /// The decision threshold (strict majority of the council).
    static let quorum = 4
    /// The hard guild membership ceiling (Dunbar's cohesion number); past it a guild must schism.
    static let guildCap = 150

    /// The (lower) median grade of a ballot multiset, or nil when empty.
    static func median(_ grades: [Grade]) -> Grade? {
        guard !grades.isEmpty else { return nil }
        let sorted = grades.sorted()
        return sorted[(sorted.count - 1) / 2]
    }

    /// The majority-judgment order over two ballot multisets: compare medians, and on a tie drop one
    /// median grade from each side and recurse (the standard tie-break). Returns -1 / 0 / +1.
    static func mjCompare(_ a: [Grade], _ b: [Grade]) -> Int {
        switch (median(a), median(b)) {
        case (nil, nil): return 0
        case (nil, _): return -1
        case (_, nil): return 1
        case let (ma?, mb?):
            if ma != mb { return ma < mb ? -1 : 1 }
            return mjCompare(removeOne(ma, a), removeOne(mb, b))
        }
    }

    private static func removeOne(_ x: Grade, _ xs: [Grade]) -> [Grade] {
        guard let idx = xs.firstIndex(of: x) else { return xs }
        var out = xs
        out.remove(at: idx)
        return out
    }

    /// Compare two members under a constitution (`.orderedDescending` ⇒ `a` outranks `b`). This is the
    /// constitution's primary key; `govern` adds the id tie-break to make the order total.
    static func rankCompare(_ c: Constitution, _ a: Member, _ b: Member) -> ComparisonResult {
        switch c {
        case .meritocracy:  return cmp(a.prestige, b.prestige)
        case .gerontocracy: return cmp(a.tenure, b.tenure)
        case .majorityJudgment:
            let r = mjCompare(a.grades, b.grades)
            return r < 0 ? .orderedAscending : (r > 0 ? .orderedDescending : .orderedSame)
        case .monarchy(let k):
            switch (a.id == k, b.id == k) {
            case (true, false): return .orderedDescending
            case (false, true): return .orderedAscending
            default:            return cmp(a.prestige, b.prestige)
            }
        }
    }

    private static func cmp(_ x: Int, _ y: Int) -> ComparisonResult {
        x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
    }

    /// Apply a constitution: members most-authority-first, ties broken by ascending id — a total,
    /// deterministic order (a permutation of the roster).
    static func govern(_ c: Constitution, _ members: [Member]) -> [Member] {
        members.sorted { x, y in
            switch rankCompare(c, y, x) {   // flip: higher rank first
            case .orderedAscending:  return true
            case .orderedDescending: return false
            case .orderedSame:       return x.id < y.id
            }
        }
    }

    /// The head of the governed order (highest authority), or nil for an empty roster.
    static func leader(_ c: Constitution, _ members: [Member]) -> Member? {
        govern(c, members).first
    }

    /// The council: the top `councilSize` of the governed order.
    static func council(_ c: Constitution, _ members: [Member]) -> [Member] {
        Array(govern(c, members).prefix(councilSize))
    }
}
