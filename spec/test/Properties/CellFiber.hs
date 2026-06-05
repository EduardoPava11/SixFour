module Properties.CellFiber (tests) where

import           Test.Tasty
import           Test.Tasty.QuickCheck
import qualified Data.Set as Set

import SixFour.Spec.CellFiber
import SixFour.Spec.ColorFixed (q16One)

-- | An in-gamut Q16 colour generator (mirrors 'inGamut': L∈[0,q16One], a,b∈[±½]).
genInGamut :: Gen Color
genInGamut = do
  l <- choose (0, q16One)
  a <- choose (negate (q16One `div` 2), q16One `div` 2)
  b <- choose (negate (q16One `div` 2), q16One `div` 2)
  pure (Color (l, a, b))

-- | A cell built only from in-gamut claims (so render's preconditions hold).
genCell :: Gen Cell
genCell = do
  n  <- choose (0, 6 :: Int)
  cs <- vectorOf n genInGamut
  pure (Set.fromList cs)

-- | A CONTESTED cell: guaranteed ≥2 distinct claims (two+ widgets collided).
genContestedCell :: Gen Cell
genContestedCell = do
  n  <- choose (2, 6 :: Int)
  cs <- vectorOf n genInGamut
  let s = Set.fromList cs
  if Set.size s >= 2 then pure s
  else genContestedCell   -- retry on the rare all-equal draw

-- | A real OKLab triple that is sometimes in-domain, sometimes NaN/Inf/out.
genIngestInput :: Gen (Double, Double, Double)
genIngestInput = oneof
  [ (,,) <$> choose (0, 1) <*> choose (-0.5, 0.5) <*> choose (-0.5, 0.5)  -- in-domain
  , (,,) <$> choose (-2, 3) <*> choose (-2, 2) <*> choose (-2, 2)          -- maybe out
  , (,,) <$> elements bads <*> choose (-0.5, 0.5) <*> choose (-0.5, 0.5)   -- bad L
  , (,,) <$> choose (0, 1) <*> elements bads <*> choose (-0.5, 0.5)        -- bad a
  ]
  where bads = [0/0, 1/0, -1/0]  -- NaN, +Inf, -Inf

tests :: TestTree
tests = testGroup "CellFiber (the WHAT axis — per-Place colour fiber join-semilattice)"
  [ -- L1..L4: bounded join-semilattice
    testProperty "L1 join associativity (x⊕y)⊕z == x⊕(y⊕z)" $
      forAll genCell $ \x -> forAll genCell $ \y -> forAll genCell $ \z ->
        lawJoinAssoc x y z

  , testProperty "L2 join commutativity x⊕y == y⊕x" $
      forAll genCell $ \x -> forAll genCell $ \y -> lawJoinComm x y

  , testProperty "L3 join idempotence x⊕x == x (semiLATTICE not monoid)" $
      forAll genCell lawJoinIdem

  , testProperty "L4 bottom identity ⊥⊕x == x == x⊕⊥" $
      forAll genCell lawBottomIdentity

  -- L5: render totality + the trivial cases
  , testProperty "L5 render totality: every cell renders in-gamut" $
      forAll genCell lawRenderTotal

  , testProperty "render singleton = the claim itself" $
      forAll genInGamut lawRenderSingleton

  , testProperty "render ⊥ = neutralColor (mid-grey L=½,a=b=0)" $
      once lawRenderBottomNeutral

  -- NO BLEND: render never synthesises a colour
  , testProperty "NO-BLEND render output ∈ {neutral, sentinel, an actual claim}" $
      forAll genCell lawNoSynthesis

  , testProperty "contested (≥2 claims) ⇒ the loud sentinel, never a mixture" $
      forAll genContestedCell lawRenderContested

  , testProperty "contested detection is exact (|cell|>1)" $
      forAll genCell lawContestedDetect

  -- the opt-in shimmer effect only ever shows a REAL claimant (still no blend)
  , testProperty "shimmerAt t picks an actual claimant for any tick" $
      forAll arbitrary $ \t -> forAll genCell (lawShimmerIsClaimant t)

  -- HOLE #4/#5/#6 (NaN + domain guard at the I/O edge)
  , testProperty "L6/HOLE#4 ingest rejects exactly NaN/Inf/out-of-domain reals" $
      forAll genIngestInput lawIngestGuardsDomain

  , testProperty "HOLE#4 ingest of any NaN channel is Nothing" $
      forAll (choose (-0.5, 0.5)) $ \a -> forAll (choose (-0.5, 0.5)) $ \b ->
        ingest (0/0, a, b) == Nothing

  , testProperty "HOLE#5 round-half-away: ingest(0,0,0)=L½ box-center is in-gamut" $
      once (case ingest (0, 0, 0) of Just c -> inGamut c; Nothing -> False)

  -- HOLE #2 (order determinism): render is a function of the SET, arrival-free
  , testProperty "HOLE#2 render depends only on the set (claim order irrelevant, n≥3)" $
      forAll (vectorOf 4 genInGamut) $ \cs ->
        render (Set.fromList cs) == render (Set.fromList (reverse cs))

  -- HOLE #1 (carrier bounded by K, source-free)
  , testProperty "HOLE#1 rendered carrier bounded by the K-leaf gamut (source-free)" $
      forAll genCell lawCarrierBoundedByK
  ]
