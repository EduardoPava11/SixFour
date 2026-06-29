{- |
Module      : V2SkiTwoLevelEntropy
Description : EXPLORATION - NOT WIRED. "One rung = two levels: expand-then-contract."
              Level 1 maximizes entropy (S invent-up + I held bijection); level 2 maximizes
              K (pool-down weakening) so the PonderNet search reaches a steady state (halts).

  THREAD of the SixFour/OneSix two-lens exploration. BASE-ONLY, in NO cabal/Map/gate.
  Checkable with:  runghc exploration/V2SkiTwoLevelEntropy.hs

  ----------------------------------------------------------------------------------------
  WHAT IT MODELS (Owner ask 3).

  The 2x2x2 -> (1 coarse + 7 detail) rung is read as TWO octree levels (V2SkiLevels
  twiceness, @levelsPerStep == 2@). One rung = expand-then-contract:

    * LEVEL 1 (EXPAND) maximizes ENTROPY. We do as many S (invent-up) and I (held
      bijection) moves as are ADMISSIBLE. S manufactures new distinct detail (cardinality
      grows, Shannon entropy of the band grows); I holds a cell where it is (reversible).
      S is BARRED on the byte-exact floor (BCI excludes contraction: the floor is a
      bijection), so the entropy-maximal admissible assignment is "S on every free cell,
      I on every floor cell" - the floor genuinely CAPS how much S is admissible.

    * LEVEL 2 (CONTRACT) maximizes K (pool-down weakening): every (coarse, detail) pair is
      pooled to its coarse cell, dropping the detail. K is the only information-losing,
      non-injective move. Maximizing K drives the band down toward the coarse DC.

    * STEADY STATE. Iterating the contract level is a well-founded recursion: the measure
      "band length" (residual / detail-band cardinality) STRICTLY DECREASES on every
      non-fixed step and is bounded below, so it BOTTOMS OUT at the coarse DC (length <= 1)
      in finitely many steps. That bottom IS the PonderNet halt: in
      PonderHaltDistribution terms, more K (higher per-step halt rate lambda) moves halt
      mass to earlier steps and lowers @expectedSteps@; the fully-contracted band has no
      detail left to refine, which is the degenerate @haltDist [] == [1.0]@ (all mass at
      the halting step).

  BLESSED READING (V2-SKI-EXPAND-CONTRACT.md Section 2, cited, not re-derived; mirrors
  V2SkiLevels.hs heldIndex/expandUp/poolDown and inventFrom):
    I = held / reversible rung (bijection: nothing created, nothing lost).
    K = pool DOWN = weakening (affine structural rule, non-injective, the only way to lose).
    S = invent UP = contraction (full-SKI structural rule, the unique cardinality-increaser),
        BARRED on the byte-exact floor.

  CITES: V2SkiLevels (heldIndex, expandUp, inventFrom, poolDown, levelsPerStep, the I/S/K
  role grading and twiceness), SixFour.Spec.ScalePonder (per-scale refine/halt mask; halt
  only ever zeros DETAIL, never the coarse DC, which is why the floor survives every ponder
  decision), SixFour.Spec.PonderHaltDistribution (haltDist, expectedSteps, the lower-halt-
  refines-more semantics). Entropy primitive copied from V2EnergyWeave (entropyBits).

  ----------------------------------------------------------------------------------------
  HONESTY (the project rejects forced jargon; a structure is claimed only if its axioms
  actually CHECK in the code below).

   * WELL-FOUNDED, NOT BANACH. The termination of the contract iteration is a WELL-FOUNDED
     / monotone-decreasing argument on the discrete measure "band length" (a strictly
     decreasing function into the naturals, bounded below by 0). It is NOT a metric
     contraction mapping and we DO NOT invoke the Banach fixed-point theorem. We have NOT
     exhibited a metric d and a Lipschitz constant L < 1. In fact lawNoForcedContractionMapping
     exhibits equal-length witnesses x, y where poolDown does NOT shrink the value-distance
     at all ( d(pool x, pool y) == d(x, y), ratio 1, so no L < 1 exists ), while the length
     measure still strictly drops. Substructural K = weakening (drop a hypothesis) is a
     DIFFERENT notion from a metric "contraction"; we keep only the well-founded reading.

   * S BARRED ON THE FLOOR is load-bearing, not decorative: the level-1 maximizer is NOT
     trivially "all S". A floor cell forces I, so the admissible maximum length is strictly
     less than the unconstrained all-S length (asserted in lawLevel1MaximizesEntropy).

   * ENTROPY here = Shannon entropy (bits) of the band's value multiset (entropyBits). On
     this construction every retained and invented value is globally DISTINCT, so entropy
     reduces to log2 (length): more admissible S => longer band => strictly higher entropy.
     We compare Doubles with a 1e-9 tolerance, never with (==).

   * SIGN CONVENTION (Owner ask 2, carried but not exercised arithmetically here). The owner
     writes b = 2B - (R+G); V2Latent LOCKS latB = R+G - 2B, the NEGATION. This module's
     bands are ABSTRACT DC/detail cells (Int), NOT opponent colour coordinates, so no decode
     congruence is invoked and the sign never bites. Were these cells colour, energy uses
     |.| so the magnitude |2B - (R+G)| == |latB| is sign-invariant, but decode/onLattice are
     sign-sensitive and the stored field MUST stay latB = R+G - 2B. We do not silently flip.

   * PONDER TIE is by ANALOGY made checkable: we do not claim the octree IS a PonderNet, only
     that "more K => sooner halt" matches haltDist/expectedSteps monotonicity, witnessed with
     the same fixed distributions as PonderHaltDistribution.lawLowerHaltRefinesMore.

  NO em-dashes anywhere (owner directive).
-}

