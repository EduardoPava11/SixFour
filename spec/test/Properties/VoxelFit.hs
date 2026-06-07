module Properties.VoxelFit (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.VoxelFit

-- Rungs in range for the two sliders.
rungs :: [Rung]
rungs = [ (rx, ry) | rx <- [0 .. maxRung], ry <- [0 .. maxRung] ]

tests :: TestTree
tests = testGroup "VoxelFit (the discrete INTEGER projection ladder — crisp at every rung)"
  [ -- the GIF-identity is preserved AS YOU ROTATE: the near face stays the flat square
    -- positions at every rung (corrects the plan's diamond-front S3)
    testProperty "lawFrontSquareAllRungs: near face == GIF positions ∀ rung, ∀ (x,y)" $
      forAll (elements rungs) $ \r ->
        forAll (choose (0, side - 1)) $ \x ->
          forAll (choose (0, side - 1)) $ \y ->
            lawFrontSquareAllRungs r x y

    -- flat collapses depth onto the front → indistinguishable from the 2D GIF
  , testProperty "lawFlatIsGifPositions: rung (0,0) collapses all depth slices to the front" $
      forAll (choose (0, side - 1)) $ \x ->
        forAll (choose (0, side - 1)) $ \y ->
          forAll (choose (0, side - 1)) $ \t ->
            lawFlatIsGifPositions x y t

    -- THE crispness gate: every corner lands on an exact integer art-pixel at every rung
  , testProperty "lawEveryCornerIntegral: integer art-px ∀ rung (the crispness gate)" $
      once (all lawEveryCornerIntegral rungs)

    -- the receding depth edge has a small-integer slope ⇒ AA-free staircase
  , testProperty "lawDepthSlopeSmallInteger: depth slope is a small-integer ratio ∀ rung" $
      once (all lawDepthSlopeSmallInteger rungs)

    -- flat silhouette is exactly artRes/2 ⇒ one voxel = one GIF cell
  , testProperty "lawFlatHalfSpanIsHalfArtRes: flat silhouette == artRes/2" $
      once lawFlatHalfSpanIsHalfArtRes

    -- every rotated rung frames a larger silhouette ⇒ the sides reveal as it comes forward
  , testProperty "lawRevealGrowsSilhouette: rotated rungs exceed flat" $
      once lawRevealGrowsSilhouette

    -- THE DISPROOF: the orbit camera is NOT pixel-exact at the hero — the integer table
    -- is mandatory, not a preference. This must hold (orbit fails) for the swap to be proven.
  , testProperty "lawOrbitHeroNotPixelExact: orbit basis fails integrality at the hero" $
      once lawOrbitHeroNotPixelExact

    -- THE RASTERIZER (cube as cells) ----------------------------------------

    -- the centered box frames every projected voxel — no silhouette corner clips ∀ rung
  , testProperty "lawCubeBoxContainsSilhouette: centered box clips nothing ∀ rung" $
      once (all lawCubeBoxContainsSilhouette rungs)

    -- the near face is fully present + front-most ⇒ the rasterized front == the 2D GIF
  , testProperty "lawRasterizeFrontIsGif: near face == GIF front ∀ rung (crisp identity)" $
      once (all lawRasterizeFrontIsGif rungs)

    -- the flat rung covers exactly the 4096 GIF cells (one voxel = one cell at rest)
  , testProperty "cubeCellCount flat == 4096 (front face only at rest)" $
      once (cubeCellCount (0, 0) == side * side)

    -- a rotated rung reveals MORE cells (the side faces appear)
  , testProperty "cubeCellCount grows when rotated (side faces reveal)" $
      once (cubeCellCount (2, 2) > cubeCellCount (0, 0))
  ]
