{- |
Module      : SixFour.Spec.DisplayDecoder
Description : The displayed L-16³ is a LEARNED, lossy, non-deterministic DECODE of the free continuous latent — a human steering view, NOT an architectural level. Its keystone is the QUARANTINE: the committed Q16 output is a pure function of the latent, blind to the display decoder, so the float preview can NEVER contaminate the bit-exact bytes. Steering still acts on the latent, so the approximate preview drives a real, deterministic commit.

The user's decision (challenge accepted): "show an L-16³, but it does NOT need to be the
architecture." The architecture's latent stays free and continuous (JEPA-abstract); the
L-16³ the user sees and steers is a LEARNED decoder readout of that latent — maximally
decoupled (a lossy, decoder-dependent float view, not a canonical projection). That buys
maximum architectural freedom at the cost of a non-deterministic preview and approximate
live steering.

The cost is made SAFE by one invariant. The committed output — the bytes that actually
become the GIF — is a pure function of the LATENT through the single Q16 crossing
("SixFour.Spec.ByteCarrier" @reenterQ16@), with NO display input. So however lossy or
non-deterministic the preview is, it cannot move the committed bytes:

  * 'lawCommitQuarantinedFromDisplay' (KEYSTONE) — 'commit' is the Q16 floor of the latent
    alone; a forbidden 'commitLeaky' that folded the display in DIVERGES across two displays
    of the same latent, proving the display carries information the real commit deliberately
    ignores. The float preview is quarantined from the integer floor.
  * 'lawDisplayIsLossyFloat' — the display is a decoder-DEPENDENT float view: two learned
    decoders give different L-16³ of the same latent. It is NOT a canonical projection and
    NOT the committed bytes — the accepted approximation, made explicit.
  * 'lawSteeringActsOnLatent' — a (nonzero) chroma action moves the LATENT and hence the
    committed output (steering is real and deterministic at commit); the zero action is the
    identity. So the approximate preview still drives an exact result.

Additive: self-contained second-order contract over @[Double]@ latents / @[Int]@ commits;
the only repo coupling is "SixFour.Spec.ByteCarrier" (the one sanctioned float→device
crossing). Re-pins NOTHING. The displayed L-16³ is hereby a QUARANTINED VIEW, provably not
a level — "SixFour.Spec.HJepaLevels" (the architecture) is untouched. GHC-boot-only; laws
QuickCheck'd in "Properties.DisplayDecoder".
-}
module SixFour.Spec.DisplayDecoder
  ( -- * The three spaces
    Latent
  , Display
  , Commit
    -- * The deterministic commit (latent → Q16 bytes, display-free)
  , commit
  , floorOf
    -- * The learned, lossy display (latent → human view) and the forbidden leak
  , displayDecode
  , commitLeaky
    -- * Steering (a chroma action on the latent)
  , steer
    -- * Laws (QuickCheck'd in @Properties.DisplayDecoder@)
  , lawCommitQuarantinedFromDisplay
  , lawDisplayIsLossyFloat
  , lawSteeringActsOnLatent
  ) where

import SixFour.Spec.ByteCarrier (mkLatent, reenterQ16, toByte)

-- | The free continuous latent (the architecture's state — JEPA-abstract, never the
-- displayed thing).
type Latent = [Double]

-- | The human-facing L-16³ readout (float; what the user sees and steers by).
type Display = [Double]

-- | The committed Q16 bytes — the bit-exact output that becomes the GIF.
type Commit = [Int]

-- | The deterministic Q16 floor of a latent: the SINGLE sanctioned float→device crossing
-- ("SixFour.Spec.ByteCarrier"). This is what 'commit' is.
floorOf :: Latent -> Commit
floorOf = map (toByte . reenterQ16 . mkLatent)

-- | THE COMMIT: latent → committed bytes, through the Q16 floor. Its type has NO 'Display'
-- input — the quarantine is a free theorem, made non-vacuous by 'lawCommitQuarantinedFromDisplay'.
commit :: Latent -> Commit
commit = floorOf

-- | The LEARNED, lossy display decode: @(decoderWeights, latent) → L-16³@. A
-- decoder-dependent float view (here a simple weighted readout), NEVER re-entered to Q16 —
-- it stays in float preview space. Different weights ⇒ different view (the non-determinism
-- the "max decoupling" choice accepts).
displayDecode :: [Double] -> Latent -> Display
displayDecode w z = zipWith (*) w z

-- | The FORBIDDEN anti-pattern (exists only as a counter-example for the keystone's teeth):
-- a commit that folds the display into the bytes. If the real 'commit' did this, the lossy
-- preview would contaminate the output — 'lawCommitQuarantinedFromDisplay' shows it would
-- then diverge across displays, which the real 'commit' never does.
commitLeaky :: Display -> Latent -> Commit
commitLeaky d z = floorOf (zipWith (+) z d)

-- | Steering: apply a chroma ACTION to the latent (acts on the latent, not the display).
-- The committed output reflects it; the zero action is the identity.
steer :: [Double] -> Latent -> Latent
steer = zipWith (+)

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.DisplayDecoder)
-- ============================================================================

-- | KEYSTONE — the QUARANTINE. The committed bytes are the Q16 floor of the LATENT alone,
-- blind to the (learned, lossy) display decoder. 'commit' has no 'Display' argument, so the
-- quarantine is a free theorem; the TEETH make it non-vacuous by exhibiting the forbidden
-- alternative — a 'commitLeaky' that folds the display in DIVERGES for two different displays
-- of the same latent, while 'commit' equals the latent's floor regardless. So the float
-- preview can NEVER move the integer output. (Closed witnesses with whole-unit separation, so
-- no sub-quantum rounding ambiguity.)
lawCommitQuarantinedFromDisplay :: Bool
lawCommitQuarantinedFromDisplay =
  let z  = [1.0, 2.0, 3.0]
      d1 = displayDecode [0, 0, 0] z   -- one decoder's view: [0,0,0]
      d2 = displayDecode [1, 1, 1] z   -- another decoder's view: [1,2,3]
  in commit z == floorOf z                       -- commit IS the latent's Q16 floor (display-free)
     && d1 /= d2                                  -- the two displays genuinely differ
     && commitLeaky d1 z /= commitLeaky d2 z      -- TEETH: a display-leaking commit IS contaminated

-- | The display is a LEARNED, decoder-dependent float view — two decoders give different
-- L-16³ of the same latent, and it is never the committed bytes. This is the accepted
-- approximation of the "max decoupling" choice, made explicit. Teeth: a claim that the
-- display were a single canonical/deterministic projection fails (different weights diverge).
lawDisplayIsLossyFloat :: Bool
lawDisplayIsLossyFloat =
  let z  = [0.5, 1.5, 2.5]
      d1 = displayDecode [1, 1, 1] z
      d2 = displayDecode [2, 2, 2] z
  in d1 /= d2                          -- decoder-dependent (non-canonical) view
     && d2 == map (* 2) d1             -- it really is the learned readout, not a fixed map

-- | Steering acts on the LATENT, so the (approximate) preview drives a REAL, deterministic
-- result: a nonzero chroma action changes the committed output, and the zero action is the
-- identity. Teeth: a "steer" that left the latent (hence the commit) unchanged would fail the
-- first conjunct; one that moved the commit on a zero action would fail the second.
lawSteeringActsOnLatent :: Bool
lawSteeringActsOnLatent =
  let z = [1.0, 2.0, 3.0]
      a = [1.0, 1.0, 1.0]              -- a nonzero chroma action
  in commit (steer a z) /= commit z    -- steering moves the deterministic commit
     && steer [0, 0, 0] z == z         -- the zero action is the identity