module V2SkiTwoLevelEntropy where

import Data.List (group, sort)
import System.Exit (exitFailure, exitSuccess)

-- ========================================================================================
-- Primitives copied from the cited modules (base-only; we do NOT import sixfour-spec).
-- ========================================================================================

-- | Abstract DC/detail band, NOT R/G/B channels (copied shape from V2SkiLevels.Frame = [Int]).
type Frame = [Int]

-- | I: held / reversible bijection. From V2SkiLevels.heldIndex.
heldIndex :: Frame -> Frame
heldIndex = id

-- | The detail an S-level manufactures. From V2SkiLevels.inventFrom (coarse + 100).
inventFrom :: Int -> Int
inventFrom coarse = coarse + 100

-- | K: pool DOWN = weakening. Keep the coarse cell of each (coarse, detail) pair, DROP the
--   detail; non-injective. Verbatim from V2SkiLevels.poolDown.
poolDown :: Frame -> Frame
poolDown (coarse:_detail:rest) = coarse : poolDown rest
poolDown [coarse]              = [coarse]
poolDown []                    = []

-- | One rung = exactly TWO octree levels. Copied constant from V2SkiLevels.levelsPerStep.
levelsPerStep :: Int
levelsPerStep = 2

-- | Shannon entropy (bits) of a band's value multiset. Copied from V2EnergyWeave.entropyBits,
--   with an empty-band guard (0 bits) so the Double never becomes NaN.
entropyBits :: [Int] -> Double
entropyBits [] = 0
entropyBits xs =
  let n  = fromIntegral (length xs)
      ps = [ fromIntegral c / n | c <- map length (group (sort xs)) ]
  in negate (sum [ p * logBase 2 p | p <- ps, p > 0 ])

-- | PonderNet halt distribution. Copied from SixFour.Spec.PonderHaltDistribution.
clamp01 :: Double -> Double
clamp01 = max 0 . min 1

haltDist :: [Double] -> [Double]
haltDist = go 1.0 . map clamp01
  where
    go remain []       = [remain]
    go remain (l : ls) = (remain * l) : go (remain * (1 - l)) ls

expectedSteps :: [Double] -> Double
expectedSteps dist = sum (zipWith (\n p -> fromIntegral n * p) [1 :: Int ..] dist)

-- Float tolerance for all Double comparisons.
eps :: Double
eps = 1e-9

-- ========================================================================================
-- LEVEL 1 (EXPAND): maximize entropy via S (invent-up) + I (held), S barred on the floor.
-- ========================================================================================

-- | A band cell carries a value and a byte-exact-FLOOR flag. A floor cell is a bijection
--   (reversible to RGB), so S (contraction) is barred on it; only I is admissible there.
data Cell = Cell { cellVal :: !Int, onFloor :: !Bool } deriving (Eq, Show)

-- | One level-1 move per cell. S = invent up (only the cardinality-increaser); I = hold.
--   K is NOT a level-1 move (level 1 is the EXPAND level).
data L1 = ApplyS | ApplyI deriving (Eq, Show)

