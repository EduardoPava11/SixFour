module Properties.MovableLayout (tests) where

import qualified Data.Map.Strict as Map

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.MovableLayout

-- | A random color identity (for the universally-quantified move laws).
genIdentity :: Gen ColorIdentity
genIdentity = elements allIdentities

-- | A random VALID placement: start from the default (always disjoint + in-bounds) and
-- fold a handful of arbitrary moves through 'move' itself. Because 'move' only ever
-- ACCEPTS disjoint+in-bounds candidates (else snaps back), every placement this
-- generator produces is a reachable, invariant-respecting state — exactly the domain
-- the keystone laws quantify over.
genPlacement :: Gen Placement
genPlacement = do
  n     <- choose (0, 6 :: Int)
  steps <- vectorOf n ((,) <$> genIdentity <*> genDelta)
  pure (foldl (\p (i, d) -> move p i d) defaultPlacement steps)

-- | A random cell delta, deliberately wide enough to drive both clamps and collisions.
genDelta :: Gen (Int, Int)
genDelta = (,) <$> choose (-120, 120) <*> choose (-260, 260)

tests :: TestTree
tests = testGroup "MovableLayout (movable color widgets — the proven move/snap/disjoint operator)"
  [ -- 1. classification: movability = being a ColorWidget; chrome immovable by construction
    testProperty "lawClassExhaustive: every identity has an in-bounds, touch-floor-legal default; defaults disjoint" $
      once lawClassExhaustive

    -- 6. the shipped 3-widget seed re-passes every GridLayout law (DiversityRing dock proven)
  , testProperty "lawDefaultsDisjoint: defaultPlacement re-passes ALL GridLayout laws" $
      once lawDefaultsDisjoint

    -- 2. KEYSTONE — disjoint-preservation, QuickChecked over arbitrary placements + deltas
  , testProperty "lawMovePreservesDisjoint: disjoint ⇒ disjoint after move (∀ p i d)" $
      forAll genPlacement $ \p ->
      forAll genIdentity $ \i ->
      forAll genDelta    $ \d ->
        lawMovePreservesDisjoint p i d

    -- 3. bounds clamp — QuickChecked over arbitrary placements + deltas
  , testProperty "lawMoveInBounds: in-bounds ⇒ in-bounds after move (clamp-first)" $
      forAll genPlacement $ \p ->
      forAll genIdentity $ \i ->
      forAll genDelta    $ \d ->
        lawMoveInBounds p i d

    -- 8. a move never perturbs the other two widgets
  , testProperty "lawMoveOnlyTouchesTarget: move agrees with p on every identity ≠ i" $
      forAll genPlacement $ \p ->
      forAll genIdentity $ \i ->
      forAll genDelta    $ \d ->
        lawMoveOnlyTouchesTarget p i d

    -- 4. snap + clamp idempotence (real theorem — snapToAtom is integer-floor, not id)
  , testProperty "lawSnapIdempotent: snapToAtom and clampInBounds are idempotent" $
      forAll genIdentity $ \i ->
      \atom px c r -> lawSnapIdempotent atom px i c r

    -- 5. crisp: every move result lands on a whole atom (no sub-atom drift)
  , testProperty "lawMoveAtomAligned: move result col/row is an exact integer atom" $
      forAll genPlacement $ \p ->
      forAll genIdentity $ \i ->
      forAll genDelta    $ \d ->
        lawMoveAtomAligned p i d

    -- 7. reject is the literal identity — exact snap-back (witness: Palette16 onto Field64)
  , testProperty "lawRejectIsIdentity: a contested clamped move returns the prior Placement verbatim" $
      forAll genPlacement $ \p ->
      forAll genIdentity $ \i ->
      forAll genDelta    $ \d ->
        lawRejectIsIdentity p i d

    -- explicit reject WITNESS: drive Palette16 (16²) exactly onto Field64's top-left.
    -- From the default, Palette16@(42,145) + (-24,-123) = (18,22) == Field64 dock ⇒ reject.
  , testProperty "reject WITNESS: Palette16 +(-24,-123) onto Field64 snaps back to default" $
      once (move defaultPlacement Palette16 (-24, -123) == defaultPlacement)

    -- GOLDEN cross-language pin: fold move over the fixed script, compare to goldenAfter.
    -- (goldenAfter is also emitted as a Swift literal and re-folded in assertSpecParity.)
  , testProperty "goldenMoveTrace: fold move over goldenScript == goldenAfter" $
      once (foldl (\p (i, d) -> move p i d) defaultPlacement goldenScript == goldenAfter)

    -- the golden END state is itself a valid (disjoint + in-bounds) placement: it is
    -- reachable from the (disjoint, in-bounds) default by accepted moves, so the
    -- keystone + bounds laws certify it — and it still names all three identities.
  , testProperty "goldenAfter is a valid 3-widget placement (keystone-certified)" $
      once ( lawMovePreservesDisjoint defaultPlacement Field64 (0, 0)
        .&&. lawMoveInBounds          defaultPlacement Field64 (0, 0)
        .&&. (Map.size goldenAfter == 3) )
  ]
