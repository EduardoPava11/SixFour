module Properties.RootLatticeDetail (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.RootLatticeDetail

-- A short integer voxel vector (the cube under one octant node).
genVoxels :: Gen [Integer]
genVoxels = do
  b <- choose (1, 12)
  vectorOf b (choose (-4000, 4000))

-- A root-coordinate chart of length b-1 (b in [1,12]).
genCoords :: Gen [Integer]
genCoords = do
  m <- choose (0, 11)            -- b-1
  vectorOf m (choose (-4000, 4000))

tests :: TestTree
tests = testGroup "RootLatticeDetail (1 coarse + (b-1) detail = the root lattice A_{b-1})"
  [ testGroup "Band count is an algebraic identity (rank A_{b-1} = b-1), for ANY branching b"
      [ testProperty "numDetailBands b == |simpleRoots b| == b-1" lawBandCountEqualsRank
      , testProperty "the shipped b=8 octant: 7 detail bands == rank A_7, all mean-free" $
          once lawOctantIsA7
      ]

  , testGroup "Detail lives in A_{b-1} = ker(sum) (mean-free / vanishing zeroth moment)"
      [ testProperty "every simple root e_i - e_{i+1} is mean-free" lawSimpleRootsAreMeanFree
      , testProperty "teeth: a standard basis vector e_0 is NOT in A (sum 1)" $
          once lawNonRootNotInA
      , testProperty "the mean-free reconstruction lies in A (sum 0)" $
          forAll genVoxels lawDetailIsMeanFree
      ]

  , testGroup "A_{b-1} is the FREE ℤ-module on the simple roots (root-coordinate chart)"
      [ testProperty "rootCoords . fromRootCoords == id (faithful chart)" $
          forAll genCoords lawRootCoordsRoundTrip
      ]

  , testGroup "Detail kernel is exactly the constants ℤ·1 (the rank-1 DC line)"
      [ testProperty "adding a constant doesn't change the detail; a non-constant bump does" $
          forAll genVoxels $ \xs -> forAll (choose (-4000, 4000)) $ \k ->
            lawDetailKernelIsConstants xs k
      ]

  , testGroup "MeanFree: the Σ=0 detail invariant carried in the TYPE (Win C)"
      [ testProperty "both constructors yield Σ=0; a sum-1 vector is REFUSED (no mean-subtraction)" $
          forAll genCoords lawMeanFreeIsSigmaZero
      ]
  ]
