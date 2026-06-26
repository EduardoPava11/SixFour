{- |
Module      : SixFour.Spec.TransportGroup
Description : The POLICY channel's algebra: @IndexDelta@ as a NON-ABELIAN transport group acting on the finite index set. Where the VALUE channel @ColourDelta@ ("SixFour.Spec.RefinementSystem" 'RModule') is an abelian ℤ-module whose deltas ADD, the policy channel's deltas COMPOSE BY CHAINING (@5↦7@ then @7↦2@ gives @5↦2@, never @7+2@) and the order matters (non-abelian). A transport is a permutation of slots; @tapply@ acts on an index map, @tcomp@ chains, @tinv@ reverses, and @tbetween x y@ data-manufactures the transport carrying @x@ to @y@.

This completes the algebraic generalization: the two delta channels are the two faces of the
@HierarchicalDelta@ — VALUE = an abelian module (addition), POLICY = a non-abelian transport group
(chaining). The distinction is a LAW ('lawCompositionIsChainingNotAddition'), not a comment, so the
spec fails if the policy channel is ever modeled as additive. Re-homes the @IndexDelta@ laws
(@lawIndexDeltaIdentity@/@lawIndexDeltaActionHomomorphism@/@lawIndexDeltaInverse@/
@lawIndexCompositionIsNotAddition@) under one structure.
-}
module SixFour.Spec.TransportGroup
  ( -- * Transports (permutations of the slot set)
    Transport
  , tid
  , tapplySlot
  , tapply
  , tcomp
  , tinv
  , tbetween
    -- * Laws
  , lawTransportActionIdentity
  , lawTransportActionHomomorphism
  , lawTransportInverse
  , lawTransportBetweenManufactures
  , lawTransportNonAbelian
  , lawCompositionIsChainingNotAddition
  ) where

import Data.Maybe (fromMaybe)

-- | A transport: a permutation of the slot labels, as the image of @[0..k-1]@ (identity outside).
type Transport = [Int]

-- | The identity transport (acts as the identity on every slot).
tid :: Transport
tid = []

-- | Apply a transport to one slot; slots outside the explicit image are fixed.
tapplySlot :: Transport -> Int -> Int
tapplySlot t s
  | s >= 0 && s < length t = t !! s
  | otherwise              = s

-- | Apply a transport to an index map (relabel every slot the map points at).
tapply :: Transport -> [Int] -> [Int]
tapply t = map (tapplySlot t)

-- | Composition by CHAINING: @tapply (tcomp a b) = tapply a . tapply b@ (apply b, then a).
tcomp :: Transport -> Transport -> Transport
tcomp a b = [ tapplySlot a (tapplySlot b i) | i <- [0 .. n - 1] ]
  where n = max (length a) (length b)

-- | The inverse transport on its support.
tinv :: Transport -> Transport
tinv t = [ fromMaybe i (lookupIndex i t) | i <- [0 .. length t - 1] ]
  where lookupIndex v xs = lookup v (zip xs [0 ..])

-- | The transport that carries index map @x@ to @y@ (data manufacture): map each slot value that
-- appears in @x@ to its partner in @y@; identity elsewhere. Well-defined when @x ↦ y@ is consistent.
tbetween :: [Int] -> [Int] -> Transport
tbetween x y = [ fromMaybe i (lookup i pairs) | i <- [0 .. n - 1] ]
  where
    pairs = zip x y
    n     = 1 + maximum (0 : x ++ y)

-- ---------------------------------------------------------------------------
-- Laws (action-level, so transport representation equality is never needed).
-- ---------------------------------------------------------------------------

-- | The identity transport acts trivially.
lawTransportActionIdentity :: [Int] -> Bool
lawTransportActionIdentity m = tapply tid m == m

-- | @tapply@ is a group ACTION: @tapply (tcomp a b) = tapply a . tapply b@.
lawTransportActionHomomorphism :: Transport -> Transport -> [Int] -> Bool
lawTransportActionHomomorphism a b m =
  tapply (tcomp a b) m == tapply a (tapply b m)

-- | Every transport is invertible: @tcomp (tinv a) a@ acts as the identity (on slots in range).
lawTransportInverse :: Transport -> [Int] -> Bool
lawTransportInverse a m0 =
  let k  = length a
      m  = map (\s -> if k == 0 then s else s `mod` k) m0   -- keep slots within a's support
  in tapply (tcomp (tinv a) a) m == m

-- | DATA MANUFACTURE: the transport built from @(x,y)@ carries @x@ to @y@. (@y@ is derived
-- consistently from @x@ via a permutation, so the pairing is well-defined.)
lawTransportBetweenManufactures :: Transport -> [Int] -> Bool
lawTransportBetweenManufactures sigma x =
  let y = tapply sigma x
  in tapply (tbetween x y) x == y

-- | NON-ABELIAN: order matters. Two transpositions on 3 slots disagree depending on order.
lawTransportNonAbelian :: Bool
lawTransportNonAbelian =
  let a = [1, 0, 2]   -- (0 1)
      b = [0, 2, 1]   -- (1 2)
  in tapply (tcomp a b) [1] /= tapply (tcomp b a) [1]

-- | THE distinction from the VALUE channel: policy deltas COMPOSE BY CHAINING, NOT by adding their
-- slot values. Two 3-cycles chain to @[2,0,1]@; their elementwise SUM is @[2,4,0]@ — different. So
-- @IndexDelta@ is a transport group, NOT the abelian @ColourDelta@ ℤ-module.
lawCompositionIsChainingNotAddition :: Bool
lawCompositionIsChainingNotAddition =
  let d1 = [1, 2, 0]                                  -- the 3-cycle (0 1 2)
      d2 = [1, 2, 0]
      chained = tcomp d2 d1                           -- d2 ∘ d1 = [2,0,1]
      added   = zipWith (+) d1 d2                     -- [2,4,0]
  in chained /= added && chained == [2, 0, 1]
