{- |
Module      : SixFour.Spec.PaintOrderPrior
Description : The user's paint/nudge FIRST-TOUCH order seeds the PonderNet halting prior on the coarse-to-fine A7 rung ladder: the earliest-touched cell gets the LOWEST halt rate, hence the deepest read, hence the most decode packets. The keystone is a PERMUTATION-PAIR property, so no magnitude-only policy (one that reads the CellBudget but discards the order) can satisfy it.

Today the capture surface records a 'CellBudget' magnitude but discards WHEN each
cell was first touched, so it cannot express "commit compute where the user looked
first". This module adds the @TouchOrder@ carrier and makes the deployed packet
depth a monotone function of touch rank. Paint order enters purely on the PRIOR
side (it reshapes the KL target @λ_p@, not a logit), the cleanest injection point.

The keystone is stated over a PERMUTATION of the touch order at FIXED 'CellBudget'.
Because @[a,b]@ and @[b,a]@ carry identical magnitudes but must yield SWAPPED depths,
no function of the magnitude field alone can satisfy it: the magnitude-only policy is
structurally falsified ('lawPaintOrderTracksRankUnderPermutation' is parameterised by
the policy so the wrong one is exhibited failing). This forbids both the de-facto
single-global-@λ_p@ policy and any magnitude-only reading.

== The rung depth IS the packet count IS the halting depth

In the S\/K\/I reading (@I@ = the free reversible coarse floor read, @K@ = pool,
@S@ = weighted invent), reading @k@ rungs above the floor spends @k@ K\/S packets.
So @packetsAboveFloor = readDepth − 1@, and paint order deciding read depth is paint
order deciding how many decode packets a region earns (see "SixFour.Spec.PacketEconomy").
An untouched cell halts at the floor (@λ_p = 1.0@, 0 packets), the free @I@ read.

== Discrete geometry + algebraic number theory

  * The per-cell depth is an INTEGER schedule of touch rank on the A7 rung ladder:
    the ceiling is @branching 2 3 − 1 = 7@ (8 octant children, "1 coarse + 7 detail"),
    and @packetsAboveFloor = max 0 (7 − rank)@. Strict while both ranks are below the
    @paletteDepth@ = 8 ceiling, then an order-preserving (never-inverting) tie beyond,
    so realistic 16^3 sessions that touch more than 8 cells stay consistent.
  * Permuting the touch order REALLOCATES packets but never inflates the total: the
    rank multiset is permutation-invariant ('lawPacketBudgetConserved'), an integer
    conservation law, so paint order is a redistribution of a fixed compute budget.
  * @λ_p@ and @expectedReadDepth@ are the training-time PRIOR (Doubles), fed to the
    real 'geometricPrior' \/ 'expectedSteps'; the DEPLOYED schedule is the integer
    rank function, keeping the byte-exact floor off the float seam.
-}
module SixFour.Spec.PaintOrderPrior
  ( -- * Carriers
    CellIx
  , TouchOrder
  , Perm
  , ceilingRank
    -- * Rank, permutation, and the deployed integer packet schedule
  , rankOf
  , applyPerm
  , rankUnder
  , touched
  , cellTouchedInBudget
  , packetsAboveFloor
    -- * The training-time halting prior (Doubles)
  , haltSeed
  , expectedReadDepth
    -- * Keystone (permutation-pair) and supporting laws
  , lawPaintOrderTracksRankUnderPermutation
  , lawEarlierTouchReadsDeeper
  , lawPacketBudgetConserved
  , lawUnpaintedHaltsAtFloor
  ) where

import Data.List (elemIndex, sort)

import SixFour.Spec.PonderHaltDistribution (geometricPrior, expectedSteps)
import SixFour.Spec.CellNudge              (CellBudget)
import SixFour.Spec.PonderBudget           (budgetToMask)
import SixFour.Spec.ScaleFiltration        (branching)
import SixFour.Spec.PairTree               (paletteDepth)

-- | A cell index into the paint grid.
type CellIx = Int

-- | First-touch order, earliest first.
type TouchOrder = [CellIx]

-- | A permutation of list positions.
type Perm = [Int]

-- | The A7 rung ceiling: 8 octant children ⇒ 7 detail bands above the coarse floor.
ceilingRank :: Int
ceilingRank = branching 2 3 - 1

-- | Rank of a cell in a touch order (position of first touch; 0 = earliest).
rankOf :: TouchOrder -> CellIx -> Maybe Int
rankOf order c = elemIndex c order

