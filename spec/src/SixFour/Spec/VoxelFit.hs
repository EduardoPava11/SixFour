{- |
Module      : SixFour.Spec.VoxelFit
Description : The DISCRETE INTEGER projection ladder for the 64³ review cube — the
              spec source of truth that the X/Y rung sliders read, replacing the
              continuous-orbit raymarcher's irrational basis.

The Review hero is the 64³ (x,y,t) space-time volume. The user rotates it flat→
isometric with two sliders that SNAP to discrete rungs. The defining requirement is
8-bit crispness: at /every/ stop, one voxel must land on an exact integer art-pixel
boundary — otherwise the staircase edges anti-alias and "the grid is the UI" breaks.

== Why the orbit camera cannot do this (the load-bearing finding)

The as-built cube (@VoxelCubeView.VoxelIso.orbit@ + @fitHalfSpan@) uses an /orthonormal/
basis (yaw about world-Y, pitch about camera-right) and a silhouette-autofit half-span.
That is pixel-exact ONLY at the flat rest pose. At any rotated stop the basis components
are irrational (involving @cos@, @sin@, @√2/2@) and the autofit makes art-px-per-voxel
irrational too — e.g. the 45°/30° "hero" lands ~1.76 art-px/voxel on x, ~0.88 on t. The
research rule (pixel-art "isometric" is really 2:1 /dimetric/): an oblique edge is AA-free
/iff/ its slope is a small-integer ratio @p\/q@; true iso (@tan 30° = 0.577@) is irrational
and forbidden. 'lawOrbitHeroNotPixelExact' makes the orbit failure a /theorem/, so the
integer-table swap is provably mandatory, not a preference.

== The corrected design — front-preserving integer depth-shear

Two independent integer sliders, each a rung @r ∈ [0,'maxRung']@:

  * the X slider shears depth HORIZONTALLY  (@+t → (-rx, 0)@ art-px/slice) — opens a side face
  * the Y slider shears depth VERTICALLY    (@+t → (0, -ry)@ art-px/slice) — opens the top face

The (x,y) front basis is @(artPerVoxel,0)@ / @(0,artPerVoxel)@ at EVERY rung, so the near
face (@t = N-1@, the current frame) is byte-identical to the flat GIF at every pose
('lawFrontSquareAllRungs') — the GIF-identity is preserved /as you rotate/, not only when
flat. (This corrects the synthesised plan's S3, whose @x→(2,1), y→(−2,1)@ would tilt the
front into a diamond and break that identity.) Because every basis component is a small
integer, every voxel corner projects to an exact integer art-pixel at every rung
('lawEveryCornerIntegral') — crisp by construction. @(0,0)@ = flat GIF; @('maxRung','maxRung')@
= the full corner-iso pose showing both the (x,t) and (y,t) side faces as epipolar streaks.

This module pins the POSITIONS (the projection geometry). 'SixFour.Spec.FrontProjection'
pins the COLOURS (the near face shows the cursor frame's @palette[index]@). Together they
discharge full S0 byte-identity with the 2D GIF; the rungs extend it crisply into depth.

GHC-boot-only: base + 'SixFour.Spec.Lattice'.
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide
module SixFour.Spec.VoxelFit
  ( -- * The volume + art-grid constants
    ArtVec, Rung
  , side, artPerVoxel, artRes, voxelPivot, maxRung
    -- * The integer projection
  , depthOf, projectVoxel, cubeCorners, cornersArt, halfSpanOf
  , ProjStop(..), stopAt, voxelLadder
    -- * The per-cell rasterizer (the cube AS cells)
  , cubeBox, rasterSide, cubeRasterMap, cubeCellCount
    -- * The orbit basis (the disproof reference)
  , heroYaw, heroPitch, orbitBasisVec, orbitFitHalfSpan, orbitProjectCorner
    -- * Laws
  , lawFrontSquareAllRungs       -- the near face == GIF positions ∀ rung (identity preserved)
  , lawFlatIsGifPositions        -- rung (0,0) collapses every depth slice onto the front face
  , lawEveryCornerIntegral       -- THE crispness gate: every corner integral ∀ rung
  , lawDepthSlopeSmallInteger    -- the depth edge slope is a small-integer ratio (AA-free)
  , lawFlatHalfSpanIsHalfArtRes  -- flat silhouette is exactly artRes/2 (one voxel = one GIF cell)
  , lawRevealGrowsSilhouette     -- every rotated rung's silhouette exceeds flat (sides reveal)
  , lawOrbitHeroNotPixelExact    -- the orbit basis FAILS integrality at the hero (the disproof)
  , lawCubeBoxContainsSilhouette -- the centered box frames EVERY projected voxel (no clip)
  , lawRasterizeFrontIsGif       -- the near face is fully present + front-most ⇒ front == 2D GIF
  ) where

import qualified Data.Map.Strict as M
import SixFour.Spec.Lattice (previewCells)

-- | A 2D art-pixel vector (the cube renders into an @artRes²@ art grid).
type ArtVec = (Int, Int)

-- | A discrete pose: @(xRung, yRung)@, each in @[0, maxRung]@. The two slider positions.
type Rung = (Int, Int)

-- | The volume side @N = 64@ ('previewCells').
side :: Int
side = previewCells

-- | Art-pixels per voxel along an un-sheared axis. @artRes \/ side = 128\/64 = 2@ — the
-- existing @ART_RES@ quantiser's resolution, so the front face is the GIF at 2× nearest.
artPerVoxel :: Int
artPerVoxel = 2

-- | The art-grid resolution (the @ART_RES@ the raymarcher quantises depth to).
artRes :: Int
artRes = artPerVoxel * side   -- 128

-- | The projection pivot — the cube centre in voxel units (mirrors @fitHalfSpan@'s ±32
-- corners). Voxel @x ∈ [0,63]@ maps so the centre sits near art-px 0.
voxelPivot :: Int
voxelPivot = side `div` 2     -- 32

-- | The deepest rung per slider. @0@ = flat … @maxRung@ = full corner-iso on that axis.
maxRung :: Int
maxRung = 2

-- | Depth of a frame slice: @0@ at the NEAR face (@t = N-1@, the current frame), growing
-- toward the far face. The near face is the reference plane that stays the GIF.
depthOf :: Int -> Int
depthOf t = (side - 1) - t

-- | Project a voxel @(x,y,t)@ under rung @(rx,ry)@ to art-pixels. The (x,y) front basis is
-- fixed; depth shears by @(rx,ry)@ art-px per slice. All-integer ⇒ always on the art grid.
projectVoxel :: Rung -> (Int, Int, Int) -> ArtVec
projectVoxel (rx, ry) (x, y, t) =
  ( artPerVoxel * (x - voxelPivot) + rx * d
  , artPerVoxel * (y - voxelPivot) + ry * d )
  where d = depthOf t

-- | The 8 cube corners @{0,N-1}³@.
cubeCorners :: [(Int, Int, Int)]
cubeCorners = [ (x, y, t) | x <- [0, e], y <- [0, e], t <- [0, e] ]
  where e = side - 1

-- | The corners' art-px under a rung.
cornersArt :: Rung -> [ArtVec]
cornersArt r = map (projectVoxel r) cubeCorners

-- | The exact half-window (art-px from centre) that frames the silhouette at a rung —
-- the integer analogue of @fitHalfSpan@, with NO autofit pad (the pad was the source of
-- the orbit's @+1@ half-span error). Always an integer because the projection is.
halfSpanOf :: Rung -> Int
halfSpanOf r = maximum [ max (abs u) (abs v) | (u, v) <- cornersArt r ]

-- | A fully-described stop: the rung, the three axis images, and the silhouette half-span.
data ProjStop = ProjStop
  { psRung     :: Rung
  , psXAxis    :: ArtVec   -- ^ image of @+x@ — fixed @(artPerVoxel, 0)@
  , psYAxis    :: ArtVec   -- ^ image of @+y@ — fixed @(0, artPerVoxel)@
  , psTAxis    :: ArtVec   -- ^ image of @+t@ — @(-rx, -ry)@ (deeper = up/left by the shear)
  , psHalfSpan :: Int
  } deriving (Eq, Show)

-- | The stop for a rung (the table entry the slider selects).
stopAt :: Rung -> ProjStop
stopAt r@(rx, ry) =
  ProjStop r (artPerVoxel, 0) (0, artPerVoxel) (negate rx, negate ry) (halfSpanOf r)

-- | The full discrete ladder — every @(xRung, yRung)@ pose the two sliders can select.
-- @(0,0)@ is the flat GIF; @(maxRung,maxRung)@ the full corner-iso.
voxelLadder :: [ProjStop]
voxelLadder = [ stopAt (rx, ry) | rx <- [0 .. maxRung], ry <- [0 .. maxRung] ]

-- The per-cell rasterizer (the cube AS cells) --------------------------------

-- | The integer CENTERED bounding box of the silhouette at a rung: @(centerU, centerV,
-- halfExtent)@. The shear term @+rx·d@ grows only positively with depth, so the silhouette
-- is NOT centred on 0 at a rotated rung — 'halfSpanOf' (= max|·|) is the wrong divisor. This
-- frames the box on its actual centre with a SQUARE integer half-extent that contains every
-- corner. (This is the load-bearing correction: a symmetric @halfSpan@ window jams the cube
-- off-centre.) @rasterSide = 2·halfExtent + 1@ is the cell count per side.
cubeBox :: Rung -> (Int, Int, Int)
cubeBox r =
  let cs   = map (cellProject r) cubeCorners
      us   = map fst cs ; vs = map snd cs
      umin = minimum us ; umax = maximum us
      vmin = minimum vs ; vmax = maximum vs
      cu   = (umin + umax) `div` 2
      cv   = (vmin + vmax) `div` 2
      h    = maximum [umax - cu, cu - umin, vmax - cv, cv - vmin]
  in (cu, cv, h)

-- | The raster side @N = 2·halfExtent + 1@ — the cube renders into an @N×N@ cell grid.
rasterSide :: Rung -> Int
rasterSide r = let (_, _, h) = cubeBox r in 2 * h + 1

-- | CELL-scale projection (1 voxel = 1 CELL, the cube law) — distinct from 'projectVoxel'
-- (which is the @artPerVoxel@-scale art grid the retired raymarcher sampled). For the cell
-- rasterizer the front face must be a SOLID 64×64 (no 2× gaps) and the whole cube must shrink
-- to fit as it rotates, so the depth shear steps in WHOLE cells: @u = (x-32) + rx·d@.
cellProject :: Rung -> (Int, Int, Int) -> ArtVec
cellProject (rx, ry) (x, y, t) =
  let d = depthOf t in ((x - voxelPivot) + rx * d, (y - voxelPivot) + ry * d)

-- | FORWARD SCATTER z-buffer: the front-most (nearest depth @d@) voxel @(x,y,d)@ that lands
-- on each output cell @cvv·N + cuu@. Every voxel is opaque, so the smallest @d@ wins. This is
-- the exact geometry the Swift bake mirrors (the Swift loop ships forward scatter, the cheaper
-- byte-identical equivalent of the inverse). The COLOUR (frame remap by cursor) is applied in
-- Swift via the already-proven 'SixFour.Spec.FrontProjection.frontFaceFrame'; this pins only
-- the geometry: which @(x,y,d)@ each cell shows.
cubeRasterMap :: Rung -> M.Map Int (Int, Int, Int)
cubeRasterMap r =
  M.map (\(d, x, y) -> (x, y, d)) $
    M.fromListWith nearer
      [ (cvv * n + cuu, (d, x, y))
      | t <- [0 .. side - 1], let d = (side - 1) - t
      , y <- [0 .. side - 1], x <- [0 .. side - 1]
      , let (pu, pv) = cellProject r (x, y, t)
      , let cuu = pu - cu + h
      , let cvv = pv - cv + h
      , cuu >= 0, cuu < n, cvv >= 0, cvv < n ]
  where
    (cu, cv, h) = cubeBox r
    n = 2 * h + 1
    nearer new@(d1, _, _) old@(d2, _, _) = if d1 <= d2 then new else old

-- | The number of populated (non-empty) cells at a rung — the golden coverage table.
cubeCellCount :: Rung -> Int
cubeCellCount = M.size . cubeRasterMap

-- LAWS ----------------------------------------------------------------------

-- | The near face (@t = N-1@) maps x,y the SAME square way at every rung — so the front
-- face is byte-identical to the flat GIF at /every/ pose, not only flat. Discharge:
-- @depthOf (N-1) = 0@, so the shear term vanishes for all @(rx,ry)@.
lawFrontSquareAllRungs :: Rung -> Int -> Int -> Bool
lawFrontSquareAllRungs r x y =
  projectVoxel r (x, y, side - 1)
    == (artPerVoxel * (x - voxelPivot), artPerVoxel * (y - voxelPivot))

-- | Rung @(0,0)@ collapses EVERY depth slice onto the front face — depth is invisible, so
-- the cube is indistinguishable from the 2D GIF. Discharge: @rx = ry = 0@ zeroes the shear.
lawFlatIsGifPositions :: Int -> Int -> Int -> Bool
lawFlatIsGifPositions x y t =
  projectVoxel (0, 0) (x, y, t) == projectVoxel (0, 0) (x, y, side - 1)

-- | THE crispness gate. Every cube corner projects to an exact integer art-pixel at every
-- rung — checked through a 'Double' rendering so it shares teeth with 'lawOrbitHeroNotPixelExact'.
-- True by construction for the integer table; the orbit basis fails the same predicate.
lawEveryCornerIntegral :: Rung -> Bool
lawEveryCornerIntegral r = all (isIntegralArt . toD . projectVoxel r) cubeCorners
  where toD (u, v) = (fromIntegral u, fromIntegral v)

-- | The depth-axis edge slope is a small-integer ratio @ry\/rx@ (both @≤ maxRung@), so the
-- receding edge staircases without anti-aliasing (the research AA-free condition).
lawDepthSlopeSmallInteger :: Rung -> Bool
lawDepthSlopeSmallInteger r =
  let (tu, tv) = psTAxis (stopAt r) in abs tu <= maxRung && abs tv <= maxRung

-- | The flat silhouette is exactly @artRes\/2@ — one voxel = one GIF cell at 2× nearest,
-- the geometric form of S0 = the 2D GIF.
lawFlatHalfSpanIsHalfArtRes :: Bool
lawFlatHalfSpanIsHalfArtRes = halfSpanOf (0, 0) == artRes `div` 2

-- | Every rotated rung frames a strictly LARGER silhouette than flat — the cube "comes
-- forward" and its side faces appear (voxels shrink to fit, never the box growing on screen).
lawRevealGrowsSilhouette :: Bool
lawRevealGrowsSilhouette =
  all (\r -> r == (0, 0) || halfSpanOf r > halfSpanOf (0, 0))
      [ (rx, ry) | rx <- [0 .. maxRung], ry <- [0 .. maxRung] ]

-- | The centered box frames EVERY projected voxel — no corner of the silhouette is clipped at
-- any rung. (This is what 'halfSpanOf' as a symmetric divisor got wrong; 'cubeBox' fixes it.)
lawCubeBoxContainsSilhouette :: Rung -> Bool
lawCubeBoxContainsSilhouette r =
  and [ cuu >= 0 && cuu < n && cvv >= 0 && cvv < n
      | t <- [0 .. side - 1]
      , y <- [0 .. side - 1], x <- [0 .. side - 1]
      , let (pu, pv) = cellProject r (x, y, t)
      , let cuu = pu - cu + h
      , let cvv = pv - cv + h ]
  where (cu, cv, h) = cubeBox r
        n = 2 * h + 1

-- | THE crispness theorem for the rasterizer: the near face (@d = 0@, @t = N-1@) is FULLY
-- present and front-most at every rung — every one of the 4096 near-face voxels @(x,y)@ lands
-- on its own cell and wins the z-test (d=0 is minimal). So the rasterized front face is
-- exactly the 2D GIF grid (RULE-CUBE-2D-IDENTITY in cell space), crisp at every rung. The
-- side faces appear only where deeper slices peek past the near face's silhouette.
lawRasterizeFrontIsGif :: Rung -> Bool
lawRasterizeFrontIsGif r =
  and [ M.lookup (cvv * n + cuu) m == Just (x, y, 0)
      | x <- [0 .. side - 1], y <- [0 .. side - 1]
      , let cuu = (x - voxelPivot) - cu + h
      , let cvv = (y - voxelPivot) - cv + h ]
  where (cu, cv, h) = cubeBox r
        n = 2 * h + 1
        m = cubeRasterMap r

-- The orbit basis (the disproof reference) -----------------------------------

-- | The 45°/30° "hero" the orbit camera aimed at.
heroYaw, heroPitch :: Double
heroYaw   = pi / 4
heroPitch = pi / 6

-- | A 'Double' mirror of Swift @VoxelIso.orbit@: yaw about world-Y, then Rodrigues pitch
-- about the camera-right axis. Returns the camera-basis image of a canonical axis @v@.
orbitBasisVec :: (Double, Double, Double) -> Double -> Double -> (Double, Double, Double)
orbitBasisVec (vx, vy, vz) yaw pitch =
  ( ax * cp + crx * sp + rx * rda * (1 - cp)
  , ay * cp + cry * sp + ry * rda * (1 - cp)
  , az * cp + crz * sp + rz * rda * (1 - cp) )
  where
    cy = cos yaw; sy = sin yaw
    ax = cy * vx + sy * vz; ay = vy; az = -sy * vx + cy * vz
    rx = cy; ry = 0; rz = -sy
    cp = cos pitch; sp = sin pitch
    crx = ry * az - rz * ay; cry = rz * ax - rx * az; crz = rx * ay - ry * ax
    rda = rx * ax + ry * ay + rz * az

-- | A 'Double' mirror of @VoxelIso.fitHalfSpan@ (silhouette autofit + the orbited @+1@ pad).
orbitFitHalfSpan :: Double -> Double -> Double
orbitFitHalfSpan yaw pitch = m + (if orbited then 1 else 0)
  where
    xb = orbitBasisVec (1, 0, 0) yaw pitch
    yb = orbitBasisVec (0, 1, 0) yaw pitch
    dot (a, b, c) (d, e, f) = a * d + b * e + c * f
    m = maximum [ max (abs (dot c xb)) (abs (dot c yb))
                | sx <- [-32, 32], sy <- [-32, 32], sz <- [-32, 32]
                , let c = (sx, sy, sz) ]
    orbited = yaw * yaw + pitch * pitch > 1e-6

-- | The orbit camera's art-px image of a voxel corner at the hero (basis · centred-corner,
-- scaled so the silhouette fills the art grid). The analogue of 'projectVoxel' for the orbit.
orbitProjectCorner :: (Int, Int, Int) -> (Double, Double)
orbitProjectCorner (x, y, t) =
  (dot c xb * scale, dot c yb * scale)
  where
    c  = (fromIntegral x - 32, fromIntegral y - 32, fromIntegral t - 32)
    xb = orbitBasisVec (1, 0, 0) heroYaw heroPitch
    yb = orbitBasisVec (0, 1, 0) heroYaw heroPitch
    dot (a, b, e) (d, f, g) = a * d + b * f + e * g
    scale = (fromIntegral artRes / 2) / orbitFitHalfSpan heroYaw heroPitch

-- | THE DISPROOF: at the hero the orbit basis sends at least one cube corner to a
-- NON-integer art-pixel — so the orbit camera cannot be crisp at a rotated stop, and the
-- integer-table swap is mandatory. (Contrast 'lawEveryCornerIntegral', which holds ∀ rung.)
lawOrbitHeroNotPixelExact :: Bool
lawOrbitHeroNotPixelExact = any (not . isIntegralArt . orbitProjectCorner) cubeCorners

-- | Is an art-px coordinate exactly integral?
isIntegralArt :: (Double, Double) -> Bool
isIntegralArt (u, v) =
  u == fromIntegral (round u :: Int) && v == fromIntegral (round v :: Int)
