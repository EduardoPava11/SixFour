{- |
Module      : SixFour.Spec.RemainderTail
Description : The discrete-surfaced / continuous-remainder typed split — closes audit blockers B6 and B1's "lossless by construction" lie.

The audit found two coupled blockers:

  * __B6__ — "the remainder stays CONTINUOUS in the net" contradicts "discrete
    next-scale AR" if they are the SAME object: a categorical/integer AR head has no
    slot for a continuous tail.
  * __B1__ — "lossless by construction" is FALSE; losslessness lives ONLY in the
    reversible integer op plus the retained remainder, never in a lossy quantizer.

The JEPA workflow refined the fix: there is no FSQ/VQ token head at all — the
__surfaced__ layer is the EXACT reversible-integer rung (the @16³@ the user steers,
"SixFour.Spec.OctreeCell"/"SixFour.Spec.SuccessiveRefinement"), and the __remainder__
is a CONTINUOUS tail emitted once by the Mac-side FlowAR head. This module makes them
two DISTINCT TYPES with two DISTINCT reconstruction guarantees, so the contradiction
cannot be written down:

  * 'Surfaced' (integers) reconstructs EXACTLY ('lawSurfacedExact').
  * 'Remainder' (continuous) reconstructs only WITHIN 'eps' ('lawTailWithinEps') and
    is provably NOT bit-exact ('lawTailNotExactWitness') — so "lossless by
    construction" is forbidden for it.
  * Losslessness needs the remainder: dropping it is strictly worse than 'eps'
    ('lawLosslessNeedsRemainder') — the honest B1 statement.
  * The tail is a ONE-SHOT regression, never autoregressed ('lawTailNotAutoregressed'),
    and its channel count is bounded ('lawRemainderChannelsBounded') so the
    retained-for-backward bytes stay small.

The continuous tail decode is modelled as a uniform @1\/tailScale@ quantiser only to
have a concrete, checkable witness of bounded-but-nonzero error; the real tail is a
learned FlowAR output. The bit-exact GIF still comes from re-quantising the
__surfaced__ part to Q16 (see the proposer→Q16 seam, a later module); the tail never
enters the integer floor.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:DeviceTag | STRADDLER
module SixFour.Spec.RemainderTail
  ( -- * The two layers (distinct types — that is the whole point)
    Surfaced(..)
  , Remainder(..)
  , Eps
    -- * Design constants
  , tailScale
  , eps
  , cTail
  , remainderChannels
    -- * Split / reconstruct
  , surfacedOf
  , residualOf
  , quantizeTail
  , tailOf
  , reconstruct
  , dropRemainder
    -- * Generation-plan model (for the one-shot / no-AR law)
  , GenNode(..)
  , genDeps
    -- * Laws (QuickCheck'd in @Properties.RemainderTail@)
  , lawSurfacedExact
  , lawTailWithinEps
  , lawTailNotExactWitness
  , lawLosslessNeedsRemainder
  , lawTailNotAutoregressed
  , lawRemainderChannelsBounded
  ) where

-- | The surfaced layer: EXACT integer voxels (the reversible Q16 rung the user steers).
newtype Surfaced = Surfaced [Int] deriving (Eq, Show)

-- | The remainder layer: a CONTINUOUS tail (the FlowAR-predicted residual that
-- "stays in the net"). A different type from 'Surfaced' on purpose.
newtype Remainder = Remainder [Double] deriving (Eq, Show)

-- | A reconstruction tolerance.
type Eps = Double

-- | The continuous tail's quantiser resolution (model only; the real tail is a
-- learned continuous output).
tailScale :: Int
tailScale = 16

-- | The worst-case continuous-tail reconstruction error: half a quantiser step.
eps :: Eps
eps = 1 / (2 * fromIntegral tailScale)

-- | The maximum channel count of the held continuous remainder (bounds the
-- retained-for-backward memory the audit flagged).
cTail :: Int
cTail = 4

-- | The pinned remainder channel count at the @256³@ rung (kept tiny).
remainderChannels :: Int
remainderChannels = 1

-- | The exact-integer surfaced part of a continuous signal (floor).
surfacedOf :: [Double] -> Surfaced
surfacedOf = Surfaced . map floor

-- | The fractional residual the surfaced floor leaves behind (each in @[0,1)@).
residualOf :: [Double] -> [Double]
residualOf ts = let Surfaced xs = surfacedOf ts
                in zipWith (\t x -> t - fromIntegral x) ts xs

-- | The lossy continuous-tail codec (uniform @1\/tailScale@ grid) — the concrete
-- stand-in for the learned FlowAR tail, lossy by at most 'eps'.
quantizeTail :: Double -> Double
quantizeTail x =
  fromIntegral (round (x * fromIntegral tailScale) :: Int) / fromIntegral tailScale

-- | The continuous remainder of a signal: the quantised residual.
tailOf :: [Double] -> Remainder
tailOf = Remainder . map quantizeTail . residualOf

-- | Reconstruct from BOTH layers: integer surfaced + continuous tail.
reconstruct :: Surfaced -> Remainder -> [Double]
reconstruct (Surfaced xs) (Remainder rs) = zipWith (\x r -> fromIntegral x + r) xs rs

-- | Reconstruct from the surfaced layer ALONE (remainder dropped) — what you get if
-- you wrongly claim the surfaced rung is lossless on its own.
dropRemainder :: Surfaced -> [Double]
dropRemainder (Surfaced xs) = map fromIntegral xs

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.RemainderTail)
-- ============================================================================

