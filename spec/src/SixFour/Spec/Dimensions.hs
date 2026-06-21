{- |
Module      : SixFour.Spec.Dimensions
Description : The RULE OF DIMENSIONS — a traceable ledger of every axis the pipeline manipulates, with a conservation invariant.

The user's first rule: every manipulated dimension must be mapped and kept
traceable. This module is the accounting oracle. Two guarantees:

  * 'lawDimConserved' — at every successive-refinement cut, @surfaced dims +
    held dims == input dims@, exactly (no dimension silently dropped); delegates
    to "SixFour.Spec.SuccessiveRefinement" + "SixFour.Spec.OctreeGenome".
  * 'lawEveryAxisClassified' — every axis the pipeline touches is classified in
    the 'ledger' (Surfaced vs Held), so a dimension can be traced from raw capture
    to surfaced cell.

The ledger (the human-readable rule): @L@ (≅ t) and @t@ are SURFACED (the cheap,
universal balance axes the L white-balance/dynamic-range operator drives); @a@,@b@
(the look, formerly the A/B candidates) and the spatial @x@,@y@ are HELD as the
net's latent remainder.

GHC-boot-only. Laws QuickCheck'd in @Properties.Dimensions@.
-}
module SixFour.Spec.Dimensions
  ( -- * The axis ledger
    Axis(..)
  , AxisRole(..)
  , ledger
  , roleOf
    -- * Laws (QuickCheck'd in @Properties.Dimensions@)
  , lawDimConserved
  , lawEveryAxisClassified
  ) where

import SixFour.Spec.SuccessiveRefinement (split, surfaced, remainderRate)
import SixFour.Spec.OctreeGenome         (octreeLeafCount)

-- | The axes the pipeline manipulates: colour @L,a,b@ and position @x,y,t@,
-- dual under @x≅a, y≅b, t≅L@ ("SixFour.Spec.XYTLabDuality").
data Axis = AxL | AxA | AxB | AxX | AxY | AxT
  deriving (Eq, Show, Enum, Bounded)

-- | Whether an axis is shown (surfaced base) or kept latent (held remainder).
data AxisRole = Surfaced | Held
  deriving (Eq, Show)

-- | The rule-of-dimensions ledger: every axis and its role.
ledger :: [(Axis, AxisRole)]
ledger =
  [ (AxL, Surfaced)   -- lightness: surfaced base, refinable for free
  , (AxT, Surfaced)   -- time: surfaced loop (held temporal super-res is small)
  , (AxA, Held)       -- chroma a: held predictive band (the look; was A/B)
  , (AxB, Held)       -- chroma b: held predictive band
  , (AxX, Held)       -- spatial: held detail band
  , (AxY, Held)       -- spatial: held detail band
  ]

-- | The role of an axis (partial only on an unclassified axis, which
-- 'lawEveryAxisClassified' forbids).
roleOf :: Axis -> Maybe AxisRole
roleOf ax = lookup ax ledger

-- | Dimension conservation: surfaced dims + held dims == input dims, exactly, at
-- every valid cut (the rule of dimensions made checkable).
lawDimConserved :: Int -> Int -> [Int] -> Bool
lawDimConserved k d cube =
  not (d >= 0 && k >= 0 && k <= d && length cube == octreeLeafCount d) ||
    let s = split k d cube
    in length (surfaced s) + remainderRate s == octreeLeafCount d

-- | Every manipulated axis is classified in the ledger (traceability).
lawEveryAxisClassified :: Bool
lawEveryAxisClassified = all (\ax -> ax `elem` map fst ledger) [minBound .. maxBound]