-- | Realize a level-1 move on a cell.
--   I holds the cell (length-1, value preserved: a bijection).
--   S duplicates the coarse value as anchor AND manufactures a new distinct detail
--   (length-2): the unique cardinality-increasing move (mirrors V2SkiLevels.expandUp).
applyL1Cell :: L1 -> Cell -> [Int]
applyL1Cell ApplyI c = [cellVal c]
applyL1Cell ApplyS c = [cellVal c, inventFrom (cellVal c)]

-- | Apply a whole level-1 assignment to a band of cells (concatenate the per-cell outputs).
applyL1 :: [L1] -> [Cell] -> Frame
applyL1 asg cells = concat (zipWith applyL1Cell asg cells)

-- | ADMISSIBILITY. S is barred on the byte-exact floor; floor cells are forced to I.
--   Enumerate every admissible level-1 assignment for a band.
admissibleL1 :: [Cell] -> [[L1]]
admissibleL1 cells =
  sequence [ if onFloor c then [ApplyI] else [ApplyS, ApplyI] | c <- cells ]

-- | The claimed entropy-maximizer: S on every FREE cell, I on every floor cell.
maxEntropyL1 :: [Cell] -> [L1]
maxEntropyL1 cells = [ if onFloor c then ApplyI else ApplyS | c <- cells ]

-- | The level-1 objective: Shannon entropy (bits) of the produced band. "Counts/scores S
--   and I usage": on this distinct-value construction, more S => longer band => higher
--   entropy; I preserves; floor-forced I caps the achievable entropy.
level1Entropy :: [L1] -> [Cell] -> Double
level1Entropy asg cells = entropyBits (applyL1 asg cells)

-- ========================================================================================
-- LEVEL 2 (CONTRACT): maximize K (pool-down weakening) toward the coarse DC.
-- ========================================================================================

-- | A level-2 input is a band of (coarse, detail) pairs.
type Pair = (Int, Int)

-- | One level-2 move per pair. K = pool (drop detail, keep coarse); I = hold the pair.
data L2 = PoolK | HoldI deriving (Eq, Show)

applyL2Pair :: L2 -> Pair -> [Int]
applyL2Pair PoolK (c, _) = [c]
applyL2Pair HoldI (c, d) = [c, d]

applyL2 :: [L2] -> [Pair] -> Frame
applyL2 mask pairs = concat (zipWith applyL2Pair mask pairs)

-- | The contract level: pool EVERY pair (maximize K). This is the all-K mask.
level2Pool :: [Pair] -> Frame
level2Pool pairs = applyL2 (map (const PoolK) pairs) pairs

-- | Enumerate every level-2 mask.
allL2Masks :: [Pair] -> [[L2]]
allL2Masks pairs = sequence [ [PoolK, HoldI] | _ <- pairs ]

-- | How many pairs were weakened (detail dropped) by a mask.
droppedDetail :: [L2] -> Int
droppedDetail = length . filter (== PoolK)

-- ========================================================================================
-- STEADY STATE: iterate the contract; well-founded measure (length) bottoms out.
-- ========================================================================================

-- | The well-founded measure: detail-band cardinality.
measure :: Frame -> Int
measure = length

-- | Iterate poolDown until a fixed point (poolDown stops shrinking at length <= 1).
--   Terminates because @measure@ strictly decreases while length >= 2.
poolSteps :: Frame -> [Frame]
poolSteps x
  | poolDown x == x = [x]
  | otherwise       = x : poolSteps (poolDown x)

poolFixpoint :: Frame -> Frame
poolFixpoint = last . poolSteps

-- | Value-distance (L1 over the common prefix) used ONLY to show poolDown is NOT a metric
--   contraction. This is a witness probe, not a claimed metric on the whole space.
valDist :: Frame -> Frame -> Int
valDist xs ys = sum (zipWith (\a b -> abs (a - b)) xs ys)

-- ========================================================================================
-- WITNESSES (non-constant, exercised at boundaries).
-- ========================================================================================

-- Level-1 band: 3 FREE cells (S admissible) + 1 FLOOR cell (S barred, forces I).
-- Distinct base values (so invented values + 100 are globally distinct => entropy = log2 len).
cells1 :: [Cell]
cells1 = [ Cell 1 False, Cell 2 False, Cell 3 True, Cell 4 False ]

-- Level-2 band of pairs (coarse, detail).
pairs2 :: [Pair]
pairs2 = [ (10, 1), (20, 2), (30, 3) ]

-- Steady-state witness: even-length band, several contract steps.
sf1 :: Frame
sf1 = [10, 1, 20, 2, 30, 3, 40, 4]

