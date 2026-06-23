{- |
Module      : SixFour.Spec.IsometryMove
Description : The EXACT, SIMT-native delta-preserving move on Q16 OKLab — the A/B genome step.

The A/B genome game advances both candidates by a /structure-preserving/ transform, so the
relative colour deltas WITHIN a frame — and, applied identically to every frame, BETWEEN
frames — do not change (the cause of the degradation was an unconstrained per-leaf nudge that
accumulated). On the integer Q16 lattice the moves that preserve every pairwise squared
distance EXACTLY (no ε) are the lattice isometries built from:

  * an integer TRANSLATION @t@ — the continuous A\/B knob (a global OKLab shift); and
  * an axis SIGN-FLIP @s ∈ {+1,−1}³@ on (L,a,b), of which σ = (L,−a,−b)
    (the proven 'SixFour.Spec.PairTree.lawSigmaEuclideanIsometry') is the canonical member.

Each is a handful of integer negate\/add ops per colour — byte-exact AND embarrassingly
SIMD\/SIMT-parallel across the 256 leaves × 64 frames (no matmul, no rounding). A continuous
rotation is deliberately EXCLUDED: a rounded integer rotation is reversible but drifts ~1 LSB
per shear, so it cannot carry a no-tolerance pairwise-delta law.

== The move

@
'apply' ('IsoMove' (sₗ,sₐ,s_b) (tₗ,tₐ,t_b)) (l,a,b) = (sₗ·l+tₗ, sₐ·a+tₐ, s_b·b+t_b)
@

The composition of a sign-flip and a translation is a lattice isometry; 'applyMove' maps it
over a whole list of generators, moving every colour /coherently/ — only a global reflect +
shift, never an independent per-leaf nudge.

Laws (QuickCheck'd in @Properties.IsometryMove@, EXACT — no ε):

  * 'lawMovePreservesPairwiseDelta' — @distSqQ16 (apply m x) (apply m y) == distSqQ16 x y@.
  * 'lawMoveReversible' — @apply (invert m) (apply m x) == x@.
  * 'lawIdentityIsNoOp' — the identity move is a byte-exact no-op.
  * 'lawSigmaIsAMove' — @apply sigmaMove (l,a,b) == (l,−a,−b)@ (σ as an 'IsoMove').
  * 'lawComposePreservesPairwiseDelta' — the move group is closed (composition stays exact).

GHC-boot-only. The Swift\/Zig port is one integer negate+add per channel per lane (SIMT).
-}
-- COMPARTMENT: METAL-GPU | tag:CommitSide
module SixFour.Spec.IsometryMove
  ( -- * The move
    IsoMove(..)
  , Sign
  , apply
  , applyMove
  , invert
  , compose
    -- * Canonical instances
  , identityMove
  , translateMove
  , sigmaMove
    -- * Laws (QuickCheck'd in Properties.IsometryMove, EXACT — no ε)
  , lawMovePreservesPairwiseDelta
  , lawMoveReversible
  , lawIdentityIsNoOp
  , lawSigmaIsAMove
  , lawComposePreservesPairwiseDelta
  ) where

import SixFour.Spec.PairTreeFixed (OKLabI)
import SixFour.Spec.QuantFixed    (distSqQ16)

-- | An axis sign: @+1@ (keep) or @−1@ (flip). Constrained to @{+1,−1}@; the generators in
-- @Properties.IsometryMove@ only ever produce @±1@ (any other value breaks the isometry laws).
type Sign = Int

-- | A lattice isometry on Q16 OKLab: per-axis sign-flips @(sₗ,sₐ,s_b)@ (each @±1@) followed by
-- an integer translation @(tₗ,tₐ,t_b)@. Both halves preserve every pairwise distance exactly,
-- so their composition does too.
data IsoMove = IsoMove
  { isoSigns :: (Sign, Sign, Sign)   -- ^ per-axis @±1@ sign-flip on (L,a,b)
  , isoShift :: OKLabI               -- ^ integer Q16 translation added after the flip
  } deriving (Eq, Show)

-- | Apply the move to one colour: flip each axis by its sign, then add the translation.
apply :: IsoMove -> OKLabI -> OKLabI
apply (IsoMove (sl, sa, sb) (tl, ta, tb)) (l, a, b) =
  (sl * l + tl, sa * a + ta, sb * b + tb)

-- | Apply the move to every colour in a list (the σ-pair generators / a palette) — the SAME
-- isometry to all, so their relative structure is preserved.
applyMove :: IsoMove -> [OKLabI] -> [OKLabI]
applyMove = map . apply

-- | The inverse move (@apply (invert m) . apply m == id@). Each sign is its own inverse, so the
-- inverse re-uses the signs and translates by @−(s·t)@.
invert :: IsoMove -> IsoMove
invert (IsoMove ss@(sl, sa, sb) (tl, ta, tb)) =
  IsoMove ss (negate (sl * tl), negate (sa * ta), negate (sb * tb))

-- | Compose two moves into one (@apply (compose m2 m1) == apply m2 . apply m1@). The result is
-- again a sign-flip + translation, so it remains an exact isometry.
compose :: IsoMove -> IsoMove -> IsoMove
compose (IsoMove (s2l, s2a, s2b) (t2l, t2a, t2b)) (IsoMove (s1l, s1a, s1b) (t1l, t1a, t1b)) =
  IsoMove (s2l * s1l, s2a * s1a, s2b * s1b)
          (s2l * t1l + t2l, s2a * t1a + t2a, s2b * t1b + t2b)

-- | The identity move (no flip, no shift) — a byte-exact no-op.
identityMove :: IsoMove
identityMove = IsoMove (1, 1, 1) (0, 0, 0)

-- | A pure translation (no flip) by a Q16 vector — the continuous A/B knob.
translateMove :: OKLabI -> IsoMove
translateMove = IsoMove (1, 1, 1)

-- | σ as a move: @(L, −a, −b)@ — the canonical reflection
-- ('SixFour.Spec.PairTree.lawSigmaEuclideanIsometry'), with no translation.
sigmaMove :: IsoMove
sigmaMove = IsoMove (1, -1, -1) (0, 0, 0)

-- | T1 — the move preserves EVERY pairwise squared distance exactly (the relative deltas within
-- a frame cannot change; applied identically to all frames, neither can the deltas between
-- frames). No ε.
lawMovePreservesPairwiseDelta :: IsoMove -> OKLabI -> OKLabI -> Bool
lawMovePreservesPairwiseDelta m x y =
  distSqQ16 (apply m x) (apply m y) == distSqQ16 x y

-- | T2 — every move is exactly reversible (byte-for-byte round-trip).
lawMoveReversible :: IsoMove -> OKLabI -> Bool
lawMoveReversible m x = apply (invert m) (apply m x) == x

-- | T3 — the identity move is a no-op on any colour.
lawIdentityIsNoOp :: OKLabI -> Bool
lawIdentityIsNoOp x = apply identityMove x == x

-- | T4 — 'sigmaMove' really is σ: it negates a and b and fixes L.
lawSigmaIsAMove :: OKLabI -> Bool
lawSigmaIsAMove (l, a, b) = apply sigmaMove (l, a, b) == (l, negate a, negate b)

-- | T5 — composition stays an exact isometry (the move group is closed under composition).
lawComposePreservesPairwiseDelta :: IsoMove -> IsoMove -> OKLabI -> OKLabI -> Bool
lawComposePreservesPairwiseDelta m2 m1 x y =
  distSqQ16 (apply (compose m2 m1) x) (apply (compose m2 m1) y) == distSqQ16 x y
