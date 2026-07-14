{-# LANGUAGE EmptyDataDecls #-}

{- |
Module      : SixFour.Spec.ByteCarrier
Description : Type-enforced delineation of which values carry DEVICE BYTES (bit-exact Q16 integers) vs Mac-side FLOAT/latent — a float-into-byte leak becomes a compile error.

The byte contract (CLAUDE.md): the Zig Q16 INTEGER core is the only cross-device
bit-exact substrate; the GIF bytes the device model runs on come from integers ONLY.
Float (Core AI L inference, bf16 conv, the JEPA\/FlowAR latent + continuous
remainder) is NOT bit-exact and MUST re-enter Q16 (the @zero-genome == floor@
short-circuit) before any byte.

The three new spec modules encoded that boundary only by CONVENTION (@[Int]@ happened
to be the surfaced rung, @[Double]@ the latent). This module makes it a TYPE:

  * @'Carried' tag a@ is a phantom-tagged carrier; its constructor is __hidden__.
  * @type 'Q16'    = Carried 'DeviceTag' Int@   — ships and runs on device (a byte source).
  * @type 'Latent' = Carried 'MacTag'    Double@ — Mac-side float, must NOT reach a byte.

The teeth are the EXPORTS: there is exactly ONE float→device crossing, 'reenterQ16'
(the @zero-genome == floor@ requantisation, delegating to
"SixFour.Spec.Q16"'s @quantizeQ16@). There is NO exported @'Latent' -> Int@, so
@'toByte' someLatent@ does not type-check — the type system, not a lint, enforces
"float must never directly carry a device byte". (Raw @Prelude.round@ is of course
always writable, but it is off-spec; the spec's job is to make the SANCTIONED crossing
singular and typed.)

Kept at the ADT\/smart-constructor layer (phantom tags + export discipline), NOT
DataKinds\/LiquidHaskell, per the project's spec methodology. Additive: nothing
imports it yet, so no shipped contract is re-pinned.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:DeviceTag
module SixFour.Spec.ByteCarrier
  ( -- * The carrier (constructor HIDDEN on purpose)
    Carried
  , DeviceTag
  , MacTag
  , Q16
  , Latent
    -- * The only sanctioned constructors / projections
  , mkLatent
  , unLatent
  , q16
  , toByte
    -- * The single float -> device crossing (scalar + batched)
  , reenterQ16
  , reenterQ16Many
    -- * Laws (QuickCheck'd in @Properties.ByteCarrier@)
  , lawByteOnlyFromQ16
  , lawReentryIsFloor
  , lawDeviceRoundTrips
  , lawBatchedReentryIsElementwise
  ) where

import SixFour.Spec.Q16 (quantizeQ16, toQ16)

-- | Phantom tag: a value that carries a DEVICE byte (bit-exact, shipped).
data DeviceTag

-- | Phantom tag: a Mac-side FLOAT\/latent value (must not reach a byte).
data MacTag

-- | A tagged carrier. The constructor is NOT exported, so the only carriers a client
-- can build are via 'mkLatent' \/ 'q16' \/ 'reenterQ16'.
newtype Carried tag a = Carried { unCarried :: a }

-- | A bit-exact device value (the integer the GIF bytes derive from).
type Q16 = Carried DeviceTag Int

-- | A Mac-side continuous value (latent\/remainder); barred by type from the byte path.
type Latent = Carried MacTag Double

-- | Build a Mac-side latent from a raw float.
mkLatent :: Double -> Latent
mkLatent = Carried

-- | Read a latent's float (for Mac-side math only — there is no @Latent -> Int@).
unLatent :: Latent -> Double
unLatent = unCarried

-- | Wrap an integer that is ALREADY on the Q16 floor (e.g. a value from the Zig
-- reversible op) as a device carrier.
q16 :: Int -> Q16
q16 = Carried

-- | The device byte source: extract the bit-exact integer. Defined ONLY on 'Q16'.
toByte :: Q16 -> Int
toByte = unCarried

-- | THE single float→device crossing: requantise a Mac-side latent onto the Q16 floor
-- (@zero-genome == floor@), delegating to "SixFour.Spec.Q16"'s @quantizeQ16@.
reenterQ16 :: Latent -> Q16
reenterQ16 (Carried x) = Carried (quantizeQ16 x)

-- | THE BATCHED float→device crossing: a large I-JEPA / Core AI head emits a VECTOR of
-- bands (an @NDArray@ of float logits), not a scalar. This is the ONLY sanctioned batched
-- door — it is exactly the elementwise 'reenterQ16' (no cross-element coupling, no reduction
-- that could leak one band's float into another's byte), so the vector head re-enters the Q16
-- floor band-by-band through the same single crossing. ('lawBatchedReentryIsElementwise'.)
reenterQ16Many :: [Latent] -> [Q16]
reenterQ16Many = map reenterQ16

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.ByteCarrier)
-- ============================================================================

-- | A device byte produced from a latent equals the latent's @quantizeQ16@ — i.e. the
-- ONLY way a float reaches a byte is through the requantisation seam.
lawByteOnlyFromQ16 :: Double -> Bool
lawByteOnlyFromQ16 x = toByte (reenterQ16 (mkLatent x)) == quantizeQ16 x

-- | A value already on the Q16 floor is a re-entry FIXPOINT: re-entering the float
-- image of an integer grid point returns that integer (delegates to the proven
-- @Q16.lawTerminalQuantizationIdempotent@: @quantizeQ16 (toQ16 q) == q@).
lawReentryIsFloor :: Int -> Bool
lawReentryIsFloor q = toByte (reenterQ16 (mkLatent (toQ16 q))) == q

-- | The device carrier round-trips trivially: @toByte . q16 == id@.
lawDeviceRoundTrips :: Int -> Bool
lawDeviceRoundTrips n = toByte (q16 n) == n

-- | The BATCHED door is exactly elementwise 'reenterQ16': each band re-enters the floor
-- independently, so a vector head's committed bytes are the per-band re-entries with NO
-- cross-band coupling. Teeth: a batched door that summed/normalised across bands (leaking one
-- band's float into another's byte) would differ from the elementwise map and fail.
lawBatchedReentryIsElementwise :: [Double] -> Bool
lawBatchedReentryIsElementwise xs =
  map toByte (reenterQ16Many (map mkLatent xs)) == map (\x -> toByte (reenterQ16 (mkLatent x))) xs
