{- |
Module      : SixFour.Spec.CrossEncoderDistance
Description : The DISTANCE between the two semantics — how far the construction encoder A (a fixed-BUDGET palette) sits from the perceptual encoder B (the raw (L,a,b,x,y,t) cloud), measured in the relational metric @d6@ and DECOMPOSED per axis. This is the quantitative heart of "explore the distance between L,a,b,x,y,t as they relate to the GIF".

"SixFour.Spec.GifDualView" proved the two encoders are one object at UNBOUNDED palette
budget (lossless). A real GIF palette is capped (the shipped @K = 256@). When the object has
more distinct colours than the budget, Encoder A must MERGE colours — and the perceptual
encoder B sees the gap. This module measures it.

  * 'palettizeBudget' — the lossy retraction @rho@: keep the first @K@ distinct colours, map
    every other voxel to the NEAREST kept colour. (Exact when distinct colours @<= K@.)
  * 'constructionDistortion' — the inter-semantic distance: the @d6@-sum between the
    perceptual cloud of the budget-rebuilt cube and the perceptual cloud of the original. It
    is @0@ iff the GIF is palettizable within budget.
  * 'axisDistortion' — that gap PROJECTED onto a single "SixFour.Spec.Dim6" axis. Because
    the rebuild keeps every voxel's POSITION, the @x,y,t@ axes contribute @0@ and the whole
    distance lands on @L,a,b@ — the per-axis ledger of WHERE the two semantics diverge.
  * 'lawPerAxisDistortionSumsToTotal' — the six axis-distortions SUM to the total @d6@
    distortion (the decomposition is exact, no double-counting).
  * 'lawDistortionZeroIffLossless' — distortion @== 0@ exactly when distinct colours @<= K@.
  * 'lawDistortionIsPseudometric' — the cloud distance underneath is a genuine pseudometric
    (non-negative, symmetric, triangle), delegating the "SixFour.Spec.RelationalMemory" @d6@
    metric laws pointwise.

Additive: reuses "SixFour.Spec.GifDualView", "SixFour.Spec.PerceptualEncoder",
"SixFour.Spec.RelationalMemory" @d6@, "SixFour.Spec.RelationalResidual" @axisVal@,
"SixFour.Spec.Dim6". GHC-boot-only. Laws QuickCheck'd in "Properties.CrossEncoderDistance".
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.CrossEncoderDistance
  ( -- * The lossy retraction (fixed palette budget)
    palettizeBudget
  , isPalettizable
    -- * The inter-semantic distance and its per-axis decomposition
  , cloudDistance
  , constructionDistortion
  , axisDistortion
    -- * Laws (QuickCheck'd in @Properties.CrossEncoderDistance@)
  , lawPerAxisDistortionSumsToTotal
  , lawDistortionZeroIffLossless
  , lawDistortionIsPseudometric
  ) where

import Data.List  (nub, minimumBy)
import Data.Ord   (comparing)

import SixFour.Spec.Dim6                (Dim6(..), allDims)
import SixFour.Spec.SameObjectInvariance (Cube(..))
import SixFour.Spec.ConstructionEncoder  (Construction(..), QColour, buildPixels)
import SixFour.Spec.GifDualView          (GifObject(..), validGifObject)
import SixFour.Spec.PerceptualEncoder    (perceptualEmbed)
import SixFour.Spec.RelationalResidual   (P6, axisVal)
import SixFour.Spec.RelationalMemory     (d6)

-- | Colour-only L1 distance between two Q16 colours (the merge metric).
colourL1 :: QColour -> QColour -> Int
colourL1 (l,a,b) (l',a',b') = abs (l - l') + abs (a - a') + abs (b - b')

-- | The GIF is palettizable within budget @k@ when it has at most @k@ distinct colours.
isPalettizable :: Int -> GifObject -> Bool
isPalettizable k (GifObject _ (Cube cl ca cb)) =
  length (nub (zip3 cl ca cb)) <= k

-- | The lossy retraction @rho@: palettize within a budget of @k@ colours. Keep the first
-- @k@ distinct colours as the palette; map every voxel to its NEAREST kept colour (ties to
-- the earliest). Exact (lossless) precisely when the object is 'isPalettizable' at @k@.
palettizeBudget :: Int -> GifObject -> Construction
palettizeBudget k (GifObject d (Cube cl ca cb)) =
  let cols    = zip3 cl ca cb
      pal     = take (max 1 k) (nub cols)
      nearest c = snd (minimumBy (comparing fst)
                        [ (colourL1 c p, i) | (i, p) <- zip [0 ..] pal ])
  in Construction d pal (map nearest cols)

-- | The distance between two equal-length perceptual clouds: the @d6@-sum voxel by voxel. A
-- pseudometric (it inherits non-negativity, symmetry and the triangle inequality from @d6@).
cloudDistance :: [P6] -> [P6] -> Int
cloudDistance ps qs = sum (zipWith d6 ps qs)

-- | THE inter-semantic distance at budget @k@: how far Encoder A's budgeted reconstruction
-- sits from Encoder B's faithful cloud, in @d6@. Zero iff palettizable within budget.
constructionDistortion :: Int -> GifObject -> Int
constructionDistortion k g@(GifObject d _) =
  cloudDistance (perceptualEmbed d (buildPixels (palettizeBudget k g)))
                (perceptualEmbed d (goPixels g))

-- | The distortion PROJECTED onto a single axis: the per-voxel @|Δ|@ on that one
-- "SixFour.Spec.Dim6" coordinate, summed. Position axes contribute @0@ (the rebuild keeps
-- every voxel in place), so the gap lands entirely on @L,a,b@.
axisDistortion :: Dim6 -> Int -> GifObject -> Int
axisDistortion ax k g@(GifObject d _) =
  let rebuilt = perceptualEmbed d (buildPixels (palettizeBudget k g))
      orig    = perceptualEmbed d (goPixels g)
  in sum (zipWith (\p q -> abs (axisVal ax p - axisVal ax q)) rebuilt orig)

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.CrossEncoderDistance)
-- ============================================================================

-- | THE per-axis decomposition: the six axis-distortions SUM to the total @d6@ distortion —
-- the inter-semantic distance is exactly partitioned across @L,a,b,x,y,t@, with no
-- double-counting and nothing dropped. This is "the distance between L,a,b,x,y,t" made an
-- exact ledger. Teeth: a metric that double-counted (or an axis projection that overlapped)
-- would break the equality.
lawPerAxisDistortionSumsToTotal :: Int -> GifObject -> Bool
lawPerAxisDistortionSumsToTotal k g
  | not (validGifObject g) || k < 1 = True
  | otherwise =
      sum [ axisDistortion ax k g | ax <- allDims ] == constructionDistortion k g

-- | The distortion is @0@ EXACTLY when the GIF is palettizable within budget (distinct
-- colours @<= K@). One direction: a palettizable object reconstructs bit-exactly (every
-- colour kept), so the cloud distance is zero. The other: a non-palettizable object has a
-- dropped distinct colour merged to a DIFFERENT kept colour, so some voxel moves and the
-- distance is positive. Teeth: this is a genuine iff, not a one-sided bound.
lawDistortionZeroIffLossless :: Int -> GifObject -> Bool
lawDistortionZeroIffLossless k g
  | not (validGifObject g) || k < 1 = True
  | otherwise =
      (constructionDistortion k g == 0) == isPalettizable k g

-- | The cloud distance underneath is a genuine PSEUDOMETRIC: non-negative, symmetric, and
-- triangle-respecting on any three equal-length clouds — delegating the
-- "SixFour.Spec.RelationalMemory" @d6@ metric laws pointwise (a sum of metrics is a metric).
-- Zero between identical clouds. This is what licenses calling 'constructionDistortion' a
-- distance, not just a number.
lawDistortionIsPseudometric :: [P6] -> [P6] -> [P6] -> Bool
lawDistortionIsPseudometric ps qs rs =
  let n  = minimum [length ps, length qs, length rs]
      a  = take n ps; b = take n qs; c = take n rs
  in cloudDistance a b >= 0
     && cloudDistance a b == cloudDistance b a
     && cloudDistance a c <= cloudDistance a b + cloudDistance b c
     && cloudDistance a a == 0
