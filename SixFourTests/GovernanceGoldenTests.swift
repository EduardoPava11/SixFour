import Testing
@testable import SixFour

/// Pins the hand-written `Governance` port (SixFour.Spec.Governance.govern + the GuildScale sizes)
/// to the spec golden `GovernanceContract` (Codegen.Governance). Integer/enum-exact: the roster and
/// the expected leader-first orderings are reproduced from the committed contract, so the Swift
/// `govern` cannot drift from the Haskell `govern` without failing here.
struct GovernanceGoldenTests {

    /// Rebuild the golden roster from the contract (index-aligned columns).
    private func roster() -> [Member] {
        GovernanceContract.rosterIds.indices.map { i in
            Member(id: GovernanceContract.rosterIds[i],
                   prestige: GovernanceContract.rosterPrestige[i],
                   tenure: GovernanceContract.rosterTenure[i],
                   reliability: 1.0,
                   grades: GovernanceContract.rosterGrades[i].map { Grade(rawValue: $0)! })
        }
    }

    @Test func derivedSizesMatchGolden() {
        #expect(Governance.councilSize == GovernanceContract.councilSize)
        #expect(Governance.quorum == GovernanceContract.quorum)
        #expect(Governance.guildCap == GovernanceContract.guildCap)
    }

    @Test func meritocracyOrderMatchesGolden() {
        let ids = Governance.govern(.meritocracy, roster()).map(\.id)
        #expect(ids == GovernanceContract.rankMeritocracy)
    }

    @Test func gerontocracyOrderMatchesGolden() {
        let ids = Governance.govern(.gerontocracy, roster()).map(\.id)
        #expect(ids == GovernanceContract.rankGerontocracy)
    }

    @Test func majorityJudgmentOrderMatchesGolden() {
        let ids = Governance.govern(.majorityJudgment, roster()).map(\.id)
        #expect(ids == GovernanceContract.rankMajorityJudgment)
    }
}
