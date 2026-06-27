{-# LANGUAGE DeriveFunctor #-}

{- |
Module      : SixFour.Spec.Recursion
Description : The boot-only recursion-scheme home — @Fix@/@cata@/@ana@/@hylo@ — so the fixpoint vocabulary is declared ONCE and the multiresolution lift can be NAMED (a capture catamorphism, a reconstruct anamorphism, the round-trip a hylomorphism) instead of re-deriving @Fix@ privately in every module.

This module is the one shared fixpoint foundation. It contains ONLY the schemes that have a REAL
consumer in the spec — the structural fold 'cata' and unfold 'ana' (the octree collapse/lift in
"SixFour.Spec.OctreeCell") and their fused composite 'hylo' (the build→flatten codec,
"SixFour.Spec.OctreeCell" @lawOctantBuildFlattenIsHylo@).

WHAT THIS MODULE DELIBERATELY DOES NOT EXPORT (the anti-jargon boundary):

  * @meta@\/@apo@\/@para@\/@histo@\/@futu@ — each has at most one (proposed) call site
    (jargon-by-absence). @meta@ (Gibbons' metamorphism = fold-then-unfold) would NAME the
    capture→reconstruct pair, but the real codec ("SixFour.Spec.OctreeCell"
    @octantDistill@\/@octantSynthesize@) folds-then-unfolds over LISTS, not a literal @Fix f → Fix g@,
    so the name has no typed consumer; admit it only when one appears. @histo@ is also the wrong
    direction for "read at depth n" (it carries FINER children; the coarser ancestors a depth-read
    needs come from "SixFour.Spec.ScaleFiltration" @valuation@).

  * No scheme here is a free theorem about reversibility: @ana coalg . cata alg@ is not @id@ for
    arbitrary @alg@\/@coalg@. The reversibility of the shipped lift stays a TESTED bijection law
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
    -- * Laws (QuickCheck'd in @Properties.Recursion@; pinned against a sample functor)
  , lawHyloFusesCataAna
  , lawCataAnaRoundTrip
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

-- | Algebra: the LENGTH of a @Fix ListF@ (the summary used by the 'hylo' fusion law).
lengthAlg :: ListF Int -> Int
lengthAlg NilF         = 0
lengthAlg (ConsF _ n)  = 1 + n

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
