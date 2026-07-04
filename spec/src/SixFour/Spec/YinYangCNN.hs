{- |
Module      : SixFour.Spec.YinYangCNN
Description : THE YIN-YANG INFERENCE-LEARNING CNN — the architecture derived from the landed algebra, its structural invariants gated here (full design: docs/YINYANG-CNN-DESIGN.md). YIN (inference, the K-direction) is FROZEN EXACT: the encoder is not learned because K and I are canonical ("SixFour.Spec.MixSKI") — 'lawEncoderIsAllOnesConv' proves the CNN-language encoder (a stride-2 all-ones convolution) IS the transitive sums carrier, byte-for-byte, zero parameters. YANG (learning, the S-direction) is ALL the parameters: per-axis section heads whose OUTPUT SIZES are forced by the algebra — 'lawStagedExpansionCountsSumToSeven': expanding one axis at a time, the staged detail counts are exactly {1, 2, 4} in every axis order, summing to 7 = rank A₇ ("SixFour.Spec.RootLatticeDetail") — the head widths are theorems, not hyperparameters.

WEIGHT TYING IS SYMMETRIZATION, INTEGRALLY ('lawSwapTyingBySymmetrization'):
the unordered x:y pair ("SixFour.Spec.OctantViews" swap law) demands the
S_x and S_y heads share weights up to the swap conjugation; the tied head
H' = H + π∘H∘σ commutes with the swap EXACTLY over ℤ (no averaging, no /2 —
the sum symmetrizes), so equivariance is imposed by integer construction.
Time is NOT tied: the t-bands are reversal-ODD ("SixFour.Spec.AxisSKI"
'lawZeroSectionIsArrowBlind'), so S_t is a different head by algebra, and
time-reversal augmentation must NEGATE the t-containing band targets
(the landed lawTimeReversalFlipsTBands is the augmentation rule).

THE REST OF THE ARCHITECTURE IS ALREADY LANDED, cited not re-proven:
color enters in the ROOT CHART (L, α₁, α₂) for integral S₃-equivariance
("SixFour.Spec.OpponentDerivation" — the stored chart would halve the
symmetry); the training targets are the graded bands = mixed derivatives
("SixFour.Spec.KinematicLadder"); the halting floor is the certified order
("SixFour.Spec.KinematicHaltPrior"); losses are W-weighted and mass-weighted
("SixFour.Spec.PaletteKinetics", shot noise as the physics note); the
tri-scale budget is 9/8 of the finest ("SixFour.Spec.TriScaleTraining");
the mix head proposes the depth-vector field and is trained on user picks
("SixFour.Spec.ChoiceTraining", "SixFour.Spec.CubeBrush"); and the whole
loop trains per capture on free coarse=pool(fine) labels — the yin-yang
verdict of the training-occurs proof, now with a wiring diagram.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.YinYangCNN
  ( -- * The frozen yin path
    allOnesConv2
    -- * The yang head sizing
  , stagedDetailCounts
    -- * Symmetrized tying
  , tieBySwap
    -- * Laws
  , lawEncoderIsAllOnesConv
  , lawStagedExpansionCountsSumToSeven
  , lawSwapTyingBySymmetrization
  ) where

import Data.List (sort)

import SixFour.Spec.OctantViews
  ( Axis (..), corners, blockFromList, axisSubsets )
import SixFour.Spec.RootLatticeDetail (numDetailBands)

-- | The CNN-language encoder: a VALID stride-2 convolution with the all-ones
-- 2×2×2 kernel over an 8³ volume (t-major flat list) — one output voxel per
-- block, the block SUM. Zero parameters by construction.
allOnesConv2 :: [Integer] -> [Integer]
allOnesConv2 xs =
  [ sum [ at (2 * x + dx) (2 * y + dy) (2 * t + dt)
        | dt <- [0, 1], dy <- [0, 1], dx <- [0, 1] ]
  | t <- [0 .. 3], y <- [0 .. 3], x <- [0 .. 3] ]
  where
    padded = take 512 (xs ++ repeat 0)
    at x y t = padded !! ((t * 8 + y) * 8 + x)

-- | The staged per-axis detail counts for one full 2×2×2 up-rung, expanding
-- the axes one at a time in the given order: each stage's new coefficients
-- equal the current cell count, which then doubles.
stagedDetailCounts :: [Axis] -> [Int]
stagedDetailCounts = go 1
  where
    go _ [] = []
    go cells (_ : rest) = cells : go (2 * cells) rest

