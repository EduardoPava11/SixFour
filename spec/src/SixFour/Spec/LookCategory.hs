{- |
Module      : SixFour.Spec.LookCategory
Description : The north-star foundation — a named look taxonomy + per-user push-pull learning.

The product north-star is __on-device personalized look-learning__: the user trains /
"push-pulls" a proprietary model so it learns /their/ look, with looks mapped out in
__categories__. 'SixFour.Spec.Preference' supplies the continuous, category-free taste
utility (Bradley–Terry) and the DPP gallery; this module adds the two pieces the
north-star still lacked (both flagged in @docs/SIXFOUR-DEBT-CLEANUP-REPORT.md@):

  1. __A category taxonomy__ — a small, named coordinate system over taste. Unlike the
     deleted Berlin–Kay @Competition@ grid (which discretised the /palette itself/ and
     inherited that fidelity error), categories here are __prototypes in descriptor
     space__: a look is summarised by an OKLab descriptor (e.g. a palette's mean), and
     'classify' picks the nearest prototype. The palette is never quantised to the
     taxonomy — the taxonomy only /labels/ a continuous descriptor, so it adds a
     legend, not a loss.

  2. __An on-device learning step__ — 'btGradStep' is one stochastic-gradient step of the
     Bradley–Terry logistic loss over the linear utility's parameter vector. A single
     "keep A over B" / swipe signal nudges the utility toward preferring A. 'trainPairs'
     folds a batch — the literal push-pull loop that runs on the phone (hand-written
     SGD on a small parameter vector; no third-party trainer on the shipped path, per
     @CLAUDE.md@ Tier 2). This is the verified /source of truth/ for that step; the
     on-device Swift port follows once the look-net forward pass is wired
     (@loadLookNet@ currently has zero callers).

Contract-first, no stubs. Laws in @Properties.LookCategory@.
-}
module SixFour.Spec.LookCategory
  ( -- * The look taxonomy (named coordinate system over taste)
    LookCategory(..)
  , allLookCategories
  , categoryPrototype
  , classify
  , lookDescriptor
  , classifyPalette
    -- * Per-user push-pull learning (Bradley–Terry SGD)
  , preferenceGap
  , btGradStep
  , trainPairs
    -- * Laws
  , lawClassifyTotal
  , lawPrototypeSelfClassify
  , lawCategoriesDistinct
  , lawZeroRateIdentity
  , lawStepIncreasesPreferredGap
  , lawDescriptorSingleton
  , lawClassifyPaletteTotal
  , lawUniformPaletteClassifiesToPrototype
  ) where

import Data.List (foldl', minimumBy)
import Data.Ord  (comparing)

import SixFour.Spec.Color      (OKLab(..), okLabDistanceSquared)
import SixFour.Spec.Preference (Embedding, linearUtility, btProbability)

-- ----------------------------------------------------------------------------
-- The look taxonomy
-- ----------------------------------------------------------------------------

-- | The named look categories — a fixed, perceptually-spread coordinate system over
-- taste. NOT a partition of the palette (see the module note): each is a /prototype/ a
-- continuous descriptor is labelled by. Order is the deterministic tie-break for
-- 'classify'.
data LookCategory
  = Warm    -- ^ reddish-yellow, mid-bright
  | Cool    -- ^ greenish-blue, mid-bright
  | Muted   -- ^ low-chroma, mid-lightness
  | Vivid   -- ^ high-chroma, bright
  | Dark    -- ^ low-lightness
  | Bright  -- ^ high-lightness, near-neutral
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | Every category, in declaration order (the 'classify' tie-break order).
allLookCategories :: [LookCategory]
allLookCategories = [minBound .. maxBound]

-- | The fixed OKLab prototype for a category — distinct anchors spread across the
-- @(L, a, b)@ look descriptor space. NOT data-derived (so a category's meaning is a
-- stable contract, exactly as 'SixFour.Spec.CloudProjection.canonicalCentre' is fixed).
categoryPrototype :: LookCategory -> OKLab
categoryPrototype Warm   = OKLab 0.62   0.12    0.10
categoryPrototype Cool   = OKLab 0.62 (-0.10) (-0.08)
categoryPrototype Muted  = OKLab 0.55   0.02    0.02
categoryPrototype Vivid  = OKLab 0.70   0.18    0.16
categoryPrototype Dark   = OKLab 0.22   0.00    0.00
categoryPrototype Bright = OKLab 0.92   0.03    0.05

-- | Label an OKLab look descriptor with its nearest category (Euclidean OKLab
-- distance; ties resolve to the earliest in 'allLookCategories'). Total: always
-- returns a category.
classify :: OKLab -> LookCategory
classify desc =
  fst (minimumBy (comparing snd)
        [ (c, okLabDistanceSquared desc (categoryPrototype c)) | c <- allLookCategories ])

-- | Summarise a whole palette's look as a single OKLab descriptor: the component-wise
-- mean of its colours. This is the bridge from the deterministic palette the app emits
-- today to the taxonomy — no NN required, so 'classifyPalette' works on the current
-- render output. An empty palette maps to the neutral centre @(0.5, 0, 0)@ so the
-- function is total.
lookDescriptor :: [OKLab] -> OKLab
lookDescriptor [] = OKLab 0.5 0 0
lookDescriptor cs =
  let n            = fromIntegral (length cs)
      (sl, sa, sb) = foldl' (\(l, a, b) (OKLab l' a' b') -> (l + l', a + a', b + b')) (0, 0, 0) cs
  in OKLab (sl / n) (sa / n) (sb / n)

-- | The look category of a whole palette: classify its mean-OKLab descriptor. The
-- end-to-end "what look is this?" the Review screen can label a render with today.
classifyPalette :: [OKLab] -> LookCategory
classifyPalette = classify . lookDescriptor

-- ----------------------------------------------------------------------------
-- Per-user push-pull learning (Bradley–Terry SGD)
-- ----------------------------------------------------------------------------

-- | The utility gap @u(a) − u(b)@ under the linear utility parameterised by @theta@.
-- Positive ⇒ @a@ is preferred. This is the Bradley–Terry logit.
preferenceGap :: [Double] -> Embedding -> Embedding -> Double
preferenceGap theta a b = linearUtility theta a - linearUtility theta b

-- | One SGD step of the Bradley–Terry logistic loss for a single preference
-- @(winner, loser)@: minimising @−log σ(u(w) − u(l))@ gives the gradient
-- @−(1 − σ(g))·(w − l)@, so the descent update is
-- @theta' = theta + rate·(1 − σ(g))·(w − l)@. The coefficient @rate·(1 − σ(g)) ≥ 0@
-- shrinks as the model already prefers @w@ (g large ⇒ σ→1) — it pulls hardest on
-- surprises, exactly the push-pull behaviour the on-device learner wants.
btGradStep :: Double -> [Double] -> (Embedding, Embedding) -> [Double]
btGradStep rate theta (w, l) =
  let g     = preferenceGap theta w l
      coeff = rate * (1 - btProbability g)
      grad  = map (* coeff) (zipWith (-) w l)
  in zipWith (+) theta grad

-- | The on-device training loop: fold a batch of @(winner, loser)@ pairwise signals
-- (keeps / swipes) into the utility parameters, one 'btGradStep' each.
trainPairs :: Double -> [(Embedding, Embedding)] -> [Double] -> [Double]
trainPairs rate pairs theta0 = foldl' (\th p -> btGradStep rate th p) theta0 pairs

-- ----------------------------------------------------------------------------
-- Laws (proven in Properties.LookCategory)
-- ----------------------------------------------------------------------------

-- | 'classify' is total: it always returns a real category.
lawClassifyTotal :: OKLab -> Bool
lawClassifyTotal desc = classify desc `elem` allLookCategories

-- | Each category's own prototype classifies back to that category (distance 0 is the
-- unique minimum because the prototypes are distinct) — the taxonomy is self-consistent.
lawPrototypeSelfClassify :: Bool
lawPrototypeSelfClassify = all (\c -> classify (categoryPrototype c) == c) allLookCategories

-- | The prototypes are pairwise distinct (no two categories share an anchor).
lawCategoriesDistinct :: Bool
lawCategoriesDistinct =
  and [ okLabDistanceSquared (categoryPrototype a) (categoryPrototype b) > 0
      | a <- allLookCategories, b <- allLookCategories, a /= b ]

-- | A zero learning rate is the identity (no signal ⇒ no change). Requires @theta@,
-- @w@, @l@ to share a dimension.
lawZeroRateIdentity :: [Double] -> (Embedding, Embedding) -> Bool
lawZeroRateIdentity theta (w, l) = btGradStep 0 theta (w, l) == theta

-- | __The core personalization guarantee.__ With a positive rate and a non-degenerate
-- pair (@w ≠ l@), one 'btGradStep' STRICTLY increases the preference gap for the
-- winner: @g' = g + rate·(1 − σ(g))·‖w − l‖² > g@. The model moves toward the user's
-- expressed look every step — push-pull provably learns.
lawStepIncreasesPreferredGap :: Double -> [Double] -> (Embedding, Embedding) -> Bool
lawStepIncreasesPreferredGap rate theta (w, l)
  | rate <= 0 = True
  | w == l    = True
  | otherwise =
      preferenceGap (btGradStep rate theta (w, l)) w l > preferenceGap theta w l

-- | A singleton palette's descriptor is that colour (mean of one).
lawDescriptorSingleton :: OKLab -> Bool
lawDescriptorSingleton c = okLabDistanceSquared (lookDescriptor [c]) c == 0

-- | 'classifyPalette' is total for any palette (including empty).
lawClassifyPaletteTotal :: [OKLab] -> Bool
lawClassifyPaletteTotal cs = classifyPalette cs `elem` allLookCategories

-- | A palette made entirely of one category's prototype classifies to that category —
-- the taxonomy round-trips through the descriptor. (@n ≥ 1@.)
lawUniformPaletteClassifiesToPrototype :: Int -> LookCategory -> Bool
lawUniformPaletteClassifiesToPrototype n c =
  classifyPalette (replicate (max 1 n) (categoryPrototype c)) == c
