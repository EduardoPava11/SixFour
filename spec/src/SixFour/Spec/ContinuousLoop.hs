{- |
Module      : SixFour.Spec.ContinuousLoop
Description : The live STEERING LOOP as a proven state machine — hold ONE continuous latent, decode a cheap quarantined preview, let a gesture steer the LATENT, re-decode at the display clock over the 64-frame loop, and COMMIT only on demand. Pins the four pieces ('DisplayDecoder.steer', 'DisplayDecoder.displayDecode', 'TemporalLoop', the deferred commit) into ONE loop whose keystone is the end-to-end quarantine: swapping the lossy display decoder leaves the committed bytes byte-identical.

This is the one phase of the four (pre-train / train / infer / __continuous-infer__) with
no end-to-end spec. The pieces exist; the LOOP that composes them per gesture across the
frames does not. This module is that loop, as types + closed laws.

The loop, one tick:

  * Hold ONE continuous 'LatentCube' — the world-model state.
  * 'step' applies the user's 'Gesture' to the LATENT ("SixFour.Spec.DisplayDecoder" @steer@)
    and decodes a cheap, lossy, quarantined preview ("SixFour.Spec.DisplayDecoder"
    @displayDecode@). It produces @(Display, LatentCube)@ and __NEVER a 'Commit'__
    ('lawStepNeverCommits') — the latent stays in continuous space; no @reenterQ16@.
  * 'commitReconstruct' is the OFF-clock, on-demand event: the single @reenterQ16@ crossing
    to the Q16-floored bytes ("SixFour.Spec.DisplayDecoder" @commit@).

The laws:

  * 'lawStepNeverCommits' — a tick keeps the latent continuous; it is NOT the committed bytes.
  * 'lawIdentityGestureIsFixpoint' — the zero gesture leaves the latent AND the commit invariant.
  * 'lawLoopClosesOverT' — advancing the display clock a full 'period' (no gesture) returns the
    held latent to itself; the frame index wraps (delegates "SixFour.Spec.TemporalLoop"
    @lawTemporalLoopClosesExact@ / @lawLoopWrapsLastToFirst@).
  * 'lawCommitInvariantUnderDisplayDecoder' (KEYSTONE) — two DIFFERENT display decoders give
    DIFFERENT previews but the SAME steered latent and therefore the SAME committed bytes. The
    strongest, end-to-end form of "SixFour.Spec.DisplayDecoder" @lawCommitQuarantinedFromDisplay@:
    the lossy learned preview can never move a committed byte, across the whole loop.

Additive: composes "SixFour.Spec.DisplayDecoder" and "SixFour.Spec.TemporalLoop"; re-pins
NOTHING. Laws are closed @:: Bool@ over explicit witnesses (whole-unit separation, no
sub-quantum rounding ambiguity), @once@-tested in "Properties.ContinuousLoop". GHC-boot-only.
-}
module SixFour.Spec.ContinuousLoop
  ( -- * The loop
    Gesture
  , LatentCube
  , step
  , commitReconstruct
    -- * Laws (closed :: Bool; @once@-tested in @Properties.ContinuousLoop@)
  , lawStepNeverCommits
  , lawIdentityGestureIsFixpoint
  , lawLoopClosesOverT
  , lawCommitInvariantUnderDisplayDecoder
  ) where

import SixFour.Spec.DisplayDecoder
  ( Latent, Display, Commit, commit, displayDecode, steer )
import SixFour.Spec.TemporalLoop
  ( period, loopIndex, lawTemporalLoopClosesExact, lawLoopWrapsLastToFirst )

-- | A user gesture, as a continuous action vector on the latent (the same shape
-- "SixFour.Spec.DisplayDecoder" @steer@ consumes). The zero gesture is the no-op.
type Gesture = [Double]

-- | The world-model state held across the loop — one continuous latent
-- ("SixFour.Spec.DisplayDecoder" @Latent@), never surfaced during steering.
type LatentCube = Latent

