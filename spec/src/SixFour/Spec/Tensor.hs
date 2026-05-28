{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies        #-}

{- |
Module      : SixFour.Spec.Tensor
Description : Typed tensors with channel-axis annotations — the math-first NN's leaves.

The algebraic foundation for the look-NN's learnable layers. A tensor here is a
**Naperian** object: @Tensor1 n s ≅ Fin n -> s@ and @Tensor2 n m s ≅ (Fin n × Fin m) -> s@.
Construction is by 'tabulate' (give a function from position to scalar); destruction
is by 'index' (read at a position). The Naperian laws ('lawTabulateIndex1' /
'lawIndexTabulate1') are the categorical statement of "a finite-rank tensor is
exactly an exponential" — and the reason rank-polymorphic operations
(map, zip, set-pool) compose cleanly. See @Naperian functors@ (Gibbons 2017).

== Channel axis (the SoA contract, lifted to algebra)

A tensor's *channel axis* is the axis whose entries are independent quantities
that get stored as PARALLEL arrays on device (the Swift @SoATensor@'s last axis,
padded to multiples of 8). By convention here the channel axis is **always the
last axis**: 'Tensor2 n m s' has @m@ channels of length @n@ each, 'Tensor3 a b c s'
has @c@ channels of length @a*b@ each. The 'HasChannelAxis' class declares this
algebraically and exposes 'channelView' so consumers can iterate channels
independently (mirroring the on-device SIMD8 hot loop one channel at a time).

== σ-action on the 10-D GMM token (the look-NN's primary σ contract)

The GMM token layout (from "SixFour.Spec.GMM") is
@[μL, μa, μb, ΣLL, ΣLa, ΣLb, Σaa, Σab, Σbb, w]@. σ on OKLab is
@(L,a,b) ↦ (L,-a,-b)@; lifted to the covariance via @Σ' = E[(σv)(σv)ᵀ]@ this
negates exactly the cross-terms with an odd number of chromatic indices.
Concretely:

>  channel | quantity | σ-action
>  --------+----------+---------
>     0    |   μL     | fix
>     1    |   μa     | NEGATE
>     2    |   μb     | NEGATE
>     3    |   ΣLL    | fix
>     4    |   ΣLa    | NEGATE
>     5    |   ΣLb    | NEGATE
>     6    |   Σaa    | fix      (two negations)
>     7    |   Σab    | fix      (two negations)
>     8    |   Σbb    | fix      (two negations)
>     9    |   w      | fix

So σ on the 10-D token is a fixed diagonal orthogonal involution; the trainer's
σ-equivariance obligation for L3 is exactly "commute with this involution".
'gmmTokenSigma' exposes the action; 'lawGmmTokenSigmaInvolution' /
'lawGmmTokenSigmaOrthogonal' pin its algebraic properties (involution + isometry).

== Why this module is small

The spec's existing modules use bare @[OKLab]@ / @U.Vector Double@. Lifting them
to typed tensors is a non-breaking *enrichment* — every existing function admits
a typed wrapper without changing its semantics. This module only adds the
algebraic vocabulary the learnable layers need (typed shape, channel axis,
σ-action on the token); the actual L3/L4/L5 'Stage' instances live in their own
modules ('SixFour.Spec.LookNet.E', '.R', '.D') and depend on this one.
-}
module SixFour.Spec.Tensor
  ( -- * Typed tensors (Naperian)
    Tensor1(..)
  , Tensor2(..)
  , Tensor3(..)
    -- * Construction / destruction
  , tabulate1
  , tabulate2
  , tabulate3
  , index1
  , index2
  , index3
  , fromList1
  , fromList2
  , toList1
  , toList2
    -- * Functorial / applicative
  , mapTensor1
  , mapTensor2
  , zipTensor1With
  , zipTensor2With
    -- * Channel axis (the SoA contract)
  , HasChannelAxis(..)
  , channelView
  , sumChannels
    -- * Permutation invariance (the L3 contract)
  , permuteRows2
  , permutationInvariantReduce
    -- * Sizing helpers
  , size1
  , size2
  , size3
    -- * GMM-token σ-action (the L3 σ-equivariance target)
  , gmmTokenSigma
  , gmmTokenSigmaMask
    -- * Hidden-state σ-action (the Hurvich-Jameson opponent-channel decomposition)
  , hiddenAchromaticDim
  , hiddenRedGreenDim
  , hiddenBlueYellowDim
  , hiddenDim
  , sigma64Mask
  , sigma64
    -- * Laws (Naperian round-trip + σ involution + permutation-invariance)
  , lawTabulateIndex1
  , lawIndexTabulate1
  , lawTabulateIndex2
  , lawIndexTabulate2
  , lawChannelViewRecombines
  , lawSumChannelsIsRowSum
  , lawGmmTokenSigmaInvolution
  , lawGmmTokenSigmaOrthogonal
  , lawPermutationInvariantReduce
  , lawSigma64Involution
  , lawSigma64Orthogonal
  , lawSigma64BiologicalRatio
  ) where

import           Data.Kind            (Type)
import           Data.Proxy           (Proxy(..))
import qualified Data.Vector.Unboxed  as U
import           GHC.TypeLits         (Nat, KnownNat, natVal)

-- =============================================================================
-- The typed tensors
-- =============================================================================

-- | Rank-1: @Tensor1 n s ≅ Fin n -> s@. Stored as a flat unboxed vector of
-- length @n@. The Naperian round-trip ('lawTabulateIndex1' / 'lawIndexTabulate1')
-- is exact for @U.Unbox@ scalars.
newtype Tensor1 (n :: Nat) s = Tensor1 { unTensor1 :: U.Vector s }
  deriving (Eq, Show)

-- | Rank-2: @Tensor2 n m s ≅ (Fin n × Fin m) -> s@. Row-major: index @(i, j)@
-- is stored at flat position @i * m + j@. The LAST axis (@m@) is the *channel
-- axis* by convention — this matches the on-device SoA layout where the channel
-- axis is split into parallel SIMD-aligned arrays.
newtype Tensor2 (n :: Nat) (m :: Nat) s = Tensor2 { unTensor2 :: U.Vector s }
  deriving (Eq, Show)

-- | Rank-3: @Tensor3 a b c s ≅ (Fin a × Fin b × Fin c) -> s@. Row-major in the
-- outer two axes; the LAST axis (@c@) is the channel axis.
newtype Tensor3 (a :: Nat) (b :: Nat) (c :: Nat) s = Tensor3 { unTensor3 :: U.Vector s }
  deriving (Eq, Show)

-- =============================================================================
-- Naperian construction / destruction
-- =============================================================================

-- | @tabulate1 f = [f 0, f 1, …, f (n-1)]@. The "exp" of the Naperian iso.
tabulate1
  :: forall n s. (KnownNat n, U.Unbox s)
  => (Int -> s) -> Tensor1 n s
tabulate1 f =
  let n = fromIntegral (natVal (Proxy :: Proxy n)) :: Int
  in Tensor1 (U.generate n f)

-- | @index1 t i@ — read position @i@. Total for @0 ≤ i < n@.
index1 :: U.Unbox s => Tensor1 n s -> Int -> s
index1 (Tensor1 v) i = v U.! i

-- | @tabulate2 f = [f i j]_{i<n, j<m}@ row-major.
tabulate2
  :: forall n m s. (KnownNat n, KnownNat m, U.Unbox s)
  => (Int -> Int -> s) -> Tensor2 n m s
tabulate2 f =
  let n = fromIntegral (natVal (Proxy :: Proxy n)) :: Int
      m = fromIntegral (natVal (Proxy :: Proxy m)) :: Int
  in Tensor2 (U.generate (n * m) (\k -> f (k `div` m) (k `mod` m)))

-- | @index2 t i j@ — read row @i@, channel @j@.
index2
  :: forall n m s. (KnownNat m, U.Unbox s)
  => Tensor2 n m s -> Int -> Int -> s
index2 (Tensor2 v) i j =
  let m = fromIntegral (natVal (Proxy :: Proxy m)) :: Int
  in v U.! (i * m + j)

tabulate3
  :: forall a b c s. (KnownNat a, KnownNat b, KnownNat c, U.Unbox s)
  => (Int -> Int -> Int -> s) -> Tensor3 a b c s
tabulate3 f =
  let na = fromIntegral (natVal (Proxy :: Proxy a)) :: Int
      nb = fromIntegral (natVal (Proxy :: Proxy b)) :: Int
      nc = fromIntegral (natVal (Proxy :: Proxy c)) :: Int
      total = na * nb * nc
  in Tensor3 (U.generate total (\k ->
        let i =  k `div` (nb * nc)
            r =  k `mod` (nb * nc)
            j =  r `div` nc
            l =  r `mod` nc
        in f i j l))

index3
  :: forall a b c s. (KnownNat b, KnownNat c, U.Unbox s)
  => Tensor3 a b c s -> Int -> Int -> Int -> s
index3 (Tensor3 v) i j l =
  let nb = fromIntegral (natVal (Proxy :: Proxy b)) :: Int
      nc = fromIntegral (natVal (Proxy :: Proxy c)) :: Int
  in v U.! (i * nb * nc + j * nc + l)

-- =============================================================================
-- List conversions (for property tests and codegen fixtures)
-- =============================================================================

fromList1 :: forall n s. (KnownNat n, U.Unbox s) => [s] -> Maybe (Tensor1 n s)
fromList1 xs =
  let n = fromIntegral (natVal (Proxy :: Proxy n)) :: Int
  in if length xs == n then Just (Tensor1 (U.fromList xs)) else Nothing

fromList2 :: forall n m s. (KnownNat n, KnownNat m, U.Unbox s) => [[s]] -> Maybe (Tensor2 n m s)
fromList2 rows =
  let n = fromIntegral (natVal (Proxy :: Proxy n)) :: Int
      m = fromIntegral (natVal (Proxy :: Proxy m)) :: Int
  in if length rows == n && all ((== m) . length) rows
       then Just (Tensor2 (U.fromList (concat rows)))
       else Nothing

toList1 :: U.Unbox s => Tensor1 n s -> [s]
toList1 (Tensor1 v) = U.toList v

toList2 :: forall n m s. (KnownNat m, U.Unbox s) => Tensor2 n m s -> [[s]]
toList2 (Tensor2 v) =
  let m = fromIntegral (natVal (Proxy :: Proxy m)) :: Int
  in chunksOf m (U.toList v)
  where
    chunksOf _ [] = []
    chunksOf k xs = let (h, t) = splitAt k xs in h : chunksOf k t

-- =============================================================================
-- Functorial / applicative
-- =============================================================================

mapTensor1 :: (U.Unbox s, U.Unbox t) => (s -> t) -> Tensor1 n s -> Tensor1 n t
mapTensor1 f (Tensor1 v) = Tensor1 (U.map f v)

mapTensor2 :: (U.Unbox s, U.Unbox t) => (s -> t) -> Tensor2 n m s -> Tensor2 n m t
mapTensor2 f (Tensor2 v) = Tensor2 (U.map f v)

zipTensor1With
  :: (U.Unbox s, U.Unbox t, U.Unbox u)
  => (s -> t -> u) -> Tensor1 n s -> Tensor1 n t -> Tensor1 n u
zipTensor1With f (Tensor1 a) (Tensor1 b) = Tensor1 (U.zipWith f a b)

zipTensor2With
  :: (U.Unbox s, U.Unbox t, U.Unbox u)
  => (s -> t -> u) -> Tensor2 n m s -> Tensor2 n m t -> Tensor2 n m u
zipTensor2With f (Tensor2 a) (Tensor2 b) = Tensor2 (U.zipWith f a b)

-- =============================================================================
-- Channel axis (the SoA contract, algebraic)
-- =============================================================================

-- | A tensor that has a designated channel axis (the last axis, by convention).
-- The associated type 'NumChannels' is the channel count; 'ChannelLength' is the
-- length of each parallel channel array. Together they pin the SoA layout used
-- on device: @NumChannels@ parallel buffers, each of @ChannelLength@ scalars
-- (padded to a multiple of 8 in the Swift port — padding is a layout detail not
-- expressed at this algebraic level).
class HasChannelAxis t where
  type NumChannels   t :: Nat
  type ChannelLength t :: Nat
  type Scalar        t :: Type
  -- | Project channel @c@ out as a flat unboxed vector of length 'ChannelLength'.
  -- This is the algebraic version of "read one SoA channel buffer."
  projectChannel :: t -> Int -> U.Vector (Scalar t)

-- Instance for the canonical channel-bearing tensor: Tensor2 n m s, with the
-- LAST axis as the channel axis.
instance (KnownNat n, KnownNat m, U.Unbox s) => HasChannelAxis (Tensor2 n m s) where
  type NumChannels   (Tensor2 n m s) = m
  type ChannelLength (Tensor2 n m s) = n
  type Scalar        (Tensor2 n m s) = s
  projectChannel (Tensor2 v) c =
    let n  = fromIntegral (natVal (Proxy :: Proxy n)) :: Int
        m  = fromIntegral (natVal (Proxy :: Proxy m)) :: Int
    in U.generate n (\i -> v U.! (i * m + c))

-- | All channels as a list of vectors (length = 'NumChannels'). The on-device
-- SoA layout is exactly this list of independent arrays.
channelView
  :: forall t. (HasChannelAxis t, KnownNat (NumChannels t))
  => t -> [U.Vector (Scalar t)]
channelView t =
  let c = fromIntegral (natVal (Proxy :: Proxy (NumChannels t))) :: Int
  in [ projectChannel t k | k <- [0 .. c - 1] ]

-- | Sum each row across channels: @sumChannels t i = Σ_j t[i,j]@.
-- This is the L3 set-pooling operation in microcosm — sum-reduce over the
-- channel axis to a single scalar per row.
sumChannels
  :: forall n m s. (KnownNat n, KnownNat m, Num s, U.Unbox s)
  => Tensor2 n m s -> Tensor1 n s
sumChannels (Tensor2 v) =
  let m = fromIntegral (natVal (Proxy :: Proxy m)) :: Int
      n = fromIntegral (natVal (Proxy :: Proxy n)) :: Int
  in Tensor1 (U.generate n (\i ->
        U.sum (U.slice (i * m) m v)))

-- =============================================================================
-- Permutation invariance (the L3 set-encoder contract)
-- =============================================================================

-- | Permute the rows of a Tensor2 by the given permutation π : [0..n-1] → [0..n-1].
-- The channel axis is untouched. This is the action under which an L3 set encoder
-- must be invariant: a set has no order, so reordering the rows (= tokens) must
-- not change the pooled output.
permuteRows2
  :: forall n m s. (KnownNat n, KnownNat m, U.Unbox s)
  => [Int] -> Tensor2 n m s -> Tensor2 n m s
permuteRows2 perm (Tensor2 v) =
  let n = fromIntegral (natVal (Proxy :: Proxy n)) :: Int
      m = fromIntegral (natVal (Proxy :: Proxy m)) :: Int
  in Tensor2 (U.generate (n * m) (\k ->
        let i  = k `div` m
            j  = k `mod` m
            i' = perm !! i
        in v U.! (i' * m + j)))

-- | A reduction over rows is *permutation-invariant* iff it factors through
-- a commutative monoid on rows. The canonical example is sum-pool. Given any
-- reduction expressed as @(Tensor2 n m s -> Tensor1 m s)@, the law
-- @reduce (permuteRows2 π t) ≡ reduce t@ is the algebraic invariance contract.
-- We expose the sum-pool as the canonical witness: any rank-polymorphic
-- @f :: Tensor1 m s -> r@ composed with 'permutationInvariantReduce' is
-- permutation-invariant by construction.
permutationInvariantReduce
  :: forall n m s. (KnownNat n, KnownNat m, Num s, U.Unbox s)
  => Tensor2 n m s -> Tensor1 m s
permutationInvariantReduce (Tensor2 v) =
  let n = fromIntegral (natVal (Proxy :: Proxy n)) :: Int
      m = fromIntegral (natVal (Proxy :: Proxy m)) :: Int
  in Tensor1 (U.generate m (\j ->
        sum [ v U.! (i * m + j) | i <- [0 .. n - 1] ]))

-- =============================================================================
-- Sizing helpers (used by tests + codegen)
-- =============================================================================

size1 :: forall n s. (KnownNat n) => Tensor1 n s -> Int
size1 _ = fromIntegral (natVal (Proxy :: Proxy n))

size2 :: forall n m s. (KnownNat n, KnownNat m) => Tensor2 n m s -> (Int, Int)
size2 _ = ( fromIntegral (natVal (Proxy :: Proxy n))
          , fromIntegral (natVal (Proxy :: Proxy m)) )

size3 :: forall a b c s. (KnownNat a, KnownNat b, KnownNat c) => Tensor3 a b c s -> (Int, Int, Int)
size3 _ = ( fromIntegral (natVal (Proxy :: Proxy a))
          , fromIntegral (natVal (Proxy :: Proxy b))
          , fromIntegral (natVal (Proxy :: Proxy c)) )

-- =============================================================================
-- σ-action on the 10-D GMM token (the L3 σ-equivariance target)
-- =============================================================================

-- | The mask of which channels of the GMM token flip sign under σ.
-- @True@ = NEGATE; @False@ = fix. Derived from the OKLab reflection
-- @(L,a,b) ↦ (L,-a,-b)@ lifted to the covariance via @Σ' = E[(σv)(σv)ᵀ]@.
-- See module docs for the derivation.
--
-- Layout: @[μL, μa, μb, ΣLL, ΣLa, ΣLb, Σaa, Σab, Σbb, w]@.
--                 0    1    2    3     4    5    6     7    8    9
gmmTokenSigmaMask :: [Bool]
gmmTokenSigmaMask =
  [ False    -- 0: μL    (achromatic, fixed)
  , True     -- 1: μa    (chromatic, negated)
  , True     -- 2: μb    (chromatic, negated)
  , False    -- 3: ΣLL   (LL — no chromatic axis)
  , True     -- 4: ΣLa   (one chromatic axis — negated)
  , True     -- 5: ΣLb   (one chromatic axis — negated)
  , False    -- 6: Σaa   (two chromatic axes — double negation cancels)
  , False    -- 7: Σab   (two chromatic axes — double negation cancels)
  , False    -- 8: Σbb   (two chromatic axes — double negation cancels)
  , False    -- 9: w     (scalar weight — fixed)
  ]

-- | Apply σ to a Tensor2 of GMM tokens (@n@ tokens × 10 channels). Per-channel:
-- flip the sign of channels marked True in 'gmmTokenSigmaMask'. This is a fixed
-- diagonal orthogonal involution on R^10, lifted row-wise to the @(n,10)@ token
-- tensor. Any trained L3 encoder @E@ must satisfy
-- @E ∘ gmmTokenSigma ≡ sigma64 ∘ E@ for the corresponding 64-D σ on the
-- hidden state (the trainer's σ-equivariance obligation — see
-- 'SixFour.Spec.LookNet.E' once that module lands).
gmmTokenSigma
  :: forall n. KnownNat n
  => Tensor2 n 10 Double -> Tensor2 n 10 Double
gmmTokenSigma (Tensor2 v) =
  let n  = fromIntegral (natVal (Proxy :: Proxy n)) :: Int
      ms = U.fromList [ if b then (-1) else 1 | b <- gmmTokenSigmaMask ]
  in Tensor2 (U.generate (n * 10) (\k ->
        let j = k `mod` 10 in (v U.! k) * (ms U.! j)))

-- =============================================================================
-- Hidden-state σ-action: the Hurvich-Jameson opponent-channel decomposition
-- =============================================================================
--
-- The 64-D hidden state of the L3 encoder / L4 core / L5 decoder is split into
-- three groups matching the opponent-color organisation of biological vision
-- (Hurvich & Jameson 1957; LGN/V1 neurophysiology; sparse-coding analysis of
-- natural images, Caywood et al. 2000):
--
--   * 22 dims encode achromatic content  (L-axis-aligned; σ-FIXED)
--   * 21 dims encode red-green opponent  (a-axis-aligned; σ-NEGATED)
--   * 21 dims encode blue-yellow opponent (b-axis-aligned; σ-NEGATED)
--
-- The 22:42 ratio is the closest 1:2 (biological achromatic:chromatic) split
-- that fits the power-of-2 width @modelDim = 64@ (SIMD8 + ANE alignment). The
-- two chromatic groups have EQUAL dimension because red-green and blue-yellow
-- are symmetric under hue rotation in OKLab — they must occupy the same number
-- of dims for the hidden state to admit a clean SO(2) hue-rotation action
-- (Lengyel et al., Color-Equivariant CNNs, NeurIPS 2023).
--
-- Why this matters for /beauty/: Ou & Luo's two-colour harmony model (2006)
-- finds pairs harmonious when SIMILAR IN HUE × DIFFERENT IN LIGHTNESS × HIGH
-- COMBINED LIGHTNESS. Mapped to this decomposition, the 22 achromatic dims
-- encode the LIGHTNESS-asymmetry axis that the σ-pair structure controls
-- (the @parent ± δ@ Haar offset moves through these dims); the 42 chromatic
-- dims encode the HUE-similarity axis that the pair's two leaves share. Beauty
-- becomes the algebraic statement "σ-pairs maximise chromatic similarity while
-- modulating achromatic offset" — and this hidden-state structure is what makes
-- that statement expressible at all.

-- | Number of σ-FIXED (achromatic, L-axis-aligned) dimensions in the hidden state.
hiddenAchromaticDim :: Int
hiddenAchromaticDim = 22

-- | Number of σ-NEGATED dims aligned with the red-green opponent axis.
hiddenRedGreenDim :: Int
hiddenRedGreenDim = 21

-- | Number of σ-NEGATED dims aligned with the blue-yellow opponent axis.
hiddenBlueYellowDim :: Int
hiddenBlueYellowDim = 21

-- | Total hidden-state width: @22 + 21 + 21 = 64@ (= 'modelDim' in LookNet).
-- Kept as a power of 2 for SIMD8 stripe alignment + ANE friendliness.
hiddenDim :: Int
hiddenDim = hiddenAchromaticDim + hiddenRedGreenDim + hiddenBlueYellowDim

-- | The σ-mask on the 64-D hidden state. @False@ = fix (achromatic); @True@ =
-- negate (chromatic). Layout: first 22 dims are achromatic, next 21 are
-- red-green-aligned, last 21 are blue-yellow-aligned. The two chromatic groups
-- are mask-identical for the σ-action (both flip sign), but they are kept
-- distinct in layout so future modules can apply per-group operations (e.g. a
-- hue-rotation SO(2) action would mix the two chromatic groups but leave the
-- achromatic group untouched).
sigma64Mask :: [Bool]
sigma64Mask =
     replicate hiddenAchromaticDim  False   -- 22 achromatic, σ-fixed
  ++ replicate hiddenRedGreenDim    True    -- 21 red-green, σ-negated
  ++ replicate hiddenBlueYellowDim  True    -- 21 blue-yellow, σ-negated

-- | Apply σ to a 64-D hidden-state vector (or a batch of them). Per-channel:
-- flip the sign of channels marked True in 'sigma64Mask'. Fixed diagonal
-- orthogonal involution; the trainer must learn weights such that
-- @E ∘ gmmTokenSigma ≡ sigma64 ∘ E@ (the σ-equivariance obligation for L3).
sigma64
  :: forall n. KnownNat n
  => Tensor2 n 64 Double -> Tensor2 n 64 Double
sigma64 (Tensor2 v) =
  let n  = fromIntegral (natVal (Proxy :: Proxy n)) :: Int
      ms = U.fromList [ if b then (-1) else 1 | b <- sigma64Mask ]
  in Tensor2 (U.generate (n * 64) (\k ->
        let j = k `mod` 64 in (v U.! k) * (ms U.! j)))

-- =============================================================================
-- Laws (predicates; QuickCheck'd in Properties.Tensor)
-- =============================================================================

-- | Naperian round-trip 1: @index1 (tabulate1 f) i ≡ f i@ for all @i ∈ [0, n)@.
lawTabulateIndex1 :: forall n. KnownNat n => (Int -> Double) -> Bool
lawTabulateIndex1 f =
  let n = fromIntegral (natVal (Proxy :: Proxy n)) :: Int
      t = tabulate1 @n f
  in and [ index1 t i == f i | i <- [0 .. n - 1] ]

-- | Naperian round-trip 2: @tabulate1 (index1 t) ≡ t@. The "exp ∘ log = id"
-- direction — pins that the unboxed-vector storage exactly represents the
-- Fin-n function.
lawIndexTabulate1 :: forall n. KnownNat n => Tensor1 n Double -> Bool
lawIndexTabulate1 t = tabulate1 @n (index1 t) == t

-- | Naperian round-trip 1 for Tensor2: @index2 (tabulate2 f) i j ≡ f i j@.
lawTabulateIndex2 :: forall n m. (KnownNat n, KnownNat m) => (Int -> Int -> Double) -> Bool
lawTabulateIndex2 f =
  let n = fromIntegral (natVal (Proxy :: Proxy n)) :: Int
      m = fromIntegral (natVal (Proxy :: Proxy m)) :: Int
      t = tabulate2 @n @m f
  in and [ index2 t i j == f i j | i <- [0 .. n - 1], j <- [0 .. m - 1] ]

-- | Naperian round-trip 2 for Tensor2: @tabulate2 (index2 t) ≡ t@.
lawIndexTabulate2 :: forall n m. (KnownNat n, KnownNat m) => Tensor2 n m Double -> Bool
lawIndexTabulate2 t = tabulate2 @n @m (index2 t) == t

-- | The SoA contract: 'channelView' followed by row-major recombination yields
-- the original tensor. Pins that the on-device "parallel arrays per channel"
-- storage is algebraically equivalent to the spec's row-major 'Tensor2'.
lawChannelViewRecombines
  :: forall n m. (KnownNat n, KnownNat m)
  => Tensor2 n m Double -> Bool
lawChannelViewRecombines t =
  let cs = channelView t
      n  = fromIntegral (natVal (Proxy :: Proxy n)) :: Int
      m  = fromIntegral (natVal (Proxy :: Proxy m)) :: Int
      recombined = Tensor2
        (U.generate (n * m) (\k ->
           let i = k `div` m
               j = k `mod` m
           in (cs !! j) U.! i))
        :: Tensor2 n m Double
  in recombined == t

-- | 'sumChannels' equals the explicit row sum @Σ_j t[i,j]@ over channels.
-- A sanity law for the reduction operation any L3 set-encoder relies on.
lawSumChannelsIsRowSum
  :: forall n m. (KnownNat n, KnownNat m)
  => Tensor2 n m Double -> Bool
lawSumChannelsIsRowSum t =
  let n   = fromIntegral (natVal (Proxy :: Proxy n)) :: Int
      m   = fromIntegral (natVal (Proxy :: Proxy m)) :: Int
      r   = sumChannels t
      ref = [ sum [ index2 t i j | j <- [0 .. m - 1] ] | i <- [0 .. n - 1] ]
  in toList1 r == ref

-- | σ on the GMM token is an involution: @gmmTokenSigma ∘ gmmTokenSigma ≡ id@.
-- Exact (each channel's sign factor is ±1 and (±1)² = 1 in 'Double').
lawGmmTokenSigmaInvolution
  :: forall n. KnownNat n
  => Tensor2 n 10 Double -> Bool
lawGmmTokenSigmaInvolution t = gmmTokenSigma (gmmTokenSigma t) == t

-- | σ on the GMM token is orthogonal: it preserves the Euclidean norm of every
-- token row (and hence of the whole tensor). Exact — sign flips don't change
-- squared magnitudes.
lawGmmTokenSigmaOrthogonal
  :: forall n. KnownNat n
  => Tensor2 n 10 Double -> Bool
lawGmmTokenSigmaOrthogonal t =
  let normSq (Tensor2 v) = U.sum (U.map (\x -> x * x) v)
  in normSq t == normSq (gmmTokenSigma t)

-- | σ on the 64-D hidden state is an involution: @sigma64 ∘ sigma64 ≡ id@.
-- Exact (sign flips squared = 1).
lawSigma64Involution
  :: forall n. KnownNat n
  => Tensor2 n 64 Double -> Bool
lawSigma64Involution t = sigma64 (sigma64 t) == t

-- | σ on the 64-D hidden state is orthogonal: preserves Euclidean norm.
-- Exact (sign flips don't change squared magnitudes).
lawSigma64Orthogonal
  :: forall n. KnownNat n
  => Tensor2 n 64 Double -> Bool
lawSigma64Orthogonal t =
  let normSq (Tensor2 v) = U.sum (U.map (\x -> x * x) v)
  in normSq t == normSq (sigma64 t)

-- | The Hurvich-Jameson biological-ratio invariant: 22 achromatic dims, 42
-- chromatic dims (21 red-green + 21 blue-yellow), summing to exactly 64. The
-- chromatic ratio is exactly 22:42 ≈ 1:1.91, the closest power-of-2-width
-- approximation of biological 1:2.
lawSigma64BiologicalRatio :: Bool
lawSigma64BiologicalRatio =
     hiddenAchromaticDim == 22
  && hiddenRedGreenDim   == 21
  && hiddenBlueYellowDim == 21
  && hiddenDim           == 64
  && length sigma64Mask  == 64
  && length (filter not sigma64Mask) == hiddenAchromaticDim
  && length (filter id  sigma64Mask) == (hiddenRedGreenDim + hiddenBlueYellowDim)
  && hiddenRedGreenDim   == hiddenBlueYellowDim  -- SO(2) hue-rotation symmetry

-- | The canonical sum-pool reduction is permutation-invariant *up to floating-
-- point reassociation noise*: @permutationInvariantReduce (permuteRows2 π t) ≈
-- permutationInvariantReduce t@ within the supplied tolerance, for any
-- permutation π of the @n@ rows.
--
-- The algebraic claim is exact (sum is a commutative-monoid operation on the
-- abstract reals), but @Double@ realises only a *near*-commutative monoid —
-- @(a+b)+c@ may differ from @(c+a)+b@ at ULP level because @+@ is non-associative
-- on floating point. The spec records this honestly via the @tol@ parameter,
-- mirroring 'SixFour.Spec.PairTree.lawReconstructAnalyzeRoundTrip'. A tolerance
-- of @1e-12@ holds for unit-bounded entries and rank up to a few hundred.
lawPermutationInvariantReduce
  :: forall n m. (KnownNat n, KnownNat m)
  => Double -> [Int] -> Tensor2 n m Double -> Bool
lawPermutationInvariantReduce tol perm t =
  let n      = fromIntegral (natVal (Proxy :: Proxy n)) :: Int
      isPerm = length perm == n
            && all (\i -> i >= 0 && i < n) perm
            && length (unique perm) == n
      Tensor1 a = permutationInvariantReduce (permuteRows2 perm t)
      Tensor1 b = permutationInvariantReduce t
      closeEnough = U.length a == U.length b
                 && U.and (U.zipWith (\x y -> abs (x - y) <= tol) a b)
  in not isPerm || closeEnough
  where
    unique []     = []
    unique (x:xs) = x : unique (filter (/= x) xs)
