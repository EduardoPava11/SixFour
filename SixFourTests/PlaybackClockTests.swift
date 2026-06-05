import Testing
import Foundation
@testable import SixFour

/// Parity gate for the single playback clock: the generated `SixFourPlaybackClock`
/// contract must match `SixFour.Spec.PlaybackClock`'s golden vectors, and the
/// `PlaybackClock` ObservableObject must obey the transport laws (advance mod-N,
/// scrub pauses + settles, reduce-motion freezes auto-advance at 0).
/// Source of truth: spec/test/Properties/PlaybackClock.hs.
struct PlaybackClockTests {

    // MARK: generated contract <-> Haskell golden

    @Test func contractSelfCheckPasses() {
        #expect(SixFourPlaybackClock.selfCheck())
        #expect(SixFourPlaybackClock.frameCount == 64)
        #expect(SixFourPlaybackClock.goldenAdvanceTable == Array(1..<64) + [0])
    }

    @Test func frameAfterMatchesGoldenTable() {
        let n = SixFourPlaybackClock.frameCount
        for f in 0..<n {
            #expect(SixFourPlaybackClock.frameAfter(f, count: n)
                    == SixFourPlaybackClock.goldenAdvanceTable[f])
        }
    }

    @Test func twoDAndThreeDFrontFaceAgree() {
        let n = SixFourPlaybackClock.frameCount
        for i in 0..<n {
            #expect(SixFourPlaybackClock.twoDFrame(i, count: n)
                    == SixFourPlaybackClock.threeDFrontFace(i, count: n))
        }
    }

    @Test func clampAndTotality() {
        #expect(SixFourPlaybackClock.clampFrame(-5, count: 64) == 0)
        #expect(SixFourPlaybackClock.clampFrame(100, count: 64) == 63)
        #expect(SixFourPlaybackClock.frameAfter(0, count: 0) == 0)   // empty loop
    }

    // MARK: the ObservableObject transport

    @MainActor @Test func advanceCyclesAndScrubPausesAndSettles() {
        let c = PlaybackClock(count: 64)
        c.advance()
        #expect(c.frame == 1)

        c.scrub(to: 40)
        #expect(c.frame == 40)
        #expect(c.playing == false)
        #expect(c.settledFrame == 40)

        // While playing, settledFrame stays frozen (analyzers don't rebuild at 20fps).
        c.togglePlay()                       // -> playing
        let settled = c.settledFrame
        c.advance(); c.advance()
        #expect(c.frame == 42)
        #expect(c.settledFrame == settled)   // unchanged mid-playback
    }

    @MainActor @Test func reduceMotionFreezesAutoAdvanceButAllowsScrub() {
        let c = PlaybackClock(count: 64, reduceMotion: true)
        c.advance()
        #expect(c.frame == 0)                // auto-advance suppressed
        c.scrub(to: 10)                      // discrete input still allowed
        #expect(c.frame == 10)
    }
}