-- No-contraction-mapping witnesses: equal length, differ only in a COARSE cell that poolDown
-- preserves exactly, so the value-distance is unchanged by pooling (ratio 1, no L < 1).
xC, yC :: Frame
xC = [10, 0, 5, 0]
yC = [20, 0, 5, 0]

-- Ponder witnesses (same fixed distributions as PonderHaltDistribution.lawLowerHaltRefinesMore).
highHalt, lowHalt :: [Double]
highHalt = replicate 6 0.6   -- more K / eager to halt (more contraction)
lowHalt  = replicate 6 0.2   -- less K / reluctant to halt (more refinement)

-- ========================================================================================
-- LAWS.
-- ========================================================================================

-- | S is the unique cardinality-increaser and I is a value-preserving bijection.
--   Teeth: S strictly grows length (1 -> 2); I preserves both length and value; mislabelling
--   S as I would claim invention is the identity, which FAILS.
lawSInventsIHolds :: Bool
lawSInventsIHolds =
  let c = Cell 7 False
  in    length (applyL1Cell ApplyS c) == 2          -- S grows cardinality
     && length (applyL1Cell ApplyI c) == 1          -- I holds cardinality
     && applyL1Cell ApplyI c == [7]                 -- I preserves the value (bijection)
     && applyL1Cell ApplyS c == [7, 107]            -- S keeps anchor + invents distinct detail
     && applyL1Cell ApplyS c /= applyL1Cell ApplyI c -- tooth: invention is NOT the identity

-- | S is BARRED on the byte-exact floor: no admissible level-1 assignment ever places S on a
--   floor cell. Teeth: there IS a floor cell (index 2), and every enumerated assignment holds
--   I there, while free cells DO range over S.
lawSBarredOnFloor :: Bool
lawSBarredOnFloor =
  let floorIdxs = [ i | (i, c) <- zip [0 ..] cells1, onFloor c ]
      freeIdxs  = [ i | (i, c) <- zip [0 ..] cells1, not (onFloor c) ]
      asgs      = admissibleL1 cells1
  in    not (null floorIdxs)                                            -- tooth: floor exists
     && all (\a -> all (\i -> a !! i == ApplyI) floorIdxs) asgs         -- S barred on floor
     && any (\a -> any (\i -> a !! i == ApplyS) freeIdxs) asgs          -- S DOES occur on free

-- | LEVEL 1 maximizes entropy: among all admissible assignments, "S on every free cell, I on
--   every floor cell" is the argmax. Non-vacuous teeth:
--     (a) it strictly beats the all-I assignment (S genuinely raises entropy),
--     (b) the floor CAPS it: the admissible-max length is strictly less than the
--         unconstrained all-S length (so the maximizer is NOT trivially "all S").
lawLevel1MaximizesEntropy :: Bool
lawLevel1MaximizesEntropy =
  let claimed     = maxEntropyL1 cells1
      claimedE    = level1Entropy claimed cells1
      allI        = replicate (length cells1) ApplyI
      allIE       = level1Entropy allI cells1
      isArgmax    = all (\a -> level1Entropy a cells1 <= claimedE + eps) (admissibleL1 cells1)
      claimedLen  = length (applyL1 claimed cells1)
      uncappedLen = 2 * length cells1           -- hypothetical all-S (if no floor barred it)
  in    isArgmax
     && claimedE > allIE + eps                  -- (a) S strictly raises entropy
     && claimedLen < uncappedLen                -- (b) floor caps admissible S

-- | LEVEL 2 maximizes K: the all-PoolK mask drops the most detail and yields the minimal-length
--   band (maximal contraction) among all masks. Teeth: it strictly beats the all-HoldI mask,
--   and pairs2 is non-empty so the maximum is real. Also ties to the copied poolDown.
lawLevel2MaximizesK :: Bool
lawLevel2MaximizesK =
  let claimed   = map (const PoolK) pairs2
      allHold   = map (const HoldI) pairs2
      masks     = allL2Masks pairs2
      claimedLn = length (applyL2 claimed pairs2)
  in    not (null pairs2)
     && all (\m -> length (applyL2 m pairs2) >= claimedLn) masks      -- all-K minimizes length
     && all (\m -> droppedDetail claimed >= droppedDetail m) masks    -- all-K drops the most
     && droppedDetail claimed > droppedDetail allHold                 -- tooth vs all-Hold
     && level2Pool pairs2 == [10, 20, 30]                             -- pools to coarse DC
     && level2Pool [(10, 1), (20, 2)] == poolDown [10, 1, 20, 2]      -- consistent with poolDown

