{- |
Module      : SixFour.Spec.ColorMomentum
Description : COLOR-TIME HAS MASS, AND IT IS IN FLUX — the kinematics of the octant grading, discovered in GHCi (2026-07-06) and pinned here: MASS is the reversal-even coarse band (@bandOf b []@ — exactly what K keeps), MOMENTUM is the reversal-odd t-band (@−bandOf b [AxT] = Σ_{t=1} − Σ_{t=0}@, the mass-weighted velocity of the block — exactly what K kills and a section S must invent), and the whole 1+3+3+1 grading splits by the ARROW OF TIME: a band negates under time reversal iff it contains the t axis ('lawGradingSplitsByTheArrow', the numerically-discovered table made law). FLUX is the transport side: the per-tick 'SixFour.Spec.V21Field.paletteW1' is the 1-D Wasserstein cost = the minimal ∫|mass·displacement| of colour through value space — the impulse between frames — and it satisfies the triangle recursion 'lawFluxTriangleRecursion' (net flux over a window never exceeds the summed per-tick flux: the burst's flux telescopes, the recursion of the ladder in the transport metric).

== The S/K/I reading (why momentum is the gene's cargo)

  * K (pool) preserves mass EXACTLY ('lawKPreservesMassKillsMomentum': a pure
    momentum perturbation — +d on the far-t face, −d on the near-t face —
    changes the momentum band by 8d and the mass band by ZERO). Pooling
    averages motion away ("SixFour.Spec.ColorTime" @lawMotionAverageInHull@ is
    the measure face; this is the algebra face).
  * S must therefore INVENT momentum: the reversal-odd content lives in the
    kernel of K, and "SixFour.Spec.AxisSKI" @lawZeroSectionIsArrowBlind@
    already proved the zero section cannot express the arrow — the arrow
    enters synthesis exactly and only through the learned temporal gene.
    Momentum is WHAT the temporal gene carries.
  * I moves it losslessly (the lift is exact; both parities survive).

Discovered-then-pinned: the GHCi session computed the band table of
@blockFromList [3,1,4,1,5,9,2,6]@ and its t-reversal — mass 31/31, t-band
−3/+3, every t-containing band negated, every space-only band invariant —
and @momentumOf@ matched @Σ_{t=1} − Σ_{t=0}@ exactly (block lanes are
t-fastest: bit 0 = t, bit 1 = y, bit 2 = x). GHC-boot-only; additive.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.ColorMomentum
  ( -- * Mass, momentum, reversal
    massOf
  , momentumOf
  , timeReverse
    -- * Laws
  , lawMassIsReversalEven
  , lawMomentumIsReversalOdd
  , lawMomentumIsTheTBand
  , lawGradingSplitsByTheArrow
  , lawKPreservesMassKillsMomentum
  , lawFluxChargesMassTimesDistance
  , lawFluxTriangleRecursion
  ) where

import SixFour.Spec.OctantViews (Axis (..), axisSubsets, bandOf, blockFromList)
import SixFour.Spec.V21Field (paletteW1)

-- | The MASS of a 2×2×2 block: the reversal-even coarse band (the DC, what K
-- keeps; the photon-count face of "mass weights certainty").
massOf :: [Integer] -> Integer
massOf cells = bandOf (blockFromList (pad cells)) []

-- | The MOMENTUM of a block: @Σ_{t=1} − Σ_{t=0}@ — mass-weighted velocity
-- across the block's own colour-time step. Equals the NEGATED t-band of the
-- Walsh grading ('lawMomentumIsTheTBand'); lanes are t-fastest (bit 0 = t).
momentumOf :: [Integer] -> Integer
momentumOf cells =
  let c = pad cells
  in sum [ c !! i | i <- [1, 3, 5, 7] ] - sum [ c !! i | i <- [0, 2, 4, 6] ]

-- | Time reversal of a block: swap within every t-pair (bit 0).
timeReverse :: [Integer] -> [Integer]
timeReverse cells =
  let c = pad cells
  in [ c !! (i + 1 - 2 * (i `mod` 2)) | i <- [0 .. 7] ]

-- | Total (defensive) pad to exactly 8 lanes.
pad :: [Integer] -> [Integer]
pad cells = take 8 (cells ++ repeat 0)

-- | MASS IS REVERSAL-EVEN: running the block backwards changes no mass.
lawMassIsReversalEven :: [Integer] -> Bool
lawMassIsReversalEven cells = massOf (timeReverse cells) == massOf cells

-- | MOMENTUM IS REVERSAL-ODD: running the block backwards negates momentum —
-- the algebraic signature of a velocity.
lawMomentumIsReversalOdd :: [Integer] -> Bool
lawMomentumIsReversalOdd cells =
  momentumOf (timeReverse cells) == negate (momentumOf cells)

-- | Momentum IS the (negated) t-band of the octant grading: the kinematic
-- quantity and the Walsh band are the same integer.
lawMomentumIsTheTBand :: [Integer] -> Bool
lawMomentumIsTheTBand cells =
  momentumOf cells == negate (bandOf (blockFromList (pad cells)) [AxT])

-- | THE GRADING SPLITS BY THE ARROW: under time reversal every band NEGATES
-- iff it contains the t axis and is INVARIANT otherwise — the reversal-even
-- half (mass + spatial structure) is what K keeps; the reversal-odd half
-- (momentum + its shears) is what only a learned S can put back.
lawGradingSplitsByTheArrow :: [Integer] -> Bool
lawGradingSplitsByTheArrow cells =
  let b = blockFromList (pad cells)
      r = blockFromList (timeReverse cells)
  in and [ bandOf r s == (if AxT `elem` s then negate else id) (bandOf b s)
         | s <- axisSubsets ]

-- | K PRESERVES MASS AND KILLS MOMENTUM: a pure momentum kick (+d on the
-- far-t face, −d on the near-t face) moves the momentum band by exactly 8d
-- and the mass band by exactly ZERO — momentum lives in the kernel of the
-- surjection, so pooling cannot see it and sections must choose it.
lawKPreservesMassKillsMomentum :: [Integer] -> Integer -> Bool
lawKPreservesMassKillsMomentum cells d =
  let c = pad cells
      kicked = [ v + (if i `mod` 2 == 1 then d else negate d)
               | (i, v) <- zip [0 :: Int ..] c ]
  in massOf kicked == massOf c
       && momentumOf kicked == momentumOf c + 8 * d

-- | FLUX CHARGES MASS × DISTANCE: one palette slot drifting @d@ value levels
-- in one channel costs exactly @d@ in 'paletteW1' — the per-tick W1 is the
-- impulse of colour mass through value space, not a difference of labels.
lawFluxChargesMassTimesDistance :: Int -> Int -> Bool
lawFluxChargesMassTimesDistance dRaw lRaw =
  let levels = 8 + abs lRaw `mod` 249          -- 8..256
      d = abs dRaw `mod` (levels - 1)          -- a legal drift
      p1 = [0, 0, 0]                           -- one slot at the origin
      p2 = [d, 0, 0]                           -- drifted d levels in channel 0
  in paletteW1 levels p1 p2 == d

-- | THE FLUX RECURSION (triangle): over any three frames the NET flux never
-- exceeds the summed per-tick flux — so summed W1 over the burst is a true
-- path length and telescoping it down the ladder can only shorten it. The
-- recursion of the weave, measured in transported colour mass.
lawFluxTriangleRecursion :: Int -> Int -> Int -> Bool
lawFluxTriangleRecursion aRaw bRaw cRaw =
  let levels = 16
      slot v = [ abs v `mod` levels, (abs v * 7) `mod` levels, (abs v * 13) `mod` levels ]
      pa = slot aRaw
      pb = slot bRaw
      pc = slot cRaw
  in paletteW1 levels pa pc <= paletteW1 levels pa pb + paletteW1 levels pb pc
