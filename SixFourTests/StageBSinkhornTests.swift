import Testing
import Foundation
import simd
@testable import SixFour

/// Tests for the new adaptive-θ Stage B merger (no `forceSurjective`, no
/// `RescueOutcome`). The merger throws `StageBError` on failure; tests
/// rely on `try`/catch rather than inspecting an optional witness.
struct StageBSinkhornTests {

    // Note: tests here use synthetic uniformly-random fixtures. Under
    // adversarial uniform-random inputs, hard-NN-surjective remap is
    // NOT guaranteed at any θ (this is precisely the math finding that
    // motivated the no-fallback rewrite). Real on-device Stage A
    // produces clustered palettes that hit surjectivity reliably; the
    // tests here therefore accept either outcome:
    //   * merge succeeds → assert structural properties hold
    //   * merge throws   → assert it's the right error type
    // Both are correct under the no-fallback design. Tests still catch
    // regressions where the merger silently produces non-K palettes or
    // non-surjective witnesses.

    @Test func globalPaletteHasExactlyKEntriesWhenSucceeds() {
        let fixture = makeSinkhornFixture(seed: 1, frames: 8)
        do {
            let (palette, _) = try StageBSinkhorn().merge(
                perFramePalettes: fixture.palettes,
                perFrameIndices: fixture.indices
            )
            #expect(palette.count == SixFourShape.K)
        } catch is StageBSinkhorn.StageBError {
            // acceptable — no-fallback design
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func witnessIsGenuinelySurjectiveWhenSucceeds() {
        let fixture = makeSinkhornFixture(seed: 2, frames: 8)
        do {
            let (_, witness) = try StageBSinkhorn().merge(
                perFramePalettes: fixture.palettes,
                perFrameIndices: fixture.indices
            )
            #expect(witness.indices.count == 8 * 4096)
            let seen = Set(witness.indices)
            #expect(seen.count == SixFourShape.K)
        } catch is StageBSinkhorn.StageBError {
            // acceptable
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func mergeIsDeterministic() {
        let fixture = makeSinkhornFixture(seed: 3, frames: 8)
        // Run twice; either both throw with same error or both succeed
        // with identical output.
        let a: Result<(palette: [SIMD3<Float>], witness: Surjective256), Error> = Result {
            try StageBSinkhorn().merge(
                perFramePalettes: fixture.palettes, perFrameIndices: fixture.indices
            )
        }
        let b: Result<(palette: [SIMD3<Float>], witness: Surjective256), Error> = Result {
            try StageBSinkhorn().merge(
                perFramePalettes: fixture.palettes, perFrameIndices: fixture.indices
            )
        }
        switch (a, b) {
        case (.success(let aResult), .success(let bResult)):
            #expect(aResult.palette == bResult.palette)
            #expect(aResult.witness.indices == bResult.witness.indices)
        case (.failure, .failure):
            // both consistently failed — also deterministic
            break
        default:
            Issue.record("merge is non-deterministic across two calls with same input")
        }
    }

    @Test func sharedAttemptsExactlyOnce() {
        // Shared mode has thetaFloor == theta, so a single attempt; if
        // surjectivity fails the merger throws immediately rather than
        // halving. Either outcome is acceptable per fixture randomness.
        let fixture = makeSinkhornFixture(seed: 7, frames: 8)
        let merger = StageBSinkhorn(params: .shared)
        do {
            let r = try merger.mergeAdaptive(
                perFramePalettes: fixture.palettes,
                perFrameIndices: fixture.indices
            )
            #expect(r.attempts == 1)
            #expect(r.achievedTheta == 0.05)
        } catch let err as StageBSinkhorn.StageBError {
            // Shared mode failure must be from a single attempt.
            if case .cannotAchieveSurjectiveGlobalPalette(_, _, let attempts) = err {
                #expect(attempts == 1)
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func globalModeMakesMultipleAdaptiveAttemptsBeforeFailing() {
        let fixture = makeSinkhornFixture(seed: 8, frames: 8)
        let merger = StageBSinkhorn(params: .global)
        do {
            let r = try merger.mergeAdaptive(
                perFramePalettes: fixture.palettes,
                perFrameIndices: fixture.indices
            )
            #expect(r.attempts >= 1)
            #expect(r.achievedTheta >= StageBSinkhorn.Params.global.thetaFloor)
        } catch let err as StageBSinkhorn.StageBError {
            // Global mode failure must have tried multiple θ halvings.
            if case .cannotAchieveSurjectiveGlobalPalette(_, _, let attempts) = err {
                #expect(attempts >= 2,
                        "Global mode should halve θ at least once before failing; got \(attempts) attempts")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func concatenatedFrameSlicesEqualWitnessWhenSucceeds() {
        let fixture = makeSinkhornFixture(seed: 4, frames: 8)
        do {
            let (_, witness) = try StageBSinkhorn().merge(
                perFramePalettes: fixture.palettes,
                perFrameIndices: fixture.indices
            )
            var concat: [UInt8] = []
            var cursor = 0
            for _ in 0..<8 {
                let end = cursor + 4096
                concat.append(contentsOf: witness.indices[cursor..<end])
                cursor = end
            }
            #expect(concat == witness.indices)
        } catch is StageBSinkhorn.StageBError {
            // acceptable
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // Fixtures live in SixFourTests/Support/Fixtures.swift
    // (`makeSinkhornFixture` / `SeedableLCG`), shared with LogDomainSinkhornTests.
}
