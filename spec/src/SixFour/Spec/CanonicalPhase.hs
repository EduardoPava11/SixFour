{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : SixFour.Spec.CanonicalPhase
Description : The loop gauge-fix — a deterministic, rotation-invariant canonical phase for the cyclic frame sequence.

Phase 0 of the RGBT‑4D hardening (@docs/SIXFOUR-RGBT4D-BUFFER-HARDENING-WORKFLOW.md@): the
semantic R/G/B/T lanes (2b) need a __privileged phase__, but the GIF loop is @C₆₄@‑symmetric — it
has no first frame. This module fixes that gauge deterministically.

== The subtlety hardening caught

The naïve rule the brief sketched — "rotate so a per‑frame scalar is maximal, ties → lowest
index" — is __NOT rotation‑invariant under ties__. Counterexample (keys @[5,3,5]@, max at indices
0 and 2): lowest index 0 ⇒ phase 0 ⇒ @[5,3,5]@. Rotate the same loop by one (@[3,5,5]@): max at
indices 1,2, lowest 1 ⇒ @[5,5,3]@ — a __different__ canonical form for the __same loop__. The gauge
is not fixed. So argmax+lowest-index fails the one job it has.

== The hardened rule: the necklace canonical form

'canonicalRotation' takes the __lexicographically-greatest rotation__ of the per-frame key
sequence (the classic /canonical form of a necklace/). Because every rotation of one loop shares
the same /set/ of rotations, they share the same greatest one — so the canonical form is
__rotation-invariant by construction__ ('lawCanonicalGaugeFixed', EXACT, ∀). Ties are resolved by
the whole sequence, not a single element; a genuinely periodic loop has several equal greatest
rotations but they are the same sequence, so the form is still unique.

Keys are integers (Q16 per-frame scalars), so the comparison is exact — no float, hence
bit-identical Mac↔device (the @lawPhaseStableUnderQ16@ obligation is met by construction). This is
the reference (an @O(n²)@ scan); the device may use Booth's @O(n)@ least-rotation — same result.
-}
-- COMPARTMENT: ZIG-FLOOR | tag:DeviceTag
module SixFour.Spec.CanonicalPhase
  ( -- * Cyclic rotation
    rotateBy
    -- * The gauge-fix
  , canonicalPhase
  , canonicalRotation
  , phaseIsUnique
  , canonicalize
    -- * Laws (QuickCheck'd in Properties.CanonicalPhase)
  , lawRotateByComposes
  , lawCanonicalRotationIsRotation
  , lawCanonicalPhaseInRange
  , lawCanonicalGaugeFixed
  , lawCanonicalIdempotent
  , lawCanonicalizeGaugeFixed
  ) where

-- | Rotate a list left by @k@ (mod length): index @k@ becomes the new head. Cyclic,
-- so @rotateBy@ is the @C_n@ action on the loop.
rotateBy :: Int -> [a] -> [a]
rotateBy _ [] = []
rotateBy k xs =
  let n  = length xs
      k' = k `mod` n
  in drop k' xs ++ take k' xs

-- | All @n@ rotations of the list (index @i@ = @rotateBy i@).
rotations :: [a] -> [[a]]
rotations xs = [ rotateBy i xs | i <- [0 .. length xs - 1] ]

-- | The canonical phase: the lowest start index whose rotation is the
-- lexicographically-greatest. Lowest-on-ties only matters for periodic loops, where
-- every greatest rotation is the same sequence anyway.
canonicalPhase :: Ord a => [a] -> Int
canonicalPhase [] = 0
canonicalPhase xs =
  let rs   = [ (rotateBy i xs, i) | i <- [0 .. length xs - 1] ]
      best = maximum (map fst rs)
  in minimum [ i | (s, i) <- rs, s == best ]

-- | The necklace canonical form: the lexicographically-greatest rotation. The same
-- for every rotation of the same loop ('lawCanonicalGaugeFixed').
canonicalRotation :: Ord a => [a] -> [a]
canonicalRotation xs = rotateBy (canonicalPhase xs) xs

-- | Whether the greatest rotation is achieved at exactly one index — i.e. the loop is
-- not periodic, so the phase is unambiguous. (When false, the canonical /sequence/ is
-- still unique, but a separate payload rotated by the phase is only well-defined under
-- this predicate — see 'lawCanonicalizeGaugeFixed'.)
phaseIsUnique :: Ord a => [a] -> Bool
phaseIsUnique [] = True
phaseIsUnique xs =
  let rs   = map (`rotateBy` xs) [0 .. length xs - 1]
      best = maximum rs
  in length (filter (== best) rs) == 1

-- | Align a payload to the canonical phase derived from a key sequence (e.g. rotate
-- the 64 frames so the canonical-phase frame leads). The application surface: keys are
-- the per-frame Q16 scalars, payload the frames.
canonicalize :: Ord k => [k] -> [a] -> [a]
canonicalize keys payload = rotateBy (canonicalPhase keys) payload

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.CanonicalPhase)
-- ============================================================================

-- | 'rotateBy' is a group action of @ℤ@ on the loop: @rotateBy i ∘ rotateBy j ≡
-- rotateBy (i+j)@.
lawRotateByComposes :: Eq a => Int -> Int -> [a] -> Bool
lawRotateByComposes i j xs = rotateBy i (rotateBy j xs) == rotateBy (i + j) xs

-- | The canonical form is a genuine rotation of the input — no element invented or
-- dropped (so the loop's content is preserved, only its phase fixed).
lawCanonicalRotationIsRotation :: Ord a => [a] -> Bool
lawCanonicalRotationIsRotation xs = null xs || canonicalRotation xs `elem` rotations xs

-- | The phase is a valid index: @0 ≤ phase < length@.
lawCanonicalPhaseInRange :: Ord a => [a] -> Bool
lawCanonicalPhaseInRange xs =
  null xs || (let p = canonicalPhase xs in p >= 0 && p < length xs)

-- | THE keystone — the gauge is fixed: every rotation of one loop has the SAME
-- canonical form. @canonicalRotation (rotateBy k xs) ≡ canonicalRotation xs@, EXACT
-- for all @k@ and all @xs@ (the @C_n@ symmetry is quotiented out). This is what makes
-- the semantic R/G/B/T assignment reproducible despite the loop having no first frame.
lawCanonicalGaugeFixed :: Ord a => Int -> [a] -> Bool
lawCanonicalGaugeFixed k xs = canonicalRotation (rotateBy k xs) == canonicalRotation xs

-- | The canonical form is a true canonical form: applying it again changes nothing.
lawCanonicalIdempotent :: Ord a => [a] -> Bool
lawCanonicalIdempotent xs = canonicalRotation (canonicalRotation xs) == canonicalRotation xs

-- | Application-level gauge-fix: when the phase is unambiguous ('phaseIsUnique') and
-- keys and payload share length, rotating BOTH by any @k@ canonicalizes to the same
-- aligned payload — so the frame alignment is invariant to which phase the loop was
-- recorded from. (Under a periodic key sequence the phase is only defined up to the
-- period, hence the precondition.)
lawCanonicalizeGaugeFixed :: (Ord k, Eq a) => Int -> [k] -> [a] -> Bool
lawCanonicalizeGaugeFixed k keys payload =
  not (phaseIsUnique keys && length keys == length payload)
    || canonicalize (rotateBy k keys) (rotateBy k payload) == canonicalize keys payload