-- | Apply a permutation to a touch order (identity if it is not a valid permutation).
applyPerm :: Perm -> TouchOrder -> TouchOrder
applyPerm pperm order
  | sort pperm == [0 .. length order - 1] = map (order !!) pperm
  | otherwise                             = order

-- | Rank of a cell after permuting the order.
rankUnder :: Perm -> TouchOrder -> CellIx -> Maybe Int
rankUnder pperm order c = rankOf (applyPerm pperm order) c

-- | The cells that were actually touched.
touched :: TouchOrder -> [CellIx]
touched = id

-- | Does the cell carry any painted budget? Uses the REAL 'budgetToMask' on the cell row.
cellTouchedInBudget :: CellBudget -> CellIx -> Bool
cellTouchedInBudget bud c
  | c < 0 || c >= length bud = False
  | otherwise                = or (budgetToMask (bud !! c))

-- | The DEPLOYED integer packet schedule above the floor: earlier touch ⇒ more packets,
-- strict while rank < 8, order-preserving tie beyond; untouched or zero-budget ⇒ 0 (floor).
packetsAboveFloor :: CellBudget -> TouchOrder -> CellIx -> Int
packetsAboveFloor bud order c =
  case rankOf order c of
    Nothing -> 0
    Just r
      | not (cellTouchedInBudget bud c) -> 0
      | otherwise                       -> max 0 (ceilingRank - r)

-- | Per-cell halt seed (training-time PRIOR, a Double): earlier rank ⇒ lower @λ_p@ ⇒
-- deeper expected read. Untouched ⇒ @λ_p = 1.0@ exactly (immediate halt at the floor).
haltSeed :: TouchOrder -> CellIx -> Double
haltSeed order c =
  case rankOf order c of
    Nothing -> 1.0
    Just r  -> clamp01 (0.15 + 0.10 * fromIntegral r)
  where clamp01 = max 0 . min 1

-- | Expected read depth from the real halting machinery (the KL-target prior).
expectedReadDepth :: TouchOrder -> CellIx -> Double
expectedReadDepth order c = expectedSteps (geometricPrior (haltSeed order c) paletteDepth)

-- | ★ KEYSTONE: under a permutation of the touch order at FIXED CellBudget, each cell's
-- deployed packet depth tracks its rank (smaller rank ⇒ ≥ packets; strict while both
-- ranks < 8, order-preserving tie beyond). Parameterised over the policy so a
-- magnitude-only policy is provably falsified.
lawPaintOrderTracksRankUnderPermutation
  :: (CellBudget -> TouchOrder -> CellIx -> Int)
  -> TouchOrder -> Perm -> CellBudget -> Bool
lawPaintOrderTracksRankUnderPermutation policy order pperm bud =
  and [ monotone c c' | c <- touched order, c' <- touched order ]
  where
    order' = applyPerm pperm order
    monotone c c' =
      case (rankUnder pperm order c, rankUnder pperm order c') of
        (Just rc, Just rc') ->
          let pc  = policy bud order' c
              pc' = policy bud order' c'
          in if rc <= rc'
               then if rc < paletteDepth && rc' < paletteDepth && rc < rc'
                      then pc > pc'
                      else pc >= pc'
               else True
        _ -> True

-- | Earlier touch ⇒ ≥ expected read depth, composing with the real @lawLowerHaltRefinesMore@.
lawEarlierTouchReadsDeeper :: TouchOrder -> Bool
lawEarlierTouchReadsDeeper order =
  and [ expectedReadDepth order (order !! i) >= expectedReadDepth order (order !! j)
      | i <- [0 .. length order - 1], j <- [0 .. length order - 1], i <= j ]

-- | Permuting the touch order REALLOCATES packets but never inflates the total (the
-- rank multiset is permutation-invariant).
lawPacketBudgetConserved :: TouchOrder -> Perm -> CellBudget -> Bool
lawPacketBudgetConserved order pperm bud =
  let order' = applyPerm pperm order
      tot o  = sum [ packetsAboveFloor bud o c | c <- touched order ]
  in tot order == tot order'

-- | An untouched cell halts at the floor: @λ_p = 1.0@ exactly and 0 packets.
lawUnpaintedHaltsAtFloor :: TouchOrder -> CellIx -> CellBudget -> Bool
lawUnpaintedHaltsAtFloor order c bud =
  (c `elem` order) || (packetsAboveFloor bud order c == 0 && haltSeed order c == 1.0)