-- | Symmetrize a linear head over the x↔y swap: H' = H + π∘H∘σ, where σ
-- permutes the block's corners by the swap and π relabels the band outputs
-- ({x}↔{y}, {x,t}↔{y,t}). Integer throughout — the sum symmetrizes without
-- division.
tieBySwap :: ([Integer] -> [Integer]) -> ([Integer] -> [Integer])
tieBySwap h inp = zipWith (+) (h inp) (permuteBands (h (swapCorners inp)))
  where
    swapCorners xs =
      [ blockFromList xs (y, x, t) | (x, y, t) <- corners ]
    permuteBands out =
      [ out !! bandIndex (map swapAxis s) | s <- axisSubsets ]
    swapAxis AxX = AxY
    swapAxis AxY = AxX
    swapAxis AxT = AxT
    bandIndex s = head [ i | (i, s') <- zip [0 ..] axisSubsets
                           , sort (map fromEnum s') == sort (map fromEnum s) ]

-- | LAW (the yin path is frozen exact): the stride-2 all-ones convolution
-- equals direct 2×2×2 block summation — the CNN encoder IS the transitive
-- sums carrier. Zero learnable parameters in the entire inference direction;
-- K needs no training because K is a theorem.
lawEncoderIsAllOnesConv :: [Integer] -> Bool
lawEncoderIsAllOnesConv xs =
  allOnesConv2 xs == direct
  where
    padded = take 512 (xs ++ repeat 0)
    at x y t = padded !! ((t * 8 + y) * 8 + x)
    direct = [ at (2*x) (2*y) (2*t) + at (2*x+1) (2*y) (2*t)
                 + at (2*x) (2*y+1) (2*t) + at (2*x+1) (2*y+1) (2*t)
                 + at (2*x) (2*y) (2*t+1) + at (2*x+1) (2*y) (2*t+1)
                 + at (2*x) (2*y+1) (2*t+1) + at (2*x+1) (2*y+1) (2*t+1)
             | t <- [0 .. 3], y <- [0 .. 3], x <- [0 .. 3] ]

-- | LAW (head widths are theorems): for EVERY axis order, the staged detail
-- counts are the multiset {1, 2, 4} and sum to 7 = rank A₇ =
-- 'numDetailBands' 8. The per-axis section heads S_first, S_second, S_third
-- have output widths 1, 2, 4 per block — forced, not tuned.
lawStagedExpansionCountsSumToSeven :: Bool
lawStagedExpansionCountsSumToSeven =
  all ok orders
  where
    orders = [ [a, b, c] | a <- axes, b <- axes, c <- axes
             , a /= b, b /= c, a /= c ]
    axes = [AxX, AxY, AxT]
    ok o = sum (stagedDetailCounts o) == numDetailBands 8
             && sort (stagedDetailCounts o) == [1, 2, 4]

-- | LAW (tying is integer symmetrization): for ANY linear head H (built from
-- generated coefficients), the tied head H' = H + π∘H∘σ commutes with the
-- x↔y swap exactly: H'(σ·block) == π(H'(block)) over ℤ. Equivariance imposed
-- by construction; no averaging, no floats, no approximation.
lawSwapTyingBySymmetrization :: [Integer] -> [Integer] -> Bool
lawSwapTyingBySymmetrization coefs xs =
  tied (swapped xs) == permuted (tied xs)
  where
    -- an arbitrary linear head: 8 outputs, each a dot of the 8 corner values
    cs = take 64 (coefs ++ repeat 1)
    h inp = [ sum (zipWith (*) (take 8 (drop (8 * o) cs)) (take 8 inp))
            | o <- [0 .. 7] ]
    tied = tieBySwap h
    swapped inp = [ blockFromList inp (y, x, t) | (x, y, t) <- corners ]
    permuted out =
      [ out !! bandIndex (map swapAxis s) | s <- axisSubsets ]
    swapAxis AxX = AxY
    swapAxis AxY = AxX
    swapAxis AxT = AxT
    bandIndex s = head [ i | (i, s') <- zip [0 ..] axisSubsets
                           , sort (map fromEnum s') == sort (map fromEnum s) ]