-- | The surfaced layer is EXACT on the integer grid: an all-integer signal
-- reconstructs bit-for-bit (the reversible-rung guarantee).
lawSurfacedExact :: [Int] -> Bool
lawSurfacedExact xs =
  let ts = map fromIntegral xs
  in reconstruct (surfacedOf ts) (tailOf ts) == ts

-- | The continuous remainder reconstructs WITHIN 'eps' (never exactly, in general).
lawTailWithinEps :: [Double] -> Bool
lawTailWithinEps ts =
  all (\d -> abs d <= eps + 1e-9)
      (zipWith (-) (reconstruct (surfacedOf ts) (tailOf ts)) ts)

-- | …and is provably NOT bit-exact: a witness whose residual is off the quantiser
-- grid reconstructs to a different value (so "lossless by construction" is false for
-- the tail layer).
lawTailNotExactWitness :: Bool
lawTailNotExactWitness =
  let ts = [0.3]
  in reconstruct (surfacedOf ts) (tailOf ts) /= ts

-- | THE honest B1 statement: losslessness NEEDS the remainder. With the tail the
-- error is within 'eps'; dropping it is strictly worse than 'eps' (the remainder
-- carries real information that must be retained).
lawLosslessNeedsRemainder :: Bool
lawLosslessNeedsRemainder =
  let ts       = [0.5]
      withR    = maxErr (reconstruct (surfacedOf ts) (tailOf ts)) ts
      withoutR = maxErr (dropRemainder (surfacedOf ts))           ts
  in withR <= eps + 1e-9 && withoutR > eps
  where maxErr a b = maximum (map abs (zipWith (-) a b))

-- | A node in the generation plan: the @i@-th surfaced next-scale token, or the
-- one-shot continuous tail.
data GenNode = SurfacedTok Int | TailShot deriving (Eq, Show)

-- | The autoregressive dependencies of a node in an @n@-surfaced-token plan: a
-- surfaced token conditions on all COARSER surfaced tokens (a causal prefix); the
-- tail conditions on the whole surfaced rung but is emitted ONCE — it introduces no
-- edge INTO itself or any other tail token.
genDeps :: Int -> GenNode -> [GenNode]
genDeps _ (SurfacedTok i) = [ SurfacedTok j | j <- [0 .. i - 1] ]
genDeps n TailShot        = [ SurfacedTok j | j <- [0 .. n - 1] ]

-- | The tail is NOT autoregressed: in a plan of @n@ surfaced tokens, NO node lists
-- the tail among its AR dependencies, and the tail has no self/tail-to-tail edge.
-- This tests the real 'genDeps' structure — it FAILS if any node ever depended on
-- 'TailShot' (unlike the previous @const []@ tautology, which could not fail).
lawTailNotAutoregressed :: Int -> Bool
lawTailNotAutoregressed n =
  n < 0
    || let nodes = map SurfacedTok [0 .. n - 1] ++ [TailShot]
       in all (\node -> TailShot `notElem` genDeps n node) nodes
          && TailShot `notElem` genDeps n TailShot

-- | The held remainder channel count is bounded (so retained-for-backward bytes stay
-- small): @1 ≤ remainderChannels ≤ cTail@.
lawRemainderChannelsBounded :: Bool
lawRemainderChannelsBounded = remainderChannels >= 1 && remainderChannels <= cTail
