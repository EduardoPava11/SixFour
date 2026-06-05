module Properties.CellGrid (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.CellGrid
import SixFour.Spec.CellFiber (Color(..))
import SixFour.Spec.ColorFixed (q16One)

-- | An in-gamut Q16 colour (mirrors CellFiber.inGamut).
genColor :: Gen Color
genColor = do
  l <- choose (0, q16One)
  a <- choose (negate (q16One `div` 2), q16One `div` 2)
  b <- choose (negate (q16One `div` 2), q16One `div` 2)
  pure (Color (l, a, b))

-- | A place inside the 64×64 field.
genPlace :: Gen Place
genPlace = Place <$> choose (0, placesH - 1) <*> choose (0, placesW - 1)

-- | A grid built from a handful of section claims joined together (the only
-- public way to build a Grid — keeps the carrier abstract).
genGrid :: Gen Grid
genGrid = do
  n      <- choose (0, 6 :: Int)
  claimsL <- vectorOf n ((,) <$> genPlace <*> genColor)
  pure (gridJoinAll [ section p c | (p, c) <- claimsL ])

-- | A small list of sample places to check pointwise laws over.
genPlaces :: Gen [Place]
genPlaces = do
  n <- choose (1, 8 :: Int)
  vectorOf n genPlace

-- | A list of (Place, Color) claims (places may repeat — that is what creates
-- contention; 'lawDisjointNoContest' de-dups internally to prove the disjoint case).
genClaimList :: Gen [(Place, Color)]
genClaimList = do
  n <- choose (0, 8 :: Int)
  vectorOf n ((,) <$> genPlace <*> genColor)

-- | A grid GUARANTEED to contain a collision: two distinct colours at one Place.
genContestedGrid :: Gen Grid
genContestedGrid = do
  p  <- genPlace
  c0 <- genColor
  c1 <- genColor `suchThat` (/= c0)
  rest <- genGrid
  pure (gridJoinAll [section p c0, section p c1, rest])

tests :: TestTree
tests = testGroup "CellGrid (the WHERE axis — spatial base + pointwise-lifted join, T9)"
  [ -- L7: pointwise join semilattice (reuse fiber laws pointwise)
    testProperty "L7 grid join associativity (pointwise reuse of L1)" $
      forAllBlind genGrid $ \x -> forAllBlind genGrid $ \y -> forAllBlind genGrid $ \z ->
        forAll genPlaces (lawGridJoinAssoc x y z)

  , testProperty "L7b grid join commutativity (pointwise reuse of L2)" $
      forAllBlind genGrid $ \x -> forAllBlind genGrid $ \y ->
        forAll genPlaces (lawGridJoinComm x y)

  , testProperty "L7c grid join idempotence (pointwise reuse of L3)" $
      forAllBlind genGrid $ \x -> forAll genPlaces (lawGridJoinIdem x)

  , testProperty "L8 empty-grid identity (⊥ is the Map default, reuse of L4)" $
      forAllBlind genGrid $ \x -> forAll genPlaces (lawEmptyGridIdentity x)

  -- L9 / T9: inherited totality over the finite 4096-place base
  , testProperty "L9/T9 inherited totality: renderGrid total over all 4096 places" $
      forAllBlind genGrid lawInheritedTotality

  , testProperty "T9 sibling: renderGrid total over the whole field (in-gamut everywhere)" $
      forAllBlind genGrid lawRenderGridTotal

  -- section embedding (the claim unit)
  , testProperty "section embeds exactly one claim; ⊥ elsewhere" $
      forAll genPlace $ \p -> forAll genColor $ \c -> forAll genPlace $ \q ->
        lawSectionEmbeds p c q

  -- HOLE #1: provenance is the fixed 3-enum on the BASE, never on the value
  , testProperty "HOLE#1 Source is the fixed 3-enum {Zig,Swift,Cursor}" $
      once lawBindingFixedEnum

  , testProperty "HOLE#1 claimWith threads Source into Binding, not the Cell" $
      forAll genPlace $ \p -> forAll genColor $ \c ->
        let (g, bnd) = claimWith (const Zig) Swift p c
        in bnd p == Swift                           -- provenance recorded on base
           && gridAt g p == gridAt (section p c) p  -- value carries no source

  -- WIDGET OWNERSHIP: disjoint ownership ⇒ overlap never happens (no blend, no sentinel)
  , testProperty "disjoint widget ownership ⇒ zero contested cells" $
      forAll genClaimList lawDisjointNoContest

  -- "if it happens I want to know": every collision is the visible loud sentinel
  , testProperty "every contested Place visibly shows the loud sentinel" $
      forAllBlind genContestedGrid lawContestedShows

  , testProperty "a contested grid actually reports contested Places (non-empty)" $
      forAllBlind genContestedGrid $ \g -> not (null (contestedPlaces g))

  -- NO SILENT MERGE: renderGridAt (any tick, any zone) never invents a colour
  , testProperty "renderGridAt ∈ {neutral, sentinel, real claim} — never a blend" $
      forAll arbitrary $ \t -> forAll arbitrary $ \z ->
        forAllBlind genGrid $ \g -> forAll genPlace (lawNoSilentMerge t (const z) g)
  ]
