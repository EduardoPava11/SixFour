module Properties.HierarchicalDelta (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.HierarchicalDelta
import SixFour.Spec.ConstructionEncoder (QColour)

-- A small octant depth so octantDistill runs at exact 8^d size, fast (d in 0..3).
genDepth :: Gen Int
genDepth = choose (0, 3)

-- A short Q16 OKLab displacement list (the ColourDelta carrier).
genQColours :: Gen [QColour]
genQColours = do
  k <- choose (0, 6)
  vectorOf k ((,,) <$> choose (-2000, 2000) <*> choose (-2000, 2000) <*> choose (-2000, 2000))

-- A short index map (palette slots in [0, 16)) for the IndexDelta carrier.
genIndex :: Gen [Int]
genIndex = do
  k <- choose (0, 8)
  vectorOf k (choose (0, 15))

tests :: TestTree
tests = testGroup "HierarchicalDelta (abstract the H: one hierarchy, two carriers + the data-delta pyramid)"
  [ testGroup "The abstracted H (lossless coarse/fine split, per carrier)"
      [ testProperty "VALUE carrier: coarseBand <> fineBand == whole" $
          forAll genQColours lawColourCoarseFineSplit
      , testProperty "POLICY carrier: coarseBand <> fineBand == whole" $
          forAll genIndex $ \f -> forAll genIndex $ \t -> lawIndexCoarseFineSplit f t
      ]

  , testGroup "VALUE delta — ColourDelta is an abelian ℤ-module (deltas ADD)"
      [ testProperty "monoid identity (no-recolour)" $
          forAll genQColours lawColourDeltaIdentity
      , testProperty "associativity (ragged via zero-pad)" $
          forAll genQColours $ \x -> forAll genQColours $ \y -> forAll genQColours $ \z ->
            lawColourDeltaAssoc x y z
      , testProperty "group inverse: d <> inv d is all-zero (unclamped arithmetic)" $
          forAll genQColours lawColourDeltaInverse
      , testProperty "coarse = global pan, fine = local jitter" $
          once lawColourCoarseIsGlobalPan
      , testProperty "VALUE target reaches t+1 in FUSED buildPixels space" $
          once lawValueDeltaReachesNextPixelsInFusedSpace
      ]

  , testGroup "POLICY delta — IndexDelta is a transport group (deltas COMPOSE)"
      [ testProperty "monoid identity (no-motion empty map)" $
          forAll genIndex $ \f -> forAll genIndex $ \t -> lawIndexDeltaIdentity f t
      , testProperty "monoid action homomorphism (compose then apply == apply in sequence)" $
          forAll genIndex $ \a -> forAll genIndex $ \m -> forAll genIndex $ \t ->
            lawIndexDeltaActionHomomorphism a m t
      , testProperty "group inverse: inv d <> d is no-motion on the data" $
          forAll genIndex $ \f -> forAll genIndex $ \t -> lawIndexDeltaInverse f t
      , testProperty "composition is CHAINING not addition (5↦7 then 7↦2 = 5↦2)" $
          once lawIndexCompositionIsNotAddition
      , testProperty "coarse = rigid region motion, fine = boundary jitter" $
          once lawIndexCoarseIsRigidMotion
      ]

  , testGroup "Spatial data-delta pyramid (reuses the frozen octant ladder, no re-pin)"
      [ testProperty "every band reconstructs the DATA delta; constant orbit strictly misses a moved frame" $
          forAll genDepth $ \d -> forAll genIndex $ \c -> forAll genIndex $ \n ->
            lawHierarchicalDeltaTargetIsDataManufactured d c n
      , testProperty "per-BAND provenance: every band is NextFrameData; one self band ⇒ whole hierarchy inadmissible" $
          forAll genDepth $ \d -> forAll genIndex $ \c -> forAll genIndex $ \n ->
            lawDeltaBandsArePerBandDataProvenance d c n
      ]
  ]
