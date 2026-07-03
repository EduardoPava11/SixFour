{- |
Module      : SixFour.Spec.CombinatorExactSequence
Description : S, K, I are the three canonical maps of the SHORT EXACT SEQUENCE of the octant refinement, @0 -> detail -> fine -> coarse -> 0@. K is the surjection (weakening, forget the detail), I is the splitting (the reversible lift, an exact isomorphism), S is a SECTION (invent a detail representative). The gene lives on S because a section is the only one of the three not canonically determined by the sequence.

The octant edge decomposes a fine @V8@ cell into @1 coarse + 7 detail@ ('OctBand'),
which over Z[1\/2]-modules is a short exact sequence

@
  0  ->  Lambda_detail  ->  Lambda_fine  ->  Lambda_coarse  ->  0
@

and the three combinators of the S\/K\/I calculus ARE its three canonical maps:

  * @I = \\x. x@ is the SPLITTING. 'liftOct' is a Z[1\/2]-module isomorphism
    @Lambda_fine ~= Lambda_coarse (+) Lambda_detail@ with exact inverse 'unliftOct'
    ('lawISplitsExactly', delegating 'OctreeCell.lawOctReversible'). Unimodular:
    it preserves lattice covolume and, as a bijection, entropy, so @work(I)=0@.

  * @K = \\x y. x@ is the SURJECTION @Lambda_fine ->> Lambda_coarse@, the quotient by
    the detail sublattice. 'scalarCollapseLossy' keeps the coarse and FORGETS the
    seven detail bands, so its kernel is exactly @Lambda_detail@
    ('lawKForgetsDetail': changing the detail never changes K). It is reduction
    modulo the detail sublattice.

  * @S = \\f g x. f x (g x)@ is a SECTION @Lambda_coarse -> Lambda_fine@, a right
    inverse of K ('lawSIsSectionOfK': @K . S = id@ on the coarse). It LIFTS a coset
    (a coarse value) to a fine representative by choosing the detail. Here the
    zero-detail section is the deterministic floor; a learned theta (the gene) is a
    DIFFERENT choice of representative in the same coset. This is why the gene lives
    only on S: I and K are canonical, a section is a CHOICE.

The defining asymmetry falls straight out: @K . S = id@ on the coarse (a section
always splits its surjection), but @S . K /= id@ on the fine, because pool-then-
reinvent cannot recover the discarded detail ('lawResidualWitnessesNonSplit'). The
gap @v@ vs @S(K v)@ is the residual the scale-transition training minimizes and the
destructive analysis erases. Only I, carrying the FULL detail, reconstructs exactly
('lawOnlyFullDetailReconstructs'). I is the true inverse; S is a learned pseudo-
inverse of K; the residual is the difference between them.

== Discrete geometry + algebraic number theory

  * The ambient ring is Z[1\/2] (the octant averages by 2, so 2 must be a unit);
    the maps are Z[1\/2]-module homomorphisms, hence module theory not linear
    algebra.
  * The latent point is @P6 = (L,a,b,x,y,t)@ (colour paired with position by @phi6@:
    @a\<->x, b\<->y, L\<->t@); a detail band is a COUPLED value-and-position
    refinement, so S invents colour-detail and its location jointly.
  * The three arrows are the homological content of the SES: inclusion of the kernel,
    surjection to the quotient, and the splitting that reconciles them. That there
    are exactly three is why S, K, I (and no fourth combinator) are the right basis.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.CombinatorExactSequence
  ( -- * The three canonical maps (S/K/I) of the octant SES
    kSurj
  , iSplit
  , sSection
  , zeroDetail
    -- * Laws pinning S/K/I to the exact sequence
  , lawISplitsExactly
  , lawKForgetsDetail
  , lawSIsSectionOfK
  , lawResidualWitnessesNonSplit
  , lawOnlyFullDetailReconstructs
  ) where

import SixFour.Spec.OctreeCell
  ( V8(..), OctBand(..), Detail, liftOct, unliftOct, scalarCollapseLossy )

-- | The trivial (floor) detail: the zero coset representative.
zeroDetail :: Detail
zeroDetail = (0,0,0,0,0,0,0)

-- | K: the SURJECTION to the coarse (forgets the seven detail bands).
kSurj :: V8 Int -> Int
kSurj = scalarCollapseLossy

-- | I: the SPLITTING, the reversible iso @V8 ~= (coarse, detail)@ ('unliftOct' inverts it).
iSplit :: V8 Int -> OctBand
iSplit = liftOct

-- | S: a SECTION, lifting a coarse value to a fine cell by choosing the (here zero) detail.
-- A learned theta would choose a different representative in the same coset.
sSection :: Int -> V8 Int
sSection c = unliftOct (OctBand c zeroDetail)

-- | I is the splitting: reconstructing from @(coarse, detail)@ is exact (delegates
-- 'OctreeCell.lawOctReversible').
lawISplitsExactly :: V8 Int -> Bool
lawISplitsExactly v = unliftOct (iSplit v) == v

-- | K forgets exactly the detail: changing the seven bands never changes K, so the
-- kernel of the surjection is the detail sublattice. Quantified over two details.
lawKForgetsDetail :: Int -> Detail -> Detail -> Bool
lawKForgetsDetail c d d' =
  kSurj (unliftOct (OctBand c d)) == kSurj (unliftOct (OctBand c d'))

-- | S is a section of K: @K . S = id@ on the coarse (a right inverse of the surjection).
lawSIsSectionOfK :: Int -> Bool
lawSIsSectionOfK c = kSurj (sSection c) == c

-- | S is NOT the splitting: @S . K /= id@ on the fine whenever the detail is nonzero.
-- The residual @v@ vs @S(K v)@ witnesses that the sequence does not split through S.
lawResidualWitnessesNonSplit :: V8 Int -> Bool
lawResidualWitnessesNonSplit v =
  (ocDetail (iSplit v) /= zeroDetail) == (v /= sSection (kSurj v))

-- | Only I (the full detail) reconstructs exactly: reassembling from the REAL coarse
-- and the REAL detail recovers @v@, where the zero-detail section does not.
lawOnlyFullDetailReconstructs :: V8 Int -> Bool
lawOnlyFullDetailReconstructs v =
  let b = iSplit v
  in  unliftOct (OctBand (ocCoarse b) (ocDetail b)) == v
