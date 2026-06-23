{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE KindSignatures #-}

{- |
Module      : SixFour.Spec.Sided
Description : Type-enforced QUARANTINE of DISPLAY-side floats from the bit-exact COMMIT — a display\/signal float reaching the committed bytes becomes a compile error, not a runtime law. The ORTHOGONAL companion to "SixFour.Spec.ByteCarrier": ByteCarrier's @MacTag@ separates float-vs-byte, but a 'Latent' and a 'Display' are BOTH Mac-side floats, so a NEW axis (display-side vs commit-side) is needed; the two compose.

The quarantine contract ("SixFour.Spec.DisplayDecoder"): the displayed L-16³ preview and
the content-responsive 'MoveSignal' signal are LOSSY, decoder-dependent floats; the
committed Q16 bytes are a pure function of the LATENT, blind to the display. Today this is
enforced only by the ABSENCE of a @Display@ argument on @commit@ — and 'Latent', 'Display',
'Commit', 'Gesture' are all bare @type@ synonyms over @[Double]@\/@[Int]@, so a @Display@ IS
structurally a @Latent@ and flows into @commit@\/@steer@ with NO type error. The runtime laws
@lawCommitQuarantinedFromDisplay@ \/ @lawSignalQuarantinedFromCommit@ guard this, but the
type system does not.

This module makes the quarantine a TYPE, exactly as "SixFour.Spec.ByteCarrier" makes
float-into-byte a type:

  * @'Sided' side a@ is a phantom-tagged carrier; its constructor is __hidden__.
  * @'DisplaySide'@ tags a value the user SEES\/steers by (a preview\/signal float).
  * @'CommitSide'@ tags a value on the deterministic commit path (the latent\/floor).
  * Smart builders 'mkLatentS' \/ 'displayDecodeS' \/ 'signalAtS' produce 'DisplaySide';
    'steerS' \/ 'commitS' CONSUME and PRODUCE only 'CommitSide'.

The teeth are the EXPORTS: there is NO @Sided DisplaySide a -> Sided CommitSide a@ and the
constructor is unexported, so @'commitS' (displayDecodeS w z)@ and @'commitS' (signalAtS m d)@
do not type-check — @Couldn't match type 'DisplaySide' with 'CommitSide'@. There is no
laundering escape ('unDisplayS' returns a raw @a@, which 'commitS' cannot accept either,
because 'commitS' takes a @Sided CommitSide@, not a raw @a@).

Additive: a NEW leaf module + 'Sided'-typed VARIANTS of the existing operations. The shipped
"SixFour.Spec.DisplayDecoder" \/ "SixFour.Spec.MoveSignal" \/ "SixFour.Spec.ContinuousLoop"
@[Double]@-typed signatures are UNCHANGED (no golden-gated contract re-pinned); callers
migrate opt-in. Kept at the ADT\/smart-constructor layer (phantom tags + export discipline),
NOT DataKinds\/LiquidHaskell, per the project's spec methodology.
-}
module SixFour.Spec.Sided
  ( -- * The sided carrier (constructor HIDDEN on purpose)
    Sided
  , DisplaySide
  , CommitSide
  , DisplayF
  , CommitF
  , CommitI
    -- * Display-side builders (produce DisplaySide; can NEVER reach commit)
  , mkDisplayS
  , displayDecodeS
  , signalAtS
  , unDisplayS
    -- * Commit-side path (consumes/produces ONLY CommitSide)
  , mkLatentS
  , steerS
  , commitS
  , unCommitI
    -- * Laws (the type makes these redundant; kept as living documentation)
  , lawSidedDisplayCannotCommit
  , lawSidedCommitRoundTrips
  ) where

-- | Phantom tag: a value on the DISPLAY side (a lossy preview\/signal float the user sees).
data DisplaySide

-- | Phantom tag: a value on the COMMIT side (the latent\/floor that becomes the GIF bytes).
data CommitSide

-- | A side-tagged carrier. The constructor is NOT exported, so the only carriers a client can
-- build are via the smart builders below; there is no @DisplaySide -> CommitSide@ crossing.
newtype Sided (side :: *) a = Sided { unSided :: a }

-- | A display-side float (preview\/signal); barred by type from the commit path.
type DisplayF = Sided DisplaySide Double

-- | A commit-side float (the latent the commit reads).
type CommitF = Sided CommitSide Double

-- | A commit-side integer (the bit-exact committed byte).
type CommitI = Sided CommitSide Int

-- ----------------------------------------------------------------------------
-- Display side (produces DisplaySide; nothing here yields a CommitSide)
-- ----------------------------------------------------------------------------

-- | Wrap a raw display-side float (e.g. a preview readout).
mkDisplayS :: Double -> DisplayF
mkDisplayS = Sided

-- | The learned, lossy display decode, SIDE-TAGGED: latent (commit-side) -> a display float.
-- It reads the commit-side latent's value but its OUTPUT is DisplaySide, so it can never be
-- fed back into 'commitS'.
displayDecodeS :: Double -> CommitF -> DisplayF
displayDecodeS w (Sided z) = Sided (w * z)

-- | The content-responsive move signal ("SixFour.Spec.MoveSignal" @signalAt@), SIDE-TAGGED:
-- a per-octant band energy (its @Detail@ is the integer substrate) times a sensitivity, as a
-- DISPLAY-side float. By type it can NEVER perturb the committed bytes — the quarantine the
-- vacuous @lawSignalQuarantinedFromCommit@ only claimed.
signalAtS :: Double -> DisplayF
signalAtS energy = Sided energy

-- | Read a display-side float's raw value (for Mac-side preview math only). Returns a raw
-- @Double@, NOT a @Sided CommitSide@, so it cannot launder a display value into 'commitS'.
unDisplayS :: DisplayF -> Double
unDisplayS = unSided

-- ----------------------------------------------------------------------------
-- Commit side (consumes/produces ONLY CommitSide)
-- ----------------------------------------------------------------------------

-- | Build a commit-side latent from a raw float (the architecture's continuous state).
mkLatentS :: Double -> CommitF
mkLatentS = Sided

-- | Steering: a chroma action on the commit-side latent. Takes and returns CommitSide only;
-- a display-side value cannot be steered.
steerS :: Double -> CommitF -> CommitF
steerS a (Sided z) = Sided (a + z)

-- | THE COMMIT: latent (commit-side) -> committed Q16 byte (commit-side integer). Defined
-- ONLY on @Sided CommitSide@; a @Sided DisplaySide@ cannot be passed. (Q16 floor stands in as
-- @floor@ here; in the wired version this delegates to "SixFour.Spec.ByteCarrier" @reenterQ16@.)
commitS :: CommitF -> CommitI
commitS (Sided z) = Sided (floor z)

-- | Read the committed byte's integer (the only projection off the commit path).
unCommitI :: CommitI -> Int
unCommitI = unSided

-- ============================================================================
-- Laws (the TYPE makes the quarantine unrepresentable; these document the legal path)
-- ============================================================================

-- | The quarantine, stated positively: the commit of a steered latent is a function of the
-- LATENT alone. A display value cannot appear in this expression (it would not type-check),
-- which is the whole point — the runtime @lawCommitQuarantinedFromDisplay@ becomes redundant.
lawSidedDisplayCannotCommit :: Bool
lawSidedDisplayCannotCommit =
  let z  = mkLatentS 2.7
      a  = 1.0
  in unCommitI (commitS (steerS a z)) == unCommitI (commitS (mkLatentS (1.0 + 2.7)))

-- | The commit side round-trips trivially: building a latent and committing it yields its floor.
lawSidedCommitRoundTrips :: Bool
lawSidedCommitRoundTrips =
  unCommitI (commitS (mkLatentS 3.9)) == (3 :: Int)
