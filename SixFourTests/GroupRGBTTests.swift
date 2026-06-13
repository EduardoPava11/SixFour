import Testing
import simd
@testable import SixFour

/// Byte-exact gate for `GroupRGBT` (Swift twin of `Spec.GroupRGBT`) + the group-select
/// `LadderExport.flatGlobalLeaves` seam. Mirrors the Haskell laws, EXACT — no tolerance.
struct GroupRGBTTests {

    /// A deterministic 64-frame burst, each frame a small sRGB8 palette.
    private func burst() -> [[SIMD3<UInt8>]] {
        (0 ..< 64).map { f in
            (0 ..< 4).map { i -> SIMD3<UInt8> in
                let r = UInt8((f * 4 + i) & 0xFF)
                let g = UInt8((i * 60) & 0xFF)
                let b = UInt8((f * 3) & 0xFF)
                return SIMD3<UInt8>(r, g, b)
            }
        }
    }

    @Test func groupsOf4FlattenIsIdentity() {
        let fs = burst()
        #expect(GroupRGBT.groupsOf4(fs).flatMap { $0 } == fs)
        #expect(GroupRGBT.groupsOf4(fs).count == 16)        // 64 / 4
        #expect(GroupRGBT.groupsOf4(fs).allSatisfy { $0.count == 4 })
    }

    @Test func allSelectedKeepsEveryFrame() {
        let fs = burst()
        #expect(GroupRGBT.selectedFrames(GroupRGBT.allSelected(fs), fs) == fs)
    }

    @Test func singleGroupSelectsExactlyThatGroup() {
        let fs = burst()
        let groups = GroupRGBT.groupsOf4(fs)
        for j in [0, 1, 7, 15] {
            let mask = (0 ..< 16).map { $0 == j }
            #expect(GroupRGBT.selectedFrames(mask, fs) == groups[j])
        }
    }

    @Test func deselectRemovesExactlyThatGroup() {
        let fs = burst()
        let groups = GroupRGBT.groupsOf4(fs)
        let j = 5
        let mask = (0 ..< 16).map { $0 != j }
        let expected = groups.enumerated().filter { $0.offset != j }.flatMap { $0.element }
        #expect(GroupRGBT.selectedFrames(mask, fs) == expected)
    }

    @Test func emptySelectionIsEmpty() {
        let fs = burst()
        #expect(GroupRGBT.selectedFrames([Bool](repeating: false, count: 16), fs).isEmpty)
    }

    // MARK: the LadderExport seam (picks are real)

    @Test func allSelectedFlatLeavesEqualsNoArg() {
        let fs = burst()
        let all = GroupRGBT.allSelected(fs)
        #expect(LadderExport.flatGlobalLeaves(palettesPerFrame: fs, selectedGroups: all)
                == LadderExport.flatGlobalLeaves(palettesPerFrame: fs))
    }

    @Test func singleGroupFlatLeavesEqualsThatGroupAlone() {
        let fs = burst()
        let groups = GroupRGBT.groupsOf4(fs)
        for j in [0, 9, 15] {
            let mask = (0 ..< 16).map { $0 == j }
            #expect(LadderExport.flatGlobalLeaves(palettesPerFrame: fs, selectedGroups: mask)
                    == LadderExport.flatGlobalLeaves(palettesPerFrame: groups[j]))
        }
    }

    @Test func fewerGroupsCanChangeTheGlobal() {
        // Selecting a single group generally yields a DIFFERENT global than all 64 —
        // the picks demonstrably change the exported palette (not cosmetic).
        let fs = burst()
        let one = (0 ..< 16).map { $0 == 0 }
        let allLeaves = LadderExport.flatGlobalLeaves(palettesPerFrame: fs)
        let oneLeaves = LadderExport.flatGlobalLeaves(palettesPerFrame: fs, selectedGroups: one)
        #expect(allLeaves != oneLeaves)
    }
}
