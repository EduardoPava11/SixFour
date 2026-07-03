{- |
Module      : SixFour.Spec.BudgetHead
Description : A gene is TWO-HEADED: its expression (the θ_up S-weights) plus an ADVISORY budget head that estimates a per-rung packet schedule. The advisory is SAFE because it only gates the @Maybe [Detail]@ fork of the decode (never @side@, @vol@, or a buffer length), so a wrong estimate lands on a coarser point of the SAME ladder, never off it; the floor is always reproducible. The learned float estimator is Tier-1 UNBUILT and is modelled here as a pure schedule.

The budget head lets a meta-controller split scarce decode-compute across competing
genes (see "SixFour.Spec.PacketEconomy") BEFORE committing a full decode. In V1 the
advisory is ADVISORY, not wire-enforced: it may only choose WHICH rungs attempt their
@S@ packet, and it is re-measured and capped locally. Honesty is priced by the
PonderNet ponder-cost objective at train time, not asserted on the wire.

The keystone has real teeth via an adversarial 'DecodeStrategy' family: only the
strategy that routes the estimate SOLELY through the detail @Maybe@ reproduces the
floor on a starved head; a strategy that reads the estimate OUTSIDE the fork (to
truncate the output or pre-allocate a buffer) fails to reproduce the floor, so the
hazard is IN-SPEC rather than lint-only ('lawOnlyMaybeForkIsFloorSafe'). The advisory
rides TAG-ADJACENT, excluded from the tag-identity bytes, so a nondeterministic
estimate cannot perturb dedup or the 'SixFour.Spec.GeneSimilarity' pullback
('lawBudgetAdvisoryDoesNotChangeTagIdentity').

== S, K, I

The budget head advises the @S@ schedule (which rungs invent detail); the @I@ floor
read is always free and always available, which is exactly what makes the advisory
safe: 'scheduleDetail' returns @Nothing@ (the pure @I@ expand) whenever no @S@ packet
is advised, so a starved or wrong head degrades to the floor, never to a fault.

== Discrete geometry + algebraic number theory

  * The schedule and cap are INTEGERS; @decodeWithBudgetCapped@ threads the cap so
    @spent ≤ cap@ for a lying head ('lawBudgetHeadBoundsActualPackets'), a byte-exact
    resource bound with no float.
  * The advisory is a swapMinor extension: @swapMajor@ is unchanged, so a budget-blind
    base extractor yields the identical @expressionSource@ ('lawBudgetHeadForwardCompatible'),
    keeping the just-landed wire codec intact.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.BudgetHead
  ( -- * The advisory budget head (learned estimator STUBBED as a schedule)
    BudgetHead(..)
  , defaultHead
  , starveHead
    -- * The reference decoder (advisory routes SOLELY through the detail Maybe)
  , scheduleDetail
  , decodeWithBudget
  , decodeWithBudgetCapped
  , spentCost
    -- * The tag-adjacent carrier
  , Augmented(..)
  , encodeWithBudget
  , extractBase
  , swapMajorOf
  , tagIdentityHash
    -- * The adversarial decode-strategy family
  , DecodeStrategy(..)
  , strategyFamily
  , readsEstimateOutsideMaybe
  , runStrategy
    -- * Laws
  , goldenStarvedHeadIsFloor
  , lawOnlyMaybeForkIsFloorSafe
  , lawBudgetHeadBoundsActualPackets
  , lawBudgetHeadForwardCompatible
  , lawBudgetAdvisoryDoesNotChangeTagIdentity
  ) where

import Data.Word (Word8)

import SixFour.Spec.SwapCarrier          (SwapPayload, normalizePayload, expressionSource, swapMajor, encodeSwapBlock)
import SixFour.Spec.SelfSimilarReconstruct (expandRungVolume)
import SixFour.Spec.OctreeCell           (Detail)

-- | The advisory budget head: a per-rung @S@-packet schedule. STUB for the Tier-1
-- learned float estimator; the pure carrier and safety laws do not depend on how it
-- is produced.
newtype BudgetHead = BudgetHead { bhSchedule :: [Int] } deriving (Eq, Show)

-- | A head advising one @S@ packet at rung 0.
defaultHead :: BudgetHead
defaultHead = BudgetHead [1]

-- | Starve a head to zero advised packets (forces the floor).
starveHead :: BudgetHead -> BudgetHead
starveHead _ = BudgetHead []

unitDetail :: Detail
unitDetail = (1,0,0,0,0,0,0)

-- | The advisory chooses ONLY the @Maybe [Detail]@ argument of 'expandRungVolume';
-- it never touches @side@ or @vol@. Starved (no positive packet) ⇒ @Nothing@ ⇒ floor.
scheduleDetail :: BudgetHead -> [Int] -> Maybe [Detail]
scheduleDetail bh vol
  | any (> 0) (bhSchedule bh) = Just (replicate (length vol) unitDetail)
  | otherwise                 = Nothing

-- | Reference decoder: routes the advisory SOLELY through the detail @Maybe@.
decodeWithBudget :: BudgetHead -> Int -> [Int] -> [Int]
decodeWithBudget bh side vol = expandRungVolume side vol (scheduleDetail bh vol)

-- | Capped decoder: the cap is THREADED so a lying/high estimate cannot unlock spend
-- beyond it. Returns (packets actually spent, output).
decodeWithBudgetCapped :: Int -> BudgetHead -> Int -> [Int] -> (Int, [Int])
decodeWithBudgetCapped cap bh side vol =
  let want  = length (filter (> 0) (bhSchedule bh))
      spend = max 0 (min cap want)
      mdet  = if spend > 0 then Just (replicate (length vol) unitDetail) else Nothing
  in (spend, expandRungVolume side vol mdet)

-- | Packets actually spent by a capped decode.
spentCost :: (Int, [Int]) -> Int
spentCost = fst

-- | A carrier with the advisory stored TAG-ADJACENT (excluded from the tag-identity bytes).
data Augmented = Augmented { apBase :: SwapPayload, apAdvisory :: [Int] }

-- | CORRECT encode: advisory stored tag-adjacent; the base payload is untouched.
encodeWithBudget :: BudgetHead -> SwapPayload -> Augmented
encodeWithBudget bh p = Augmented (normalizePayload p) (bhSchedule bh)

-- | Recover the base payload (a budget-blind extractor).
extractBase :: Augmented -> SwapPayload
extractBase = apBase

-- | The advisory is a swapMinor extension: @swapMajor@ is unchanged.
swapMajorOf :: Augmented -> Word8
swapMajorOf _ = swapMajor

-- | Tag identity = the canonical base wire bytes, which do NOT contain the advisory.
-- Two advisories over one base yield identical bytes.
tagIdentityHash :: Augmented -> [Word8]
tagIdentityHash a = encodeSwapBlock (apBase a)

-- | The adversarial decode-strategy family: one safe (Maybe-fork-only) and two hazards
-- (reading the estimate outside the fork to truncate or pre-allocate the output).
data DecodeStrategy = MaybeForkOnly | TruncateToEstimate | PreallocEstimate
  deriving (Eq, Show)

-- | The full adversarial family the keystone quantifies over.
strategyFamily :: [DecodeStrategy]
strategyFamily = [MaybeForkOnly, TruncateToEstimate, PreallocEstimate]

-- | Does the strategy read the estimate OUTSIDE the detail @Maybe@ (the hazard)?
readsEstimateOutsideMaybe :: DecodeStrategy -> Bool
readsEstimateOutsideMaybe MaybeForkOnly      = False
readsEstimateOutsideMaybe TruncateToEstimate = True
readsEstimateOutsideMaybe PreallocEstimate   = True

-- | Run a strategy. The safe one routes through the @Maybe@; the hazards size the
-- output from the estimate (and so break the floor on a starved head).
runStrategy :: DecodeStrategy -> BudgetHead -> Int -> [Int] -> [Int]
runStrategy MaybeForkOnly bh side vol = decodeWithBudget bh side vol
runStrategy TruncateToEstimate bh side vol =
  take (sum (bhSchedule bh)) (expandRungVolume side vol Nothing)
runStrategy PreallocEstimate bh side vol =
  take (sum (bhSchedule bh)) (expandRungVolume side vol Nothing ++ repeat 0)

-- | GOLDEN: a starved head reproduces the byte-exact floor.
goldenStarvedHeadIsFloor :: Bool
goldenStarvedHeadIsFloor =
     decodeWithBudget (starveHead defaultHead) 1 [200] == replicate 8 200
  && replicate 8 200 == expandRungVolume 1 [200] Nothing

-- | ★ KEYSTONE (teeth): every estimate-outside-Maybe strategy FAILS to reproduce the
-- floor on a starved head, so only the Maybe-fork routing is floor-safe.
lawOnlyMaybeForkIsFloorSafe :: Int -> [Int] -> Bool
lawOnlyMaybeForkIsFloorSafe side0 vol =
  let side = 1 + (abs side0 `mod` 3)
  in and [ not (readsEstimateOutsideMaybe s)
             || runStrategy s (starveHead defaultHead) side vol /= expandRungVolume side vol Nothing
         | s <- strategyFamily ]

-- | The spent packets never exceed the (non-negative) cap, even with a lying head.
lawBudgetHeadBoundsActualPackets :: BudgetHead -> Int -> Int -> [Int] -> Bool
lawBudgetHeadBoundsActualPackets bh cap0 side0 vol =
  let cap  = abs cap0 `mod` 8
      side = 1 + (abs side0 `mod` 3)
  in spentCost (decodeWithBudgetCapped cap bh side vol) <= cap

-- | Forward-compatible: a budget-blind base extractor yields the identical
-- @expressionSource@ with @swapMajor@ unchanged.
lawBudgetHeadForwardCompatible :: SwapPayload -> BudgetHead -> Bool
lawBudgetHeadForwardCompatible p bh =
     swapMajorOf (encodeWithBudget bh p) == swapMajor
  && expressionSource (extractBase (encodeWithBudget bh p)) == expressionSource (normalizePayload p)

-- | Tag identity is advisory-independent: two advisories over one base hash identically.
lawBudgetAdvisoryDoesNotChangeTagIdentity :: SwapPayload -> BudgetHead -> BudgetHead -> Bool
lawBudgetAdvisoryDoesNotChangeTagIdentity p bh1 bh2 =
  tagIdentityHash (encodeWithBudget bh1 p) == tagIdentityHash (encodeWithBudget bh2 p)