-- | ONE loop tick: steer the LATENT by the gesture, then decode a cheap lossy preview from
-- the steered latent. Returns @(preview, latent')@ — NEVER a 'Commit'. The first argument is
-- the (learned, lossy) display decoder's weights; the preview depends on them, the latent
-- does not. This is the per-gesture, per-frame work at the display clock.
step :: [Double] -> Gesture -> LatentCube -> (Display, LatentCube)
step w g z = let z' = steer g z in (displayDecode w z', z')

-- | The OFF-clock, on-demand commit: the single @reenterQ16@ crossing from the continuous
-- latent to the Q16-floored bytes (= "SixFour.Spec.DisplayDecoder" @commit@). Runs only when
-- the user commits, never inside 'step'.
commitReconstruct :: LatentCube -> Commit
commitReconstruct = commit

-- ============================================================================
-- Laws (closed predicates; @once@-tested in Properties.ContinuousLoop)
-- ============================================================================

-- | A loop tick NEVER commits: the latent it carries stays in CONTINUOUS space (no
-- @reenterQ16@), so it is not the committed bytes. Witness: an identity tick leaves the
-- latent intact, and re-reading that latent as the committed (Q16-floored) integers gives a
-- DIFFERENT value — proof the tick did not cross to the floor. Teeth: a 'step' that committed
-- (re-entered Q16) would make @z'@ equal the floored bytes and fail the second conjunct.
lawStepNeverCommits :: Bool
lawStepNeverCommits =
  let z       = [0.3, 1.5, 2.5]
      (_d, z') = step [1, 1, 1] [0, 0, 0] z
  in z' == z                                       -- the loop latent stays continuous
     && map fromIntegral (commit z') /= z'          -- ...and is NOT the committed Q16 bytes

-- | The IDENTITY gesture is a fixpoint of the loop: a zero-gesture tick leaves the held
-- latent unchanged, and therefore the committed result invariant. Teeth: a tick that drifted
-- the latent on a no-op gesture (or whose commit depended on the preview) fails.
lawIdentityGestureIsFixpoint :: Bool
lawIdentityGestureIsFixpoint =
  let z       = [1.5, 2.5, 3.5]
      (_d, z') = step [1, 1, 1] [0, 0, 0] z
  in z' == z
     && commit z' == commit z

-- | The loop CLOSES over the temporal axis: the 64-frame display clock wraps
-- (@loopIndex period == loopIndex 0@; delegates "SixFour.Spec.TemporalLoop"
-- @lawTemporalLoopClosesExact@ / @lawLoopWrapsLastToFirst@), and advancing a full 'period' of
-- no-gesture ticks returns the held latent to itself. Teeth: a tick that drifted the latent
-- over the loop would not return after 'period' iterations; a clock that did not wrap fails
-- the delegated closure.
lawLoopClosesOverT :: Bool
lawLoopClosesOverT =
     period == 64
  && loopIndex period == loopIndex 0               -- the 64-frame clock wraps
  && lawTemporalLoopClosesExact 7                  -- the exact temporal loop closes (delegated)
  && lawLoopWrapsLastToFirst                       -- frame 63 → frame 0 (delegated)
  && (let w        = [1, 1, 1]
          z        = [1.5, 2.5, 3.5]
          loopTick (_d, zz) = step w [0, 0, 0] zz  -- advance one frame, no gesture
          (_dN, zN) = iterate loopTick (displayDecode w z, z) !! period
      in zN == z)                                  -- the held latent is invariant over a full T loop

-- | KEYSTONE — the END-TO-END QUARANTINE. Two DIFFERENT display decoders produce DIFFERENT
-- previews but the SAME steered latent, hence the SAME committed bytes: the lossy, learned,
-- non-deterministic preview can never move a committed byte, across the whole loop. This is
-- the strongest form of "SixFour.Spec.DisplayDecoder" @lawCommitQuarantinedFromDisplay@,
-- lifted to the steering loop. Teeth: a 'step' whose latent update read the display decoder
-- (a leak) would make @z1 /= z2@ and fail; a vacuous "displays never differ" reading fails the
-- first conjunct.
lawCommitInvariantUnderDisplayDecoder :: Bool
lawCommitInvariantUnderDisplayDecoder =
  let z        = [1.5, 2.5, 3.5]
      g        = [1, 1, 1]
      (d1, z1) = step [1, 1, 1] g z
      (d2, z2) = step [9, 9, 9] g z
  in d1 /= d2                          -- the previews genuinely differ (decoder matters for the VIEW)
     && z1 == z2                        -- but the steered latent is decoder-independent
     && commit z1 == commit z2          -- ...so the committed bytes are identical (end-to-end)