-- | STEADY STATE: iterating the contract level reaches a FIXED POINT in finitely many steps,
--   and that fixed point is the coarse DC bottom (length <= 1). Tested at boundaries:
--   the long band sf1, the empty band, and a singleton (already fixed).
lawContractReachesSteadyState :: Bool
lawContractReachesSteadyState =
  let check x =
        let fp = poolFixpoint x
        in    poolDown fp == fp                       -- it IS a fixed point
           && measure fp <= 1                         -- bottom = coarse DC
           && length (poolSteps x) <= measure x + 1   -- finite, length-bounded
  in check sf1 && check [] && check [7] && poolFixpoint sf1 == [10]

-- | The WELL-FOUNDED measure strictly decreases on every non-fixed contract step (monotone
--   into the naturals, bounded below by 0). Non-vacuous: sf1 has 3 transitions, all strict.
lawMeasureStrictlyDecreases :: Bool
lawMeasureStrictlyDecreases =
  let steps   = poolSteps sf1
      msrs    = map measure steps
      strict  = and (zipWith (>) msrs (drop 1 msrs))
  in    length steps >= 2          -- there ARE transitions to check
     && strict                     -- each strictly smaller
     && last msrs >= 0             -- bounded below (well-founded floor)

-- | HONESTY GUARD. Termination is WELL-FOUNDED, NOT a Banach metric contraction. Substructural
--   K = weakening is a different notion from a Lipschitz < 1 map. Witness: equal-length xC, yC
--   that differ only in a COARSE cell poolDown preserves, so the value-distance is UNCHANGED by
--   pooling ( d(pool x, pool y) == d(x, y), ratio 1 ), hence NO contraction constant L < 1 can
--   exist; meanwhile the length measure strictly drops. So the termination witness is the
--   well-founded measure, never a metric contraction.
lawNoForcedContractionMapping :: Bool
lawNoForcedContractionMapping =
  let dBefore = valDist xC yC
      dAfter  = valDist (poolDown xC) (poolDown yC)
  in    dBefore > 0                                  -- a real (non-zero) distance to probe
     && dAfter == dBefore                            -- pooling does NOT shrink the metric
     && not (dAfter < dBefore)                       -- so no Banach L < 1 holds here
     && measure (poolDown xC) < measure xC           -- yet the WELL-FOUNDED measure drops
     && measure (poolDown yC) < measure yC

-- | PONDER TIE. More K (contraction) corresponds to a higher per-step halt rate lambda: halt
--   mass moves to earlier steps and @expectedSteps@ falls (mirrors
--   PonderHaltDistribution.lawLowerHaltRefinesMore). And the fully-contracted band (no detail
--   left to refine) is the degenerate @haltDist [] == [1.0]@: all mass at the halting step.
lawHaltMassMovesWithContraction :: Bool
lawHaltMassMovesWithContraction =
  let esHigh = expectedSteps (haltDist highHalt)
      esLow  = expectedSteps (haltDist lowHalt)
  in    esHigh < esLow                                       -- more K => halts sooner
     && abs (sum (haltDist highHalt) - 1) < eps              -- proper distribution
     && abs (sum (haltDist lowHalt)  - 1) < eps
     && haltDist [] == [1.0]                                 -- fully contracted = certain halt
     && abs (expectedSteps (haltDist []) - 1) < eps          -- all mass at the single halt step

-- ========================================================================================
-- RUNNER.
-- ========================================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawSInventsIHolds",              lawSInventsIHolds)
  , ("lawSBarredOnFloor",              lawSBarredOnFloor)
  , ("lawLevel1MaximizesEntropy",      lawLevel1MaximizesEntropy)
  , ("lawLevel2MaximizesK",            lawLevel2MaximizesK)
  , ("lawContractReachesSteadyState",  lawContractReachesSteadyState)
  , ("lawMeasureStrictlyDecreases",    lawMeasureStrictlyDecreases)
  , ("lawNoForcedContractionMapping",  lawNoForcedContractionMapping)
  , ("lawHaltMassMovesWithContraction",lawHaltMassMovesWithContraction)
  ]

main :: IO ()
main = do
  mapM_ (\(n, ok) -> putStrLn (n ++ ": " ++ if ok then "PASS" else "FAIL")) laws
  if all snd laws
    then do putStrLn "ALL LAWS PASS"; exitSuccess
    else exitFailure
