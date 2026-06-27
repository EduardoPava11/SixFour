{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleInstances #-}
{- |
Module      : SixFour.Spec.GaugeAction
Description : The model's three GAUGE freedoms unified as finite GROUP ACTIONS whose OBSERVABLE is the orbit invariant (the rendered image = the quotient X/G). ONE 'GaugeAction' interface instantiated by structurally different groups — the palette gauge @S_K@ (permute the K colours + remap the index = same pixels), and the @ℤ/2@ channel/ordering involution (swapAB / XOR ordering / phi6) — each with @gobserve (gact g x) == gobserve x@. This is INVARIANT THEORY, not Galois theory: the observable is the ring-of-invariants quotient, there is no field extension, and the palette gauge is NON-ABELIAN @S_K@ (NOT the abelian cyclic Frobenius @Gal(F_{2^8}/F_2) = ℤ/8@), pinned by 'lawPaletteGaugeIsNonAbelian'.

Group ops are class methods (not a 'Monoid' superclass) so the identity can be SIZED by the
configuration — the palette gauge's identity is @[0..K-1]@, which a polymorphic @mempty@ cannot
supply. Subsumes @lawPaletteIndexGaugeInvariant@ (ConstructionEncoder), @lawReorderingPreservesObject@
+ @lawEquivariance@ (SameObjectInvariance), @lawPhi6Involution@ (Dim6) under one law family.
See "SixFour.Spec.RootLatticeDetail" (the lift's lattice algebra) for the sibling generalization.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.GaugeAction
  ( -- * The interface
    Group(..)
  , GaugeAction(..)
    -- * Groups
  , Perm(..)
  , Z2(..)
  , applyPerm
  , composePerm
  , invertPerm
    -- * Configurations
  , PaletteConfig(..)
  , ChannelPair(..)
    -- * Laws
  , lawActIsGroupAction
  , lawGaugeInvertible
  , lawObservableIsOrbitInvariant
  , lawPaletteGaugeIsNonAbelian
  ) where

import Data.List (elemIndex)
import Data.Maybe (fromMaybe)

-- | A minimal GROUP (base stops at 'Monoid', and a polymorphic @mempty@ cannot size the palette
-- identity, so the gauge group's multiplication/inverse live here; the identity is supplied by
-- 'gident', sized by the configuration).
class Group g where
  gcompose :: g -> g -> g       -- ^ group multiplication
  ginvert  :: g -> g            -- ^ group inverse

-- | A finite GAUGE: a group @g@ acting on configurations @x@ whose OBSERVABLE @Obs x@ is the orbit
-- invariant (the rendered image). @x@ determines @g@ (the fundep) and @Obs x@ (the type family).
class Group g => GaugeAction g x | x -> g where
  type Obs x
  gident   :: x -> g            -- ^ the identity gauge, sized by the configuration
  gact     :: g -> x -> x       -- ^ the action
  gobserve :: x -> Obs x        -- ^ the orbit-invariant observable (the rendered image)

-- ---------------------------------------------------------------------------
-- Group 1: the symmetric group S_K, as a finitely-supported permutation (identity outside range).
-- ---------------------------------------------------------------------------

newtype Perm = Perm [Int] deriving (Eq, Show)

-- | Apply a permutation; indices outside the explicit image act as the identity.
applyPerm :: Perm -> Int -> Int
applyPerm (Perm p) i
  | i >= 0 && i < length p = p !! i
  | otherwise              = i

-- | Composition @(p `composePerm` q) = p ∘ q@ (apply q then p), sized to the larger support.
composePerm :: Perm -> Perm -> Perm
composePerm a@(Perm p) b@(Perm q) =
  Perm [ applyPerm a (applyPerm b i) | i <- [0 .. n - 1] ]
  where n = max (length p) (length q)

-- | Inverse permutation on its support.
invertPerm :: Perm -> Perm
invertPerm (Perm p) = Perm [ fromMaybe i (elemIndex i p) | i <- [0 .. length p - 1] ]

instance Group Perm where
  gcompose = composePerm
  ginvert  = invertPerm

-- ---------------------------------------------------------------------------
-- Group 2: ℤ/2 (the swapAB / XOR-ordering / phi6 involution).
-- ---------------------------------------------------------------------------

newtype Z2 = Z2 Bool deriving (Eq, Show)

instance Group Z2 where
  gcompose (Z2 a) (Z2 b) = Z2 (a /= b)          -- XOR
  ginvert  g = g                                -- self-inverse

-- ---------------------------------------------------------------------------
-- Config 1: the palette gauge. (palette, index); the observable is the gather palette[index].
-- ---------------------------------------------------------------------------

-- | A 1-channel (palette, index) configuration (the gauge structure is identical per OKLab channel,
-- so 1 channel is faithful for the gauge laws).
newtype PaletteConfig = PaletteConfig ([Int], [Int]) deriving (Eq, Show)

instance GaugeAction Perm PaletteConfig where
  type Obs PaletteConfig = [Int]
  gident (PaletteConfig (pal, _)) = Perm [0 .. length pal - 1]
  -- permute the palette (pal'[σ i] = pal[i]) AND remap the index (i ↦ σ i): the observable is fixed.
  gact perm (PaletteConfig (pal, idx)) = PaletteConfig (pal', idx')
    where inv  = invertPerm perm
          pal' = [ idxGet pal (applyPerm inv j) | j <- [0 .. length pal - 1] ]
          idx' = map (applyPerm perm) idx
  gobserve (PaletteConfig (pal, idx)) = [ idxGet pal i | i <- idx ]

-- | Safe list index (out-of-range → 0); keeps the gauge total on ragged generated inputs.
idxGet :: [Int] -> Int -> Int
idxGet xs k = if k >= 0 && k < length xs then xs !! k else 0

-- ---------------------------------------------------------------------------
-- Config 2: a channel pair under the ℤ/2 swap; the observable is the unordered pair.
-- ---------------------------------------------------------------------------

newtype ChannelPair = ChannelPair (Int, Int) deriving (Eq, Show)

instance GaugeAction Z2 ChannelPair where
  type Obs ChannelPair = (Int, Int)
  gident _ = Z2 False
  gact (Z2 s) (ChannelPair (a, b)) = ChannelPair (if s then (b, a) else (a, b))
  gobserve (ChannelPair (a, b)) = (min a b, max a b)   -- the swap-invariant

-- ---------------------------------------------------------------------------
-- Laws (non-vacuous; each FAILS if the action/invariance is violated).
-- ---------------------------------------------------------------------------

-- | 'gact' is a genuine group action: a homomorphism @act (g·h) = act g ∘ act h@, and the identity
-- acts trivially.
lawActIsGroupAction :: (GaugeAction g x, Eq x) => g -> g -> x -> Bool
lawActIsGroupAction g h x =
     gact (gcompose g h) x == gact g (gact h x)
  && gact (gident x) x == x

-- | Every gauge element is invertible: @act (g⁻¹) ∘ act g = id@.
lawGaugeInvertible :: (GaugeAction g x, Eq x) => g -> x -> Bool
lawGaugeInvertible g x = gact (ginvert g) (gact g x) == x

-- | THE gauge law: the observable is the ORBIT INVARIANT — acting by any @g@ leaves the rendered
-- image unchanged. The observable factors through the quotient @X/G@ (invariant theory).
lawObservableIsOrbitInvariant :: (GaugeAction g x, Eq (Obs x)) => g -> x -> Bool
lawObservableIsOrbitInvariant g x = gobserve (gact g x) == gobserve x

-- | THE boundary (honest "not Galois"): the palette gauge is the NON-ABELIAN symmetric group @S_K@
-- (@K ≥ 3@), so it is NOT the cyclic abelian Frobenius @Gal(F_{2^8}/F_2) = ℤ/8@. Concrete teeth: two
-- transpositions whose two composition orders give DIFFERENT configurations (non-commuting), yet
-- BOTH preserve the observable (they are still gauges).
lawPaletteGaugeIsNonAbelian :: Bool
lawPaletteGaugeIsNonAbelian =
  let g = Perm [1, 0, 2]   -- swap slots 0 ↔ 1
      h = Perm [0, 2, 1]   -- swap slots 1 ↔ 2
      x = PaletteConfig ([10, 20, 30], [0, 1, 2, 1, 0])
  in gact (gcompose g h) x /= gact (gcompose h g) x        -- non-abelian: g·h ≠ h·g as actions
     && gobserve (gact (gcompose g h) x) == gobserve x      -- yet both gauge the SAME observable
     && gobserve (gact (gcompose h g) x) == gobserve x
