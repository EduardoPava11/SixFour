{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies        #-}

{- |
Module      : SixFour.Spec.LookNetE
Description : L3 encoder — typed Stage with σ-equivariance + permutation-invariance.

The first /learnable/ layer expressed as a typed 'Stage' (mirroring "SixFour.Spec.Pipeline"
for the deterministic stages). The encoder @E@ takes a SET of GMM tokens and pools
them to a 64-D context. Its algebraic obligations:

  1. **Permutation-invariance** (the set-encoder contract): @E(perm s) ≡ E(s)@ for
     any permutation of the tokens. A set has no order; reordering must not
     change the pooled context.

  2. **σ-equivariance** (the chroma-reflection contract): @E ∘ gmmTokenSigma
     ≡ sigma64 ∘ E@. The chroma reflection @(L,a,b) ↦ (L,−a,−b)@ on the input
     tokens must commute with the corresponding 64-D involution on the hidden
     state (the Hurvich-Jameson opponent-channel decomposition,
     'SixFour.Spec.Tensor.sigma64').

Both are stated as 'Stage'-class predicates on a /reference baseline/ encoder
'encoderReference' that satisfies them by construction. The trained encoder is a
controlled deviation: its weights MUST keep both laws within a small tolerance,
or the σ-equivariance proof (the analogue of @option4Theorem@) does not type-check.

== The reference baseline

'encoderReference' is a deterministic, σ-correct, permutation-invariant function
of the token set:

>  E_ref(tokens) = sum_over_tokens (placeToken token)

where @placeToken@ maps each of the 10 GMM-token channels into a specific
hidden-state dim chosen so the σ-classes match: achromatic channels of the token
(μL, ΣLL, Σaa, Σab, Σbb, w) land in the 22 σ-fixed achromatic hidden dims;
red-green chromatic channels (μa, ΣLa) land in the 21 σ-negated red-green dims;
blue-yellow chromatic channels (μb, ΣLb) land in the 21 σ-negated blue-yellow
dims. This is the smallest σ-equivariant embedding that uses every input channel.

This baseline is to L3 what 'SixFour.Spec.LookNet.baselinePalette' is to L5/L6:
a total reference the trained network is a controlled deviation from.

== Why this matters

Without a typed Stage for L3, the σ-equivariance obligation is a comment in
'encoderIO.netDescription'. With it, GHC enforces — at compile time — that the
input/output types are 'gmmTokenSigma'/'sigma64'-shaped, and the QuickCheck
properties enforce — at test time — that the reference baseline really
satisfies its claimed laws. The trainer then has a /hard/ equivariance target
(commute with these fixed involutions), not a heuristic.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.LookNetE
  ( -- * The set / context types (the L3 boundary)
    GmmTokenSet(..)
  , HiddenContext(..)
  , mkGmmTokenSet
  , gmmTokenSetSize
    -- * The encoder Stage
  , L3Encoder
  , encoderReference
    -- * σ-actions on the boundary types
  , sigmaGmmTokenSet
  , sigmaHiddenContext
    -- * The channel-placement map (algebraic, σ-correct by construction)
  , placeToken
  , achromaticChannelSlots
  , redGreenChannelSlots
  , blueYellowChannelSlots
    -- * Laws (predicates; QuickCheck'd in Properties.LookNetE)
  , lawEncoderRefSigmaEquivariance
  , lawEncoderRefPermutationInvariance
  , lawEncoderRefDimensionalContract
  , lawPlacementMapHonoursSigma
  ) where

import           Data.List           (sortOn)
import qualified Data.Vector.Unboxed as U

import SixFour.Spec.Tensor
  ( Tensor1(..), Tensor2(..)
  , gmmTokenSigma, gmmTokenSigmaMask
  , sigma64, sigma64Mask
  , hiddenAchromaticDim, hiddenRedGreenDim, hiddenBlueYellowDim, hiddenDim
  )

-- =============================================================================
-- Boundary types
-- =============================================================================

-- | A set of GMM tokens (the L3 input). Each token is a 10-D vector
-- @[μL, μa, μb, ΣLL, ΣLa, ΣLb, Σaa, Σab, Σbb, w]@ (matching the layout pinned
-- in "SixFour.Spec.GMM"). The list order is irrelevant to the semantics — the
-- set has no order — and 'encoderReference' is permutation-invariant under it.
newtype GmmTokenSet = GmmTokenSet { unGmmTokenSet :: [Tensor1 10 Double] }
  deriving (Eq, Show)

-- | The 64-D hidden context (the L3 output). Single vector; the σ-action on it
-- is 'sigma64' lifted from a 1×64 'Tensor2' (see 'sigmaHiddenContext').
newtype HiddenContext = HiddenContext { unHiddenContext :: Tensor1 64 Double }
  deriving (Eq, Show)

-- | Build a 'GmmTokenSet' from rows, each required to be a 10-D GMM token (@Nothing@ otherwise).
mkGmmTokenSet :: [[Double]] -> Maybe GmmTokenSet
mkGmmTokenSet rows
  | all ((== 10) . length) rows = Just (GmmTokenSet [ Tensor1 (U.fromList r) | r <- rows ])
  | otherwise                   = Nothing

-- | The number of tokens in the set (the pooled per-frame palette count, ≤ @T·K@).
gmmTokenSetSize :: GmmTokenSet -> Int
gmmTokenSetSize (GmmTokenSet xs) = length xs

-- =============================================================================
-- The Stage tag (algebraic, like Pipeline.hs's Bin16 / SymSelect / …)
-- =============================================================================

-- | The L3 encoder tag. There is no value-level data here — 'encoderReference'
-- provides the reference implementation; a trained encoder is a different
-- inhabitant of the same dimensional contract.
data L3Encoder

-- We deliberately do NOT make 'L3Encoder' an instance of 'SixFour.Spec.Pipeline.Stage'
-- in this module to avoid a cyclic import (Pipeline → Tensor would be fine but
-- Pipeline currently imports PairTree / Bottleneck16 / SigmaDecomp; adding it
-- would entangle this leaf module). The integration with the @:>@ composition
-- framework lives in a sibling module @SixFour.Spec.LookNet.Compose@ (to be
-- added when L4/L5 land). The Stage-shaped reference function and the σ/perm
-- actions are exported here so that integration is mechanical.

-- =============================================================================
-- σ-actions on the boundary types
-- =============================================================================

-- | σ on a set of tokens: row-wise 'gmmTokenSigma' (the fixed diagonal
-- involution on the 10-D token, derived from OKLab geometry — see Tensor docs).
-- Stacks the list into a 'Tensor2' to apply, then unstacks. Exact.
sigmaGmmTokenSet :: GmmTokenSet -> GmmTokenSet
sigmaGmmTokenSet (GmmTokenSet xs) =
  GmmTokenSet [ Tensor1 (U.zipWith (\b x -> if b then negate x else x)
                                    (U.fromList gmmTokenSigmaMask)
                                    v)
              | Tensor1 v <- xs ]

-- | σ on the hidden context: 'sigma64' lifted from a 1×64 batch view.
sigmaHiddenContext :: HiddenContext -> HiddenContext
sigmaHiddenContext (HiddenContext (Tensor1 v)) =
  let ms     = U.fromList [ if b then (-1) else 1 | b <- sigma64Mask ]
      vFlip  = U.zipWith (*) v ms
  in HiddenContext (Tensor1 vFlip)

-- =============================================================================
-- The σ-correct channel-placement map (the algebraic baseline embedding)
-- =============================================================================

-- | Hidden dim slots reserved for ACHROMATIC content (the first 22 dims).
achromaticChannelSlots :: [Int]
achromaticChannelSlots = [0 .. hiddenAchromaticDim - 1]                   -- 0..21

-- | Hidden dim slots reserved for RED-GREEN chromatic content (next 21 dims).
redGreenChannelSlots :: [Int]
redGreenChannelSlots =
  [ hiddenAchromaticDim .. hiddenAchromaticDim + hiddenRedGreenDim - 1 ]  -- 22..42

-- | Hidden dim slots reserved for BLUE-YELLOW chromatic content (last 21 dims).
blueYellowChannelSlots :: [Int]
blueYellowChannelSlots =
  [ hiddenAchromaticDim + hiddenRedGreenDim
    .. hiddenAchromaticDim + hiddenRedGreenDim + hiddenBlueYellowDim - 1 ] -- 43..63

-- | The placement map from a 10-D GMM token to its 64-D embedded form. Each of
-- the 10 token channels is placed at a specific hidden dim chosen so the
-- σ-class of the token channel matches the σ-class of the hidden dim:
--
-- >  token chan | quantity | σ-class    | hidden slot
-- >  -----------+----------+------------+-------------
-- >       0     |   μL     | achromatic | 0  (achromatic)
-- >       1     |   μa     | red-green  | 22 (red-green)
-- >       2     |   μb     | blue-yellow| 43 (blue-yellow)
-- >       3     |   ΣLL    | achromatic | 1  (achromatic)
-- >       4     |   ΣLa    | red-green  | 23 (red-green)
-- >       5     |   ΣLb    | blue-yellow| 44 (blue-yellow)
-- >       6     |   Σaa    | achromatic | 2  (achromatic)
-- >       7     |   Σab    | achromatic | 3  (achromatic)
-- >       8     |   Σbb    | achromatic | 4  (achromatic)
-- >       9     |   w      | achromatic | 5  (achromatic)
--
-- Remaining hidden dims (6..21 achromatic, 24..42 red-green, 45..63 blue-yellow)
-- are zero. They will be populated by the TRAINED encoder — the baseline just
-- pins the σ-correct skeleton.
placeToken :: Tensor1 10 Double -> Tensor1 64 Double
placeToken (Tensor1 t) =
  let slots :: [(Int, Int)]
      slots =
        [ (0, 0)    -- μL    → achromatic
        , (1, 22)   -- μa    → red-green
        , (2, 43)   -- μb    → blue-yellow
        , (3, 1)    -- ΣLL   → achromatic
        , (4, 23)   -- ΣLa   → red-green
        , (5, 44)   -- ΣLb   → blue-yellow
        , (6, 2)    -- Σaa   → achromatic
        , (7, 3)    -- Σab   → achromatic
        , (8, 4)    -- Σbb   → achromatic
        , (9, 5)    -- w     → achromatic
        ]
      out = U.replicate 64 0.0 U.// [ (h, t U.! c) | (c, h) <- slots ]
  in Tensor1 out

-- =============================================================================
-- The reference baseline encoder
-- =============================================================================

-- | The reference L3 encoder: place each token into the σ-correct slots
-- ('placeToken'), then sum across the token set. Permutation-invariant by
-- construction (sum is a commutative-monoid operation); σ-equivariant by
-- construction ('placeToken' matches token σ-classes to hidden σ-classes; sum
-- preserves linearity, hence equivariance).
--
-- The empty set maps to the zero context — the only sensible total convention.
encoderReference :: GmmTokenSet -> HiddenContext
encoderReference (GmmTokenSet []) =
  HiddenContext (Tensor1 (U.replicate 64 0.0))
encoderReference (GmmTokenSet xs) =
  let placed     = map placeToken xs
      addV (Tensor1 a) (Tensor1 b) = Tensor1 (U.zipWith (+) a b)
      sumPlaced  = foldr1 addV placed
  in HiddenContext sumPlaced

-- =============================================================================
-- Laws (predicates; QuickCheck'd in Properties.LookNetE)
-- =============================================================================

-- | The reference baseline is σ-equivariant up to floating-point reassociation
-- noise: @encoderReference (sigmaGmmTokenSet s) ≈ sigmaHiddenContext (encoderReference s)@
-- within the supplied tolerance. The algebraic equality is exact for any
-- linear encoder; the tolerance accommodates the @+@ non-associativity on the
-- token-set sum (same caveat as 'SixFour.Spec.Tensor.lawPermutationInvariantReduce').
lawEncoderRefSigmaEquivariance :: Double -> GmmTokenSet -> Bool
lawEncoderRefSigmaEquivariance tol s =
  let HiddenContext (Tensor1 lhs) = encoderReference (sigmaGmmTokenSet s)
      HiddenContext (Tensor1 rhs) = sigmaHiddenContext (encoderReference s)
  in U.length lhs == U.length rhs
     && U.and (U.zipWith (\x y -> abs (x - y) <= tol) lhs rhs)

-- | The reference baseline is permutation-invariant (set semantics): reordering
-- the input tokens does not change the output context, up to FP tolerance.
lawEncoderRefPermutationInvariance :: Double -> [Int] -> GmmTokenSet -> Bool
lawEncoderRefPermutationInvariance tol perm (GmmTokenSet xs) =
  let n      = length xs
      isPerm = length perm == n
            && all (\i -> i >= 0 && i < n) perm
            && length (unique perm) == n
      permed = GmmTokenSet (map (xs !!) perm)
      HiddenContext (Tensor1 a) = encoderReference (GmmTokenSet xs)
      HiddenContext (Tensor1 b) = encoderReference permed
  in not isPerm
     || (U.length a == U.length b
         && U.and (U.zipWith (\x y -> abs (x - y) <= tol) a b))
  where
    unique = map head . groupAdjacent . sortOn id
    groupAdjacent [] = []
    groupAdjacent (x:xs') =
      let (same, rest) = span (== x) xs'
      in (x : same) : groupAdjacent rest

-- | Dimensional contract: input is a set of 10-D tokens; output is one 64-D
-- vector. Pinned at the type level by 'GmmTokenSet' / 'HiddenContext' — this
-- law restates it for the QuickCheck snapshot.
lawEncoderRefDimensionalContract :: Bool
lawEncoderRefDimensionalContract =
  let HiddenContext (Tensor1 v) = encoderReference (GmmTokenSet [])
  in U.length v == 64 && hiddenDim == 64

-- | The placement map honours σ-classes: for each (token channel, hidden slot)
-- pair, the σ-class of the token channel equals the σ-class of the hidden slot.
-- This is the algebraic correctness criterion for 'placeToken' — if any slot
-- were mismatched, the encoder would fail 'lawEncoderRefSigmaEquivariance'.
lawPlacementMapHonoursSigma :: Bool
lawPlacementMapHonoursSigma =
  let slots :: [(Int, Int)]
      slots =
        [ (0, 0), (1, 22), (2, 43), (3, 1), (4, 23), (5, 44)
        , (6, 2), (7, 3), (8, 4), (9, 5) ]
      tokenIsChromatic c  = gmmTokenSigmaMask !! c
      hiddenIsChromatic h = sigma64Mask !! h
  in all (\(c, h) -> tokenIsChromatic c == hiddenIsChromatic h) slots
