{- |
Module      : SixFour.Spec.CoverageMonotone
Description : The PROVABLE part of the generalization-coverage story, separated honestly from the empirical numeric threshold. "SixFour.Spec.Generalization" decomposes held error into COVERAGE (which inputs were seen) plus the irreducible masked residual, but it names coverage only as a DATA CONDITION — it proves nothing about HOW coverage improves with data. This module proves the one thing about coverage that IS a theorem: coverage is a MONOTONE (antitone in error) set function over @Generalization.generator@/@Generalization.targetMap@. If the seen training inputs of run A are a SUBSET of run B's, then B's held-error set is a SUBSET of A's: more data weakly REDUCES, never increases, held error.

The honest boundary (no overclaim). This is PLAIN set-monotonicity, not a numeric guarantee. It does NOT
claim any multi-day coverage threshold, any rate, or any "covers everything after N captures" — those stay
DEMONSTRATED/empirical. What is converted from a stated PROPERTY into a proven LEMMA is exactly: the held
error set is an antitone function of the seen set. The empirical question "how big does the seen set get,
how fast?" is untouched and stays empirical by design.

The model (a real consumer of the generalization model, not a relabel). A learner is a function
@[Input] -> Input -> [Int]@ from its seen set to a learned map. The FAITHFUL learner reproduces the actual
'SixFour.Spec.Generalization.targetMap' EXACTLY on its seen support and is wrong (returns @[]@, which can
never equal the always-non-empty target) off it — this is the very @learned@ of
@Generalization.lawHeldErrorIsCoverageNotShift@. Its held-error set over a held universe @U@ is therefore
@{ x ∈ U | x ∉ seen }@, which is manifestly antitone in @seen@. The laws consume the actual @generator@ and
@targetMap@, so this is a real lemma about the generalization object.

The teeth (a false witness must fail):
  * 'lawForgetfulLearnerBreaksMonotone' — a NON-monotone learner that FORGETS on more data (errs on a
    previously-correct seen input once the seen set grows) FAILS the subset conclusion, while the faithful
    learner passes on the same witness. So 'lawCoverageMonotone' is not vacuously true of any learner.
  * 'lawDisjointInputAlwaysInError' — a held input DISJOINT from the union of every training run's seen set
    (a constant-detail tuple the strictly-+1 'generator' can never emit) stays in the error set for EVERY
    run. Coverage cannot be conjured: this guards against a vacuous "covers everything"/empty-error body.
  * 'lawOnSupportZeroHeldError' — on-support exactness inherited from "SixFour.Spec.Generalization": held
    error is 0 (the input is NOT in the error set) on a seen input, for inputs drawn from the real @generator@.

Pure-spec, GHC-boot-only; laws QuickCheck'd / @once@-tested in "Properties.CoverageMonotone". Emits no golden.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.CoverageMonotone
  ( -- * The learner model (seen set ↦ learned map) and its held-error set
    Learner
  , mkInput
  , faithful
  , forgetful
  , errSet
  , bogusInput
    -- * The provable lemma: coverage is a monotone (antitone-in-error) set function
  , lawCoverageMonotone
    -- * Teeth
  , lawForgetfulLearnerBreaksMonotone
  , lawDisjointInputAlwaysInError
  , lawOnSupportZeroHeldError
    -- * Capstone
  , lawCoverageIsMonotoneSetFunction
  ) where

import Data.List (nub)

import SixFour.Spec.Generalization (Input, generator, targetMap)

-- ---------------------------------------------------------------------------
-- The learner model
-- ---------------------------------------------------------------------------

-- | A learner: a map from its SEEN training-input set to a learned @Input -> target@ function. The seen set
-- is the ONLY thing distinguishing two training runs in this coverage model.
type Learner = [Input] -> Input -> [Int]

-- | Deterministically build a valid 'Input' from an @Int@ (coarse @mod 256@, 7 detail bands @mod 64@). Used
-- to generate subset-related seen sets and held universes for the monotonicity law.
mkInput :: Int -> Input
mkInput n = (abs n `mod` 256, [ abs (n + j) `mod` 64 | j <- [0 .. 6] ])

-- | The FAITHFUL learner: reproduces 'SixFour.Spec.Generalization.targetMap' EXACTLY on its seen support and
-- returns @[]@ off it. Since @targetMap@ is always non-empty (its head is the coarse value), @[]@ can never
-- equal a real target, so off-support is always an error. This is the @learned@ of
-- @Generalization.lawHeldErrorIsCoverageNotShift@, lifted to range over an arbitrary seen set.
faithful :: Learner
faithful seen x = if x `elem` seen then targetMap x else []

-- | The FORGETFUL learner (the teeth foil): reproduces the target only while the seen set is small
-- (@length ≤ k@); once it has seen MORE than @k@ inputs it forgets and errs on everything. This is exactly a
-- learner whose error set is NOT antitone in the seen set, so it breaks 'lawCoverageMonotone'.
forgetful :: Int -> Learner
forgetful k seen x = if x `elem` seen && length seen <= k then targetMap x else []

-- | The held-error set of a learner over a held universe: the held inputs it does NOT reproduce correctly.
-- For the 'faithful' learner this equals @{ x ∈ U | x ∉ seen }@.
errSet :: Learner -> [Input] -> [Input] -> [Input]
errSet learn seen u = [ x | x <- u, learn seen x /= targetMap x ]

-- | A held input DISJOINT from the union of every 'SixFour.Spec.Generalization.generator' run: a
-- constant-detail tuple. The generator's detail bands are @(s*13 + i*7 + j) mod 64@ over @j ∈ [0..6]@, so
-- consecutive bands always differ by @1 (mod 64)@; a constant-detail tuple can therefore never be emitted.
bogusInput :: Input
bogusInput = (200, replicate 7 5)

-- ---------------------------------------------------------------------------
-- Laws (QuickCheck'd / once-tested in Properties.CoverageMonotone)
-- ---------------------------------------------------------------------------

-- | THE LEMMA: coverage is a monotone set function — held error is ANTITONE in the seen set. We build
-- @seenB@ as a superset of @seenA@ (append more seen inputs), then prove the faithful learner's held-error
-- set over @U@ SHRINKS (or stays equal): @errSet faithful seenB U ⊆ errSet faithful seenA U@. More data
-- weakly reduces, never increases, held error. (No numeric threshold is claimed — only the set inclusion.)
lawCoverageMonotone :: [Int] -> [Int] -> [Int] -> Bool
lawCoverageMonotone as bs us =
  let seenA = map mkInput as
      seenB = seenA ++ map mkInput bs        -- seenA ⊆ seenB as sets (by construction)
      u     = map mkInput us
      errA  = errSet faithful seenA u
      errB  = errSet faithful seenB u
  in all (`elem` errA) errB                  -- errB ⊆ errA : the monotone-improvement conclusion

-- | TEETH (a): a non-monotone learner FAILS the lemma. With @seenA ⊆ seenB@ and @|seenB| > k@, the
-- 'forgetful' learner errs on an input it got right under @seenA@ — so its error set GROWS with data and the
-- subset conclusion @errB ⊆ errA@ is FALSE — while the 'faithful' learner keeps that same input correct.
-- This proves 'lawCoverageMonotone' has real content (it is not true of every learner).
lawForgetfulLearnerBreaksMonotone :: Bool
lawForgetfulLearnerBreaksMonotone =
  let x     = mkInput 1
      seenA = [x]
      seenB = [x, mkInput 2, mkInput 3]      -- length 3 > k=1: forgetful forgets here
      u     = [x]
      errA  = errSet (forgetful 1) seenA u
      errB  = errSet (forgetful 1) seenB u
  in x `notElem` errSet faithful seenB u     -- faithful: x stays correct with MORE data (monotone)
     && x `elem` errB                        -- forgetful: x becomes WRONG with more data (non-monotone)
     && not (all (`elem` errA) errB)         -- so errB ⊆ errA FAILS for the forgetful learner

-- | TEETH (b): coverage cannot be conjured. A held input disjoint from the union of ALL training runs (the
-- constant-detail 'bogusInput', which 'SixFour.Spec.Generalization.generator' can never emit) stays in the
-- error set for EVERY run. This guards against a vacuous "covers everything" / always-empty error body: if
-- @errSet@ ever returned @[]@, this would fail.
lawDisjointInputAlwaysInError :: Bool
lawDisjointInputAlwaysInError =
  all (\s -> bogusInput `notElem` generator s
             && bogusInput `elem` errSet faithful (generator s) [bogusInput])
      [0 .. 50]

-- | TEETH (c): on-support exactness, inherited from "SixFour.Spec.Generalization". On inputs drawn from the
-- real @generator@, the faithful learner reproduces the target EXACTLY, so a seen input is NEVER in the
-- error set — held error is 0 on the seen support. (This is the @Generalization@ on-support-exact fact,
-- consumed here over the actual generator.)
lawOnSupportZeroHeldError :: Int -> Bool
lawOnSupportZeroHeldError seed =
  let seen = generator seed
  in all (\x -> faithful seen x == targetMap x
                && x `notElem` errSet faithful seen seen)
         (nub seen)

-- | CAPSTONE: coverage is a monotone set function over the generalization generator/target — the provable
-- core (antitone-in-error) with all three teeth attached. Drop any conjunct and the statement weakens to
-- something a forgetful learner or an empty-error body could satisfy. The empirical numeric threshold is
-- DELIBERATELY ABSENT: this proves monotone improvement, not how much coverage a given capture budget buys.
lawCoverageIsMonotoneSetFunction :: [Int] -> [Int] -> [Int] -> Int -> Bool
lawCoverageIsMonotoneSetFunction as bs us seed =
     lawCoverageMonotone as bs us
  && lawForgetfulLearnerBreaksMonotone
  && lawDisjointInputAlwaysInError
  && lawOnSupportZeroHeldError seed
