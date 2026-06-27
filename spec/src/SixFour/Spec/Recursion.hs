{-# LANGUAGE DeriveFunctor #-}

{- |
Module      : SixFour.Spec.Recursion
Description : The boot-only recursion-scheme home — @Fix@/@cata@/@ana@/@hylo@/@meta@ — so the fixpoint vocabulary is declared ONCE and the multiresolution lift can be NAMED (a capture catamorphism, a reconstruct anamorphism, the codec a metamorphism) instead of re-deriving @Fix@ privately in every module.

This module is the one shared fixpoint foundation. It contains ONLY the schemes that have
≥2 honest consumers in the spec — the structural fold 'cata' and unfold 'ana' (the octree
collapse/lift in "SixFour.Spec.OctreeCell"), their fused composite 'hylo', and 'meta' (Gibbons'
metamorphism: a fold that fully completes, then an unfold) which NAMES the capture→reconstruct
PAIR as one object.

WHAT THIS MODULE DELIBERATELY DOES NOT EXPORT (the anti-jargon boundary):

  * @apo@\/@para@\/@histo@\/@futu@ — each had exactly one proposed call site (jargon-by-absence),
    and @histo@ is the wrong direction for "read at depth n" (it carries FINER children; the
    coarser ancestors a depth-read needs already come from "SixFour.Spec.ScaleFiltration"
    @valuation@). They are admitted only if a SECOND real consumer appears.

  * The metamorphism naming is DOCUMENTATION, not a free theorem. 'meta' asserts NOTHING about
    mutual-inverseness: @ana coalg . cata alg@ is not @id@ for arbitrary @alg@\/@coalg@. The
    reversibility of the shipped lift stays a TESTED bijection law
    ("SixFour.Spec.OctreeCell" @lawOctantLadderBijective@), never "structural by construction" —
    the floored @sLift@ is a SET-bijection, not a ℤ-module homomorphism
    ("SixFour.Spec.RootLatticeDetail" honest boundary).

Boot-only: @base@ only (no @recursion-schemes@\/@free@\/@comonad@). ~30 lines of combinators.
The laws below pin the combinators against a sample 'ListF' functor (non-vacuous: a mis-defined
'hylo' or 'ana' fails them). The law that NAMES a real shipped pair lives with that pair
("SixFour.Spec.OctreeCell" @lawOctantBuildFlattenIsHylo@).
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.Recursion
  ( -- * The fixpoint and its morphisms (the only public surface)
    Fix(..)
  , cata
  , ana
  , hylo
  , meta
    -- * Laws (QuickCheck'd in @Properties.Recursion@; pinned against a sample functor)
  , lawHyloFusesCataAna
  , lawCataAnaRoundTrip
  , lawMetaFoldThenUnfold
  ) where

-- | The least fixed point of a functor. An octree cube is @Fix (OctF l)@; a cons-list is
-- @Fix 'ListF'@. Declared here ONCE so no module re-derives it privately.
newtype Fix f = Fix { unFix :: f (Fix f) }

-- | Catamorphism — a structural FOLD (the collapse\/capture direction): tear a @Fix f@ down to a
-- summary @b@ by applying the F-algebra @alg@ bottom-up.
cata :: Functor f => (f b -> b) -> Fix f -> b
cata alg = alg . fmap (cata alg) . unFix

-- | Anamorphism — a structural UNFOLD (the lift\/reconstruct direction): grow a @Fix f@ from a
-- seed @a@ by applying the F-coalgebra @coalg@ top-down.
ana :: Functor f => (a -> f a) -> a -> Fix f
ana coalg = Fix . fmap (ana coalg) . coalg

-- | Hylomorphism — unfold then fold, FUSED (no intermediate @Fix@ is built). Extensionally
-- @hylo alg coalg = cata alg . ana coalg@ ('lawHyloFusesCataAna' proves it), but it never
-- materializes the tree, so it is the right name for a one-pass refine-and-summarize.
hylo :: Functor f => (f b -> b) -> (a -> f a) -> a -> b
hylo alg coalg = alg . fmap (hylo alg coalg) . coalg

-- | Metamorphism (Gibbons) — a 'cata' that FULLY COMPLETES to a summary, then an 'ana' that
-- rebuilds a (possibly different) structure from it. This NAMES the capture→reconstruct PAIR as
-- one object. It is documentation: it asserts nothing about @ana coalg . cata alg@ being the
-- identity. Round-trip exactness is a SEPARATE, TESTED fact about the specific @alg@\/@coalg@.
meta :: (Functor f, Functor g) => (f b -> b) -> (b -> g b) -> Fix f -> Fix g
meta alg coalg = ana coalg . cata alg

-- ---------------------------------------------------------------------------
-- A sample functor to pin the combinators (non-vacuous laws).
-- ---------------------------------------------------------------------------

-- | A cons-list functor: @Fix ListF@ is an ordinary @[Int]@. Used only to witness the schemes.
data ListF a = NilF | ConsF Int a deriving (Eq, Show, Functor)

-- | Coalgebra: unfold a Haskell list into a @Fix ListF@ (one cons per element).
fromListCoalg :: [Int] -> ListF [Int]
fromListCoalg []       = NilF
fromListCoalg (x : xs) = ConsF x xs

-- | Algebra: fold a @Fix ListF@ back to a Haskell list (the inverse shape of 'fromListCoalg').
toListAlg :: ListF [Int] -> [Int]
toListAlg NilF         = []
toListAlg (ConsF x xs) = x : xs

-- | Algebra: the LENGTH of a @Fix ListF@ (the middle summary for the 'meta' law).
lengthAlg :: ListF Int -> Int
lengthAlg NilF         = 0
lengthAlg (ConsF _ n)  = 1 + n

-- | Coalgebra: unfold a count @n@ into the descending list-tree @[n, n-1, …, 1]@.
countDownCoalg :: Int -> ListF Int
countDownCoalg n
  | n <= 0    = NilF
  | otherwise = ConsF n (n - 1)

-- | The FUSION law: the fused 'hylo' equals build-then-fold @cata alg . ana coalg@. Non-vacuous —
-- a 'hylo' that dropped the @fmap@ recursion, or an 'ana' that mis-threaded the seed, would differ.
lawHyloFusesCataAna :: [Int] -> Bool
lawHyloFusesCataAna xs =
  hylo lengthAlg fromListCoalg xs == cata lengthAlg (ana fromListCoalg xs)

-- | 'ana' then 'cata' round-trips a list through @Fix ListF@: @cata toListAlg . ana fromListCoalg = id@.
-- Teeth: a coalgebra that dropped the tail, or an algebra that reordered, fails.
lawCataAnaRoundTrip :: [Int] -> Bool
lawCataAnaRoundTrip xs =
  cata toListAlg (ana fromListCoalg xs) == xs

-- | 'meta' as fold-then-unfold: collapse a length-@n@ list-tree to its length @n@, then unfold the
-- descending @[n, n-1, …, 1]@. Witnesses that the named composite computes (NOT that it is an
-- identity — it is deliberately a DIFFERENT structure out). Capped so the unfold stays finite.
lawMetaFoldThenUnfold :: [Int] -> Bool
lawMetaFoldThenUnfold xs0 =
  let xs   = take 64 xs0
      n    = length xs
      src  = ana fromListCoalg xs                 -- Fix ListF of length n
      out  = meta lengthAlg countDownCoalg src    -- Fix ListF = [n, n-1, …, 1]
  in cata toListAlg out == reverse [1 .. n]
