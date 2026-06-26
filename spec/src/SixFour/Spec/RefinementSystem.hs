{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE FlexibleInstances #-}
{- |
Module      : SixFour.Spec.RefinementSystem
Description : The capstone of the algebraic generalization: the spine triad @CommutativeRing → RModule → ReversibleLift@ that makes the model's scattered structures INSTANCES of one base-ring abstraction. The current model is the @R = ℤ@ (Q16), rank-3 (OKLab), branching-8 (dyadic octant) corner; the SAME laws hold over @R = ℤ[i]@ (the Gaussian integers, ring of integers of ℚ(i) — the "Gaussian-chroma" knob) and over a non-dyadic @b = 3@ lift, which is what proves this is a GENERALIZATION, not a rename.

The field axiom is ABSENT BY DESIGN ('CommutativeRing' has no @recip@): byte-exactness forbids
dividing by non-units, so the model lives in module theory over a ring of integers, not linear
algebra over a field. 'RModule' is the @ColourDelta@ carrier abstracted (a free module over R);
'ReversibleLift' is the per-node multiresolution bijection whose detail count is @b-1@ (the rank of
the root lattice @A_{b-1}@ in "SixFour.Spec.RootLatticeDetail"). See "SixFour.Spec.RingReduction"
(the float↔device crossing over these rings) and "SixFour.Spec.ScaleFiltration" (the dyadic tower).

HONEST BOUNDARY (doc): the realizer 'liftVec' is the prefix-difference lifting scheme (ONE reversible
bijection); the shipped averaging @sLift@ is another. The class law is the BIJECTION
(@unlift ∘ lift = id@), the structural content; per-element R-linearity of the floored shipped lift
is NOT claimed (see RootLatticeDetail).
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.RefinementSystem
  ( -- * The base ring R (deliberately NOT a field)
    CommutativeRing(..)
  , Gaussian(..)
    -- * Free modules over R (the ColourDelta carrier, abstracted)
  , RModule(..)
  , Triple(..)
    -- * The per-node reversible multiresolution lift
  , ReversibleLift(..)
  , liftVec
  , unliftVec
  , Dyad8(..)
  , Tern3(..)
    -- * Ring laws
  , lawRingAddAssoc, lawRingAddComm, lawRingAddIdentity, lawRingAddInverse
  , lawRingMulAssoc, lawRingMulComm, lawRingMulIdentity, lawRingDistrib
    -- * Module laws
  , lawModuleAddInverse, lawModuleSmulOne, lawModuleSmulMul
  , lawModuleSmulDistribModule, lawModuleSmulDistribRing
    -- * Lift laws
  , lawLiftRoundTrips, lawFromToVec, lawLiftDetailCount, lawLiftFRoundTrips
  ) where

-- | A commutative ring with unit — and DELIBERATELY no multiplicative inverse (not a field). The
-- top knob of the whole generalization: choosing @r@ chooses the coefficient ring.
class CommutativeRing r where
  rzero :: r
  rone  :: r
  radd  :: r -> r -> r
  rmul  :: r -> r -> r
  rneg  :: r -> r

-- | The canonical base ring: @ℤ@ (the Q16 substrate; units only @±1@, so NOT a field).
instance CommutativeRing Integer where
  rzero = 0
  rone  = 1
  radd  = (+)
  rmul  = (*)
  rneg  = negate

-- | The SECOND base ring: the Gaussian integers @ℤ[i] = a + b·i@, the ring of integers of @ℚ(i)@ —
-- a genuine commutative ring (Euclidean domain) distinct from @ℤ@. This is the "Gaussian-chroma"
-- knob the generalization unlocks; its existence proves 'RModule'/'CommutativeRing' generalize.
newtype Gaussian = Gaussian (Integer, Integer) deriving (Eq, Show)

instance CommutativeRing Gaussian where
  rzero = Gaussian (0, 0)
  rone  = Gaussian (1, 0)
  radd (Gaussian (a, b)) (Gaussian (c, d)) = Gaussian (a + c, b + d)
  rmul (Gaussian (a, b)) (Gaussian (c, d)) = Gaussian (a * c - b * d, a * d + b * c)
  rneg (Gaussian (a, b)) = Gaussian (negate a, negate b)

-- | A free module over the ring @r@ (the carrier @m@ determines @r@). The @ColourDelta@ algebra,
-- abstracted away from @ℤ@ OKLab to any base ring.
class CommutativeRing r => RModule r m | m -> r where
  mzero :: m
  madd  :: m -> m -> m
  mneg  :: m -> m
  smul  :: r -> m -> m

-- | A rank-3 free module over @r@ (the OKLab colour triple = the ColourDelta carrier). ONE instance
-- universally quantified over the ring gives both @Triple Integer@ (ℤ³, the real ColourDelta) and
-- @Triple Gaussian@ (ℤ[i]³, Gaussian chroma) as concrete instantiations.
data Triple r = Triple r r r deriving (Eq, Show)

instance CommutativeRing r => RModule r (Triple r) where
  mzero = Triple rzero rzero rzero
  madd (Triple a b c) (Triple d e f) = Triple (radd a d) (radd b e) (radd c f)
  mneg (Triple a b c) = Triple (rneg a) (rneg b) (rneg c)
  smul r (Triple a b c) = Triple (rmul r a) (rmul r b) (rmul r c)

-- | A per-node reversible multiresolution lift on a @b@-vector: @lift@ splits into @(coarse, b-1
-- detail)@, @unlift@ rebuilds, and the two are mutually inverse (the structural bijection).
class ReversibleLift f where
  liftBranching :: f -> Int      -- ^ b (the carrier's fixed size)
  toVec         :: f -> [Integer]
  fromVec       :: [Integer] -> f
  -- | The carrier's OWN reversible split into @(coarse, b-1 detail)@. DEFAULT = the module-level
  -- prefix-difference 'liftVec' over 'toVec', so a carrier with no special structure (e.g. 'Dyad8',
  -- 'Tern3') inherits the generic scheme for free. A carrier with a DIFFERENT exact integer
  -- bijection — the averaging octant S-transform @OctreeCell.liftOct@ — OVERRIDES this method, which
  -- is what makes the 'ReversibleLift' abstraction GOVERN that real lift rather than merely run a
  -- parallel scheme beside it.
  liftF   :: f -> (Integer, [Integer])
  liftF   = liftVec . toVec
  -- | The exact inverse of 'liftF' (DEFAULT = 'fromVec' over 'unliftVec'). An overriding instance
  -- must keep @unliftF . liftF = id@ ('lawLiftFRoundTrips').
  unliftF :: (Integer, [Integer]) -> f
  unliftF = fromVec . unliftVec

-- | The prefix-difference lifting scheme: @coarse = x0@, @detail_i = x_{i+1} − x_i@ (the @b-1@
-- consecutive differences). Reversible over @ℤ@ with no division.
liftVec :: [Integer] -> (Integer, [Integer])
liftVec []       = (0, [])
liftVec (x : xs) = (x, zipWith subtract (x : xs) xs)   -- subtract a b = b - a → x_{i+1} - x_i

-- | The inverse: prefix-sum the coarse value with the detail differences.
unliftVec :: (Integer, [Integer]) -> [Integer]
unliftVec (c, ds) = scanl (+) c ds

-- | The shipped 2×2×2 octant carrier: @b = 8@ (dyadic).
newtype Dyad8 = Dyad8 [Integer] deriving (Eq, Show)

instance ReversibleLift Dyad8 where
  liftBranching _ = 8
  toVec (Dyad8 xs) = xs
  fromVec = Dyad8

-- | A NON-DYADIC carrier: @b = 3@ (ternary). Its existence proves the lift generalizes off powers
-- of two — the capability the current octant-only code cannot express.
newtype Tern3 = Tern3 [Integer] deriving (Eq, Show)

instance ReversibleLift Tern3 where
  liftBranching _ = 3
  toVec (Tern3 xs) = xs
  fromVec = Tern3

-- ---------------------------------------------------------------------------
-- Ring laws (tested at BOTH Integer and Gaussian).
-- ---------------------------------------------------------------------------

lawRingAddAssoc :: (CommutativeRing r, Eq r) => r -> r -> r -> Bool
lawRingAddAssoc a b c = radd (radd a b) c == radd a (radd b c)

lawRingAddComm :: (CommutativeRing r, Eq r) => r -> r -> Bool
lawRingAddComm a b = radd a b == radd b a

lawRingAddIdentity :: (CommutativeRing r, Eq r) => r -> Bool
lawRingAddIdentity a = radd a rzero == a && radd rzero a == a

lawRingAddInverse :: (CommutativeRing r, Eq r) => r -> Bool
lawRingAddInverse a = radd a (rneg a) == rzero

lawRingMulAssoc :: (CommutativeRing r, Eq r) => r -> r -> r -> Bool
lawRingMulAssoc a b c = rmul (rmul a b) c == rmul a (rmul b c)

lawRingMulComm :: (CommutativeRing r, Eq r) => r -> r -> Bool
lawRingMulComm a b = rmul a b == rmul b a

lawRingMulIdentity :: (CommutativeRing r, Eq r) => r -> Bool
lawRingMulIdentity a = rmul a rone == a && rmul rone a == a

lawRingDistrib :: (CommutativeRing r, Eq r) => r -> r -> r -> Bool
lawRingDistrib a b c = rmul a (radd b c) == radd (rmul a b) (rmul a c)

-- ---------------------------------------------------------------------------
-- Module laws (tested at Triple Integer and Triple Gaussian).
-- ---------------------------------------------------------------------------

lawModuleAddInverse :: (RModule r m, Eq m) => m -> Bool
lawModuleAddInverse x = madd x (mneg x) == mzero

lawModuleSmulOne :: (RModule r m, Eq m) => m -> Bool
lawModuleSmulOne x = smul rone x == x

lawModuleSmulMul :: (RModule r m, Eq m) => r -> r -> m -> Bool
lawModuleSmulMul a b x = smul (rmul a b) x == smul a (smul b x)

lawModuleSmulDistribModule :: (RModule r m, Eq m) => r -> m -> m -> Bool
lawModuleSmulDistribModule r x y = smul r (madd x y) == madd (smul r x) (smul r y)

lawModuleSmulDistribRing :: (RModule r m, Eq m) => r -> r -> m -> Bool
lawModuleSmulDistribRing a b x = smul (radd a b) x == madd (smul a x) (smul b x)

-- ---------------------------------------------------------------------------
-- Lift laws (tested at Dyad8 (b=8) and Tern3 (b=3)).
-- ---------------------------------------------------------------------------

-- | The lift is a BIJECTION: @unlift ∘ lift = id@ on the carrier.
lawLiftRoundTrips :: (ReversibleLift f, Eq f) => f -> Bool
lawLiftRoundTrips x = fromVec (unliftVec (liftVec (toVec x))) == x

-- | The carrier representation round-trips: @fromVec ∘ toVec = id@.
lawFromToVec :: (ReversibleLift f, Eq f) => f -> Bool
lawFromToVec x = fromVec (toVec x) == x

-- | The detail count is @b − 1@ (= rank @A_{b-1}@), for a carrier filled to its branching: a
-- full-size @b@-vector lifts to @b-1@ detail bands.
lawLiftDetailCount :: ReversibleLift f => f -> Bool
lawLiftDetailCount x =
  let b  = liftBranching x
      xs = take b (toVec x ++ repeat 0)        -- pad/truncate to exactly b
  in length (snd (liftVec xs)) == b - 1

-- | The carrier's OWN lift is a BIJECTION: @unliftF . liftF = id@. Holds for the default
-- prefix-difference scheme AND for any instance that overrides 'liftF'/'unliftF' with a different
-- exact bijection (e.g. the averaging octant S-transform). This is the law that lets the
-- abstraction govern a real, non-generic lift: the overriding instance owes exactly this.
lawLiftFRoundTrips :: (ReversibleLift f, Eq f) => f -> Bool
lawLiftFRoundTrips x = unliftF (liftF x) == x
