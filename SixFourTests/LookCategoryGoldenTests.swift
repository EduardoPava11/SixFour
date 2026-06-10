import Testing
import simd
@testable import SixFour

/// Pins the on-device look taxonomy (`SFLookCategory`) to the spec golden
/// (`LookCategoryContract`, from `SixFour.Spec.LookCategory`). Prototypes are
/// well-separated so nearest-prototype classification is precision-independent
/// (Float port vs Double golden).
struct LookCategoryGoldenTests {

    @Test func classifyMatchesGolden() {
        #expect(LookCategoryContract.goldenDescriptors.count
                == LookCategoryContract.goldenCategories.count)
        for (i, d) in LookCategoryContract.goldenDescriptors.enumerated() {
            let got = SFLookCategory.classify(SIMD3<Float>(Float(d.x), Float(d.y), Float(d.z)))
            #expect(got == LookCategoryContract.goldenCategories[i],
                    "descriptor \(d) → \(got) vs \(LookCategoryContract.goldenCategories[i])")
        }
    }

    @Test func descriptorOfSingletonIsThatColour() {
        let c = SIMD3<Float>(0.31, 0.12, -0.21)
        let d = SFLookCategory.descriptor([c])
        #expect(abs(d.x - c.x) < 1e-6 && abs(d.y - c.y) < 1e-6 && abs(d.z - c.z) < 1e-6)
    }

    @Test func emptyPaletteIsTotal() {
        // Empty ⇒ neutral centre ⇒ some valid category name (no crash, total).
        #expect(SFLookCategory.names.contains(SFLookCategory.name([])))
    }
}
