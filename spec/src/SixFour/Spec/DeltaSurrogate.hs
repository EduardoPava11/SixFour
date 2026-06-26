-- COMPARTMENT: MLX-MODEL | tag:MacTag
{- |
Module      : SixFour.Spec.DeltaSurrogate
Description : The DIFFERENTIABLE training surrogates for the two delta heads — and the proof each one's HARD COMMIT re-enters its byte-exact carrier. The value delta relaxes to an OKLab REGRESSION (L2); the policy delta, being a transport over CATEGORICAL palette slots, relaxes to a per-voxel CLASSIFICATION (softmax + cross-entropy), NOT a regression. This is the learned-continuous ↔ proven-discrete seam for the time axis, stated as laws.

"SixFour.Spec.HierarchicalDelta" defines the two delta CARRIERS as the byte-exact substrate: the
VALUE delta is a ℤ-module ('ColourDelta'), the POLICY delta a transport group over categorical
palette slots ('IndexDelta'). Neither is differentiable as-is — you cannot take a gradient through
an integer displacement, still less through a @Map@ of @(oldSlot,newSlot)@ assignments. Training
therefore needs CONTINUOUS surrogates, and the two carriers fall on OPPOSITE sides of the
regression\/classification line:

  * The VALUE head is a REGRESSION. 'ValueSurrogate' is a continuous OKLab displacement per slot;
    'decodeValue' rounds it (commit half-to-even) to a 'ColourDelta', and 'valueLoss' is squared
    OKLab distance. 'lawValueSurrogateDecodesToCarrier' = the integer target is a fixpoint of the
    decode (the relaxation loses nothing at the optimum); 'lawValueLossIsRegression' = the loss is
    a genuine squared metric (doubling the error quadruples the loss).
  * The POLICY head is a CLASSIFICATION. 'PolicySurrogate' is per-voxel logits over the K palette
    slots; 'decodePolicy' is a per-voxel argmax (deterministic lowest-index tie-break), and
    'policyLoss' is categorical cross-entropy — a slot label has no metric, so an L2 over slot
    NUMBERS would be meaningless. THE KEYSTONE 'lawPolicySurrogateDecodesToTransport' proves the
    hard argmax commit re-enters the byte-exact 'IndexDelta' transport EXACTLY: a surrogate that
    classifies every voxel correctly decodes to the data-manufactured policy target, so the
    continuous head and the integer floor agree at the optimum. 'lawPolicyArgmaxDeterministic'
    pins the commit as a pure function of the logits (no float nondeterminism commits a byte).

Collapse-safety is INHERITED, not re-proven: both surrogates regress\/classify toward the
DATA-MANUFACTURED carriers ("SixFour.Spec.TemporalData" / "SixFour.Spec.JepaTarget"), which are
@θ@-free, so no EMA and no @L_close@ orbit. This module only adds the differentiable skins and
their decode bridges.

GHC-boot-only. Reuses @HierarchicalDelta@ (the carriers) + @ConstructionEncoder@ (@QColour@).
Laws QuickCheck'd in "Properties.DeltaSurrogate".
-}
module SixFour.Spec.DeltaSurrogate
  ( -- * The VALUE head: a continuous OKLab regression surrogate
    QColourF
  , ValueSurrogate(..)
  , embedValue
  , decodeValue
  , valueLoss
    -- * The POLICY head: a per-voxel categorical (softmax/CE) surrogate
  , PolicySurrogate(..)
  , oneHotPolicy
  , decodePolicy
  , policyLoss
  , softmax
    -- * The policy backward (CE gradient) step + the margin-guarded commit
  , policyGradStep
  , policyMarginEps
  , commitWithMargin
    -- * Laws (QuickCheck'd in @Properties.DeltaSurrogate@)
  , lawValueSurrogateDecodesToCarrier
  , lawValueLossZeroAtTarget
  , lawValueLossIsRegression
  , lawPolicySurrogateDecodesToTransport
  , lawPolicyArgmaxDeterministic
  , lawPolicyCrossEntropyPrefersTarget
  , lawPolicyCEGradientMovesTowardTarget
  , lawPolicyArgmaxMarginOrFallback
  ) where

import Data.List (sortBy)
import Data.Ord  (comparing, Down(..))

import SixFour.Spec.ConstructionEncoder (QColour)
import SixFour.Spec.HierarchicalDelta   (ColourDelta(..), IndexDelta, deltaBetween)

-- ============================================================================
-- VALUE head — a continuous OKLab REGRESSION surrogate
-- ============================================================================

-- | A continuous OKLab displacement @(dL,da,db)@ — one float colour (the differentiable twin of a
-- "SixFour.Spec.ConstructionEncoder" @QColour@).
type QColourF = (Double, Double, Double)

-- | The VALUE surrogate: a continuous per-slot OKLab displacement the regression head emits.
newtype ValueSurrogate = ValueSurrogate { unValueSurrogate :: [QColourF] } deriving (Eq, Show)

toF :: QColour -> QColourF
toF (l,a,b) = (fromIntegral l, fromIntegral a, fromIntegral b)

-- | Embed an integer 'ColourDelta' as a continuous surrogate (the exact-target witness).
embedValue :: ColourDelta -> ValueSurrogate
embedValue (ColourDelta xs) = ValueSurrogate (map toF xs)

-- | COMMIT the regression to the byte-exact carrier: round each displacement half-to-even (the
-- spec's commit rounding) to an integer 'ColourDelta'.
decodeValue :: ValueSurrogate -> ColourDelta
decodeValue (ValueSurrogate ss) = ColourDelta [ (round l, round a, round b) | (l,a,b) <- ss ]

-- | The REGRESSION loss: summed squared OKLab distance to the (integer) target — the differentiable
-- objective the value head descends.
valueLoss :: ValueSurrogate -> ColourDelta -> Double
valueLoss (ValueSurrogate ss) (ColourDelta ts) = sum (zipWith sq ss (map toF ts))
  where sq (l1,a1,b1) (l2,a2,b2) = (l1-l2)^(2::Int) + (a1-a2)^(2::Int) + (b1-b2)^(2::Int)

-- ============================================================================
-- POLICY head — a per-voxel categorical (softmax / cross-entropy) surrogate
-- ============================================================================

-- | The POLICY surrogate: per voxel, a length-K logit vector over the palette slots. The
-- classification head emits these; the commit is a per-voxel argmax.
newtype PolicySurrogate = PolicySurrogate { unPolicySurrogate :: [[Double]] } deriving (Eq, Show)

-- | A one-hot surrogate over K slots for a list of target slot indices (the exact-target witness:
-- a peak of @10@ at the target slot, @0@ elsewhere).
oneHotPolicy :: Int -> [Int] -> PolicySurrogate
oneHotPolicy k targets =
  PolicySurrogate [ [ if s == t then 10 else 0 | s <- [0 .. k-1] ] | t <- targets ]

-- | Per-voxel argmax with a deterministic LOWEST-INDEX tie-break (so a tie commits a definite slot,
-- never a float-order coin-flip). THE one place the policy commit is defined.
argmaxFirst :: [Double] -> Int
argmaxFirst [] = 0
argmaxFirst xs = length (takeWhile (/= maximum xs) xs)

-- | COMMIT the classification to a Morton-order index map: the argmax slot per voxel. Composed with
-- 'deltaBetween' against the base index, this is the byte-exact 'IndexDelta'.
decodePolicy :: PolicySurrogate -> [Int]
decodePolicy (PolicySurrogate rows) = map argmaxFirst rows

-- | Numerically-stable softmax (max-subtract) — the differentiable normaliser the CE loss reads.
softmax :: [Double] -> [Double]
softmax zs =
  let m  = maximum zs
      es = map (\z -> exp (z - m)) zs
      s  = sum es
  in map (/ s) es

-- | The CLASSIFICATION loss: summed per-voxel categorical cross-entropy at the target slot. A slot
-- is a categorical label with no metric, so this — not an L2 over slot numbers — is the differentiable
-- objective the policy head descends.
policyLoss :: PolicySurrogate -> [Int] -> Double
policyLoss (PolicySurrogate rows) targets =
  sum [ negate (log (max 1e-12 (softmax row !! t))) | (row, t) <- zip rows targets ]

-- | ONE cross-entropy BACKWARD step per voxel (the train-time gradient the policy head descends):
-- @row' = row − lr · (softmax row − oneHot t)@. @softmax row − oneHot t@ is exactly the CE gradient
-- w.r.t. the logits, so a step with @lr > 0@ moves the head toward committing the target slot.
policyGradStep :: Double -> PolicySurrogate -> [Int] -> PolicySurrogate
policyGradStep lr (PolicySurrogate rows) targets =
  PolicySurrogate [ step row t | (row, t) <- zip rows targets ]
  where
    step row t =
      let p   = softmax row
          oh  = [ if s == t then 1 else 0 | s <- [0 .. length row - 1] ]
          grd = zipWith (-) p oh
      in zipWith (\z g -> z - lr * g) row grd

-- | The pinned logit-margin threshold for a cross-device-safe discrete commit. A float argmax is
-- NOT bit-identical across devices at a near-tie, so the policy commits the argmax only when the
-- top-two logit gap EXCEEDS this eps; otherwise it falls back to the data-manufactured slot.
policyMarginEps :: Double
policyMarginEps = 1e-6

-- | Margin-guarded policy commit: per voxel, emit the @argmaxFirst@ slot ONLY when @(top1 − top2) > eps@
-- (sort descending, take the gap); otherwise fall back to the corresponding data-manufactured
-- target slot from the @fallback@ list. So every committed byte is either margin-safe (a clear
-- winner, cross-device deterministic) or the byte-exact data slot — never a device-dependent
-- near-tie argmax.
commitWithMargin :: Double -> [Int] -> PolicySurrogate -> [Int]
commitWithMargin eps fallback (PolicySurrogate rows) =
  [ commit row f | (row, f) <- zip rows fallback ]
  where
    commit row f =
      case sortBy (comparing Down) row of
        (a : b : _) -> if a - b > eps then argmaxFirst row else f
        [_]         -> argmaxFirst row     -- a single slot has no rival: an unambiguous winner
        []          -> f

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.DeltaSurrogate)
-- ============================================================================

-- | The VALUE relaxation loses nothing at the optimum: the integer 'ColourDelta' is a FIXPOINT of
-- @decodeValue . embedValue@. So a regression head that reaches the target commits the byte-exact
-- carrier. Teeth: a decode that truncated (not half-to-even rounded) would drift on a half value.
lawValueSurrogateDecodesToCarrier :: [QColour] -> Bool
lawValueSurrogateDecodesToCarrier xs =
  decodeValue (embedValue (ColourDelta xs)) == ColourDelta xs

-- | The regression loss is ZERO exactly at the target (and the objective is well-defined). Teeth: a
-- biased loss would be non-zero at the exact target.
lawValueLossZeroAtTarget :: [QColour] -> Bool
lawValueLossZeroAtTarget xs =
  valueLoss (embedValue (ColourDelta xs)) (ColourDelta xs) == 0

-- | The value loss is a genuine SQUARED metric (a regression, not a classification): scaling the
-- displacement ERROR by @c@ scales the loss by @c²@. Teeth: a linear (L1) or categorical loss would
-- scale by @|c|@, not @c²@ — this is what distinguishes the value head's objective from the policy's.
lawValueLossIsRegression :: [QColour] -> Int -> Bool
lawValueLossIsRegression xs c0 =
  let c       = 1 + (abs c0 `mod` 5)                       -- a scale in [1,5]
      errAt k = valueLoss (ValueSurrogate [ (fromIntegral (k*l), fromIntegral (k*a), fromIntegral (k*b))
                                          | (l,a,b) <- xs ]) (ColourDelta (map (const (0,0,0)) xs))
                                                            -- loss of (k·x) against 0 = k²·‖x‖²
  in errAt c == fromIntegral (c*c) * errAt 1

-- | THE KEYSTONE — the policy surrogate's HARD COMMIT re-enters the byte-exact transport. A
-- classification head that labels every voxel with frame @t+1@'s slot argmax-decodes to EXACTLY that
-- index map, so the committed 'IndexDelta' (@deltaBetween base@ the decode) equals the
-- data-manufactured policy target (@deltaBetween base target@). The continuous head and the integer
-- floor AGREE at the optimum — the learned-continuous ↔ proven-discrete bridge, closed for policy.
-- Teeth: a mis-decode (wrong argmax, mishandled tie) would commit a different index and break the
-- transport equality.
lawPolicySurrogateDecodesToTransport :: Int -> [Int] -> [Int] -> Bool
lawPolicySurrogateDecodesToTransport k0 base target =
  let k = 1 + abs k0
      inRange = all (\i -> i >= 0 && i < k)
  in not (length base == length target && inRange base && inRange target)
     || let sur = oneHotPolicy k target
        in decodePolicy sur == target
           && (deltaBetween base (decodePolicy sur) :: IndexDelta) == deltaBetween base target

-- | The policy COMMIT is a pure function of the logits: argmax breaks ties to the LOWEST index, so
-- no float ordering decides a byte. Teeth: a tie resolved by @maximumBy@ (last) or by float address
-- would commit a different slot for @[1,3,3]@.
lawPolicyArgmaxDeterministic :: Bool
lawPolicyArgmaxDeterministic =
  decodePolicy (PolicySurrogate [[1,3,3], [5,2,2,2], [0]]) == [1, 0, 0]

-- | Cross-entropy is a genuine CLASSIFICATION objective: a surrogate peaked at the TARGET slot
-- incurs strictly LESS loss than one peaked at a WRONG slot. So gradient descent on CE drives the
-- argmax toward the data slot. Teeth: a constant or wrong-peaked surrogate scores no better than the
-- target-peaked one would fail this strict inequality.
lawPolicyCrossEntropyPrefersTarget :: Int -> Int -> Int -> Bool
lawPolicyCrossEntropyPrefersTarget k0 t0 w0 =
  let k = 2 + abs k0
      t = abs t0 `mod` k
      w = abs w0 `mod` k
  in t == w
     || policyLoss (oneHotPolicy k [t]) [t] < policyLoss (oneHotPolicy k [w]) [t]

-- | THE BACKWARD-PATH TOOTH — the CE gradient MOVES a wrong head toward the byte-exact slot. Start
-- a @K=3@ surrogate peaked at the WRONG slot (@[[0,0,5]]@, argmax = 2) with target @[0]@: (a) ONE
-- 'policyGradStep' strictly LOWERS 'policyLoss' (the relaxed objective descends), and (b) iterating
-- the step drives 'decodePolicy' to converge to @[0]@ — the argmax reaches the data-manufactured
-- slot. Exercises the TRAIN-TIME BACKWARD path 'lawPolicySurrogateDecodesToTransport' never touches
-- (that one only checks a perfect one-hot FORWARD-decode at the optimum). Teeth: a head with no
-- gradient toward target, or an L2-over-slot-numbers surrogate, FAILS the strict-decrease +
-- argmax-reaches-target conjuncts.
lawPolicyCEGradientMovesTowardTarget :: Bool
lawPolicyCEGradientMovesTowardTarget =
  let lr      = 0.5
      sur     = PolicySurrogate [[0, 0, 5]]   -- peaked at the WRONG slot (argmax = 2)
      tgt     = [0]
      oneStep = policyGradStep lr sur tgt
      settled = iterate (\s -> policyGradStep lr s tgt) sur !! 200
  in policyLoss oneStep tgt < policyLoss sur tgt   -- the CE objective strictly descends
     && decodePolicy settled == tgt                 -- ...and the argmax reaches the data slot

-- | THE COMMIT-MARGIN TOOTH — the discrete commit is cross-device safe at a FLOAT near-tie. For a
-- near-tie row @[1.0, 1.0 + 5e-7]@ (gap @< policyMarginEps@) with fallback slot @f@,
-- 'commitWithMargin' returns @[f]@ (deterministic data-slot fallback, NOT the device-dependent
-- argmax 1); for a clear-margin row @[0, 5]@ it returns the argmax @[1]@. So every committed byte is
-- either margin-safe or the byte-exact data slot. Exercises the sub-eps near-tie boundary
-- 'lawPolicyArgmaxDeterministic' never reaches (it covers only EXACT integer ties). Teeth: a plain
-- argmax would commit a device-dependent slot at the near-tie and FAIL the @[f]@ conjunct.
lawPolicyArgmaxMarginOrFallback :: Bool
lawPolicyArgmaxMarginOrFallback =
  let f       = 0                                   -- the data slot, distinct from the near-tie argmax (1)
      nearTie = PolicySurrogate [[1.0, 1.0 + 5e-7]]
      clear   = PolicySurrogate [[0, 5]]
  in commitWithMargin policyMarginEps [f] nearTie == [f]   -- sub-eps gap ⇒ fall back to the data slot
     && commitWithMargin policyMarginEps [f] clear == [1]  -- clear margin ⇒ commit the argmax
     && argmaxFirst [1.0, 1.0 + 5e-7] == 1                 -- ...the would-be argmax 1 differs from f=0
