{- |
Module      : SixFour.Spec.MoveSignal
Description : The CONTENT-RESPONSIVE move signal (v1): how much a chroma move moves THIS texture = a per-octant texture ENERGY (deterministic, trainer-free) times a per-move SENSITIVITY (pinned to 1 in v1; the trained head's local chroma gain multiplies in later). Closes the "moveMagnitude is a constant" gap (HARD #1) — the steering organ's feedback channel.

The gap (from the adversarial invariant hunt + the form-follows-function audit):
"SixFour.Spec.TwoMoveOctave" 'moveMagnitude' is proven a CONSTANT @== 2@ for every path
('lawMoveMagnitudeIsConstant') — it is the move's abstract LATTICE COST, blind to the picture.
The function demands a measure that reads LARGE in a textured region and SMALL in a flat one
(how much THIS move moves THIS texture). No function of the COORDINATE can do that; the signal
must read the CONTENT — the octant's reversible-lift detail bands, which are provably ZERO on a
flat octant ("SixFour.Spec.CarrierL" @lawSearchIsZeroOnConstant@) and nonzero on a textured one.

v1 (this module) ships the DETERMINISTIC factor only, with the learned factor pinned to 1, so the
signal is a real gated object TODAY with ZERO dependence on the (unbuilt) large-head trainer —
the project's "frozen floor + bounded learned addition" pattern applied to the signal. The
trained Jacobian sensitivity @||d predictMaskedBandPos / d(a,b)||@ (HARD #1 candidate c) multiplies
into 'moveSensitivity' once weights exist; until then it is 1 and non-vacuous.

THE SEAM this pins: the signal is FLOAT (a smooth perceptual readout) yet reads the bit-exact
INTEGER detail field. So it lives on the DISPLAY side of the "SixFour.Spec.DisplayDecoder"
quarantine: the float signal can NEVER reach the committed bytes (the commit is a pure function of
the latent, blind to the display). This module extends that quarantine from "render cannot move
bytes" to "signal cannot move bytes".

Energy metric choice: a single landing octant is ONE 'Detail' 7-tuple, so its texture energy is
the band L1 NORM (the residual surplus). "SixFour.Spec.DetailEntropy" @detailEntropyBits@ is the
REGIONAL generalisation over a LIST of octants (a single octant has singleton bands = zero
entropy), kept for a future field signal; the per-octant energy here is the L1 norm.

GHC-boot-only. Additive LEAF (nothing depends on it). Laws QuickCheck'd in "Properties.MoveSignal".
-}
module SixFour.Spec.MoveSignal
  ( -- * The content-responsive signal (v1)
    bandEnergy
  , moveSensitivity
  , signalAt
    -- * Laws (QuickCheck'd in @Properties.MoveSignal@)
  , lawFlatOctantZeroSignal
  , lawTexturedMoveStrictlyExceedsFlat
  , lawSignalIsDeterministicFiniteFloat
  , lawSignalQuarantinedFromCommit
  , lawSensitivityReadsContent
  ) where

import SixFour.Spec.OctreeCell (Detail)
import SixFour.Spec.TwoMoveOctave (AbMove)
import SixFour.Spec.DisplayDecoder (lawCommitQuarantinedFromDisplay)

-- | The texture ENERGY of one landing octant: the L1 norm of its 7 reversible-lift detail
-- coefficients (the residual surplus). @0@ on a flat octant (its detail is all-zero,
-- "SixFour.Spec.CarrierL" @lawSearchIsZeroOnConstant@); strictly positive on a textured one.
-- This is the deterministic, trainer-free factor of the signal.
bandEnergy :: Detail -> Double
bandEnergy (a, b, c, e, f, g, h) =
  fromIntegral (abs a + abs b + abs c + abs e + abs f + abs g + abs h)

-- | The per-move SENSITIVITY: the (learned) local chroma gain of the head along the move's axis,
-- evaluated AT the landing octant's content. Pinned to @1@ in v1 — non-vacuous before the large
-- head trains. The trained Jacobian @||d predictMaskedBandPos / d(a,b)||@ (HARD #1 candidate c)
-- multiplies in HERE once weights exist; because that Jacobian is a function of the landing
-- octant's 'Detail' (the position-conditioning the head reads), the TYPE now FORCES the content
-- argument to be in scope — a future implementer pinning it content-blind must do so deliberately
-- (@\\_ _ -> 1.0@), not structurally by a signature that never received the content.
moveSensitivity :: AbMove -> Detail -> Double
moveSensitivity _ _ = 1.0

-- | THE content-responsive signal: @sensitivity(move, landing) * energy(landing octant)@ = "how
-- much THIS move moves THIS texture". v1 = energy only (sensitivity @== 1@). Float, display-side;
-- the integer 'Detail' is the bit-exact substrate it reads, the float gain never re-enters Q16.
signalAt :: AbMove -> Detail -> Double
signalAt m d = moveSensitivity m d * bandEnergy d

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.MoveSignal)
-- ============================================================================

-- | A FLAT octant (all-zero detail — what a constant region produces, delegating
-- "SixFour.Spec.CarrierL" @lawSearchIsZeroOnConstant@ + "SixFour.Spec.DetailEntropy"
-- @lawConstantDetailZeroBits@) carries ZERO signal. Teeth: a signal with a nonzero floor (e.g.
-- the constant @moveMagnitude == 2@) fails.
lawFlatOctantZeroSignal :: AbMove -> Bool
lawFlatOctantZeroSignal m = signalAt m (0, 0, 0, 0, 0, 0, 0) == 0

-- | KEYSTONE: a move into a TEXTURED octant reads STRICTLY larger than into a FLAT one of the
-- same move. This is the property 'moveMagnitude' (a proven constant) CANNOT have — the signal
-- now SEES content. Mirrors "SixFour.Spec.MaskedBandPrediction" @lawSiblingContextStrictlyHelps@.
-- Teeth: any content-blind readout (the old constant signal) gives equal for flat and textured
-- and fails.
lawTexturedMoveStrictlyExceedsFlat :: AbMove -> Detail -> Bool
lawTexturedMoveStrictlyExceedsFlat m d =
  let flat               = (0, 0, 0, 0, 0, 0, 0) :: Detail
      (a, b, c, e, f, g, h) = d
      textured           = (abs a + 1, b, c, e, f, g, h)   -- guaranteed nonzero energy
  in signalAt m flat == 0 && signalAt m textured > signalAt m flat

-- | The signal is a PURE DETERMINISTIC function of the integer detail (same detail -> same
-- signal) and is always a FINITE float (never a NaN/Inf, never an integer byte). It reads NO
-- float-preview state, so unlike a render-difference readout it is reproducible. Teeth: a signal
-- that consulted the lossy display would not be a pure function of the integer detail.
lawSignalIsDeterministicFiniteFloat :: AbMove -> Detail -> Bool
lawSignalIsDeterministicFiniteFloat m d =
  let s = signalAt m d
  in s == signalAt m d && not (isNaN s) && not (isInfinite s) && s >= 0

-- | DORMANT-TEETH (the re-pin's reward): 'moveSensitivity' now RECEIVES the landing 'Detail', so a
-- non-trivial sensitivity (the trained Jacobian, HARD #1 candidate c) CAN read content — the type
-- permits it. This law states the v1 baseline HONESTLY: sensitivity is pinned to a content-blind
-- constant TODAY, so two different landings under the same move agree (@== 1@). When the Jacobian
-- lands, this law is the one to FLIP to @/=@ (two contentful landings must differ) — it cannot be
-- flipped while the signature is @AbMove -> Double@, because there is no content to read. The
-- promotion is that the wrong-input vacuity is now a deliberate body, not a structural ceiling.
lawSensitivityReadsContent :: AbMove -> Detail -> Detail -> Bool
lawSensitivityReadsContent m d1 d2 =
  moveSensitivity m d1 == moveSensitivity m d2   -- v1: pinned constant; FLIP to /= when Jacobian lands

-- | The signal is QUARANTINED from the commit: it lives on the DISPLAY side, and the committed
-- byte is a pure function of the latent, blind to the display (delegates
-- "SixFour.Spec.DisplayDecoder" @lawCommitQuarantinedFromDisplay@). So a float content-signal can
-- NEVER perturb the bit-exact bytes — the quarantine extends from "render cannot move bytes" to
-- "signal cannot move bytes".
lawSignalQuarantinedFromCommit :: Bool
lawSignalQuarantinedFromCommit = lawCommitQuarantinedFromDisplay
