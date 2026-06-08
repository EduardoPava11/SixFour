{- |
Module      : SixFour.Spec.CloudProjection
Description : Distance-honest projection geometry for the P4 OKLab Temporal Cloud.

The source of truth for the Review screen's @PaletteCloudView@ (P4 — see
@docs/SIXFOUR-HIGHDIM-UIUX.md@ §3 and @docs/palette-explorer-2d-3d-4d-design.md@
§2.3). The cloud plots the 256 palette colours at their __true OKLab coordinates__
and lets the user PROJECT that 3-space onto the 2-D screen by orbiting, and the
4th axis (time, the 64 frames) by scrubbing a playhead.

== The governing principle: projection IS the interaction

We never try to show 4-D at once. 2-D and 3-D are the honest projection TARGETS,
because they are the only surfaces we can make controls out of. So:

  * orbit (yaw\/pitch) = pick the 3-D→2-D projection;
  * an OKLab axis-pair plane (a×b, L×a, L×b) = a faithful planar shadow you snap to;
  * the playhead = the time projection.

== Distance honesty — the one theorem this module pins

1. __World map is an isometry up to a single isotropic scale__ (@oklabToWorld@).
   We map @OKLab (L,a,b)@ to world @(x,y,z) = ((a-aᶜ)·s, (L-Lᶜ)·s, (b-bᶜ)·s)@
   with the __same__ scale @s@ on all three axes and a fixed canonical centre.
   Because the scale is isotropic, world Euclidean distance equals @s ×@ OKLab
   Euclidean distance __exactly__ (@lawWorldIsometry@). Per-axis normalisation —
   the obvious "fit the box" move — is FORBIDDEN here: it would stretch the axes
   independently and silently distort perceptual distance.

2. __Orbit is a rotation, hence an isometry__ (@rotateYawPitch@): yaw about the
   world up-axis Y then pitch about X. 3-D distance is preserved exactly
   (@lawRotationIsometry@), so orbiting never changes what the data MEANS.

3. __Orthographic projection drops the depth coordinate__ (@orthographic@): screen
   @(u,v) = (x_cam, y_cam)@, with @z_cam@ kept only for depth-sort\/occlusion.
   Dropping one orthonormal coordinate is a 1-Lipschitz contraction: on-screen
   distance is __≤__ true distance, with EQUALITY for any pair lying in the
   view plane (@lawOrthographicInPlaneExact@, @lawOrthographicContracts@). That is
   the exact, defensible "screen distance = perceptual distance" claim — true in
   the plane, never an over-statement out of it.

4. __Perspective breaks the claim__ (@perspective@): the on-screen separation of a
   segment depends on its depth, so two equal-length 3-D segments at different
   depths project to different screen lengths (@lawPerspectiveDistorts@). Hence
   perspective is the labelled "explore" mode with the distance claim REMOVED;
   orthographic is the sticky default.

== The AABB gamut hull (deterministic, not float gift-wrap)

@aabbHull@ is the axis-aligned bounding box of a set of OKLab points: a pair of
opposite corners. It is the honest, order-independent gamut extent (no
non-deterministic convex-hull tie-breaks). For a @SplitTree@\/branching subtree
this draws the half-set's perceptual extent. @lawHullContainsAll@,
@lawHullDeterministic@.

== Population → radius (a non-positional channel)

@populationRadius@ maps a slot's pixel count to a dot radius so that visual AREA
∝ population (radius ∝ √count): the perceptually-correct "how much of the frame
is this colour" channel. @lawRadiusMonotone@, @lawRadiusBounded@.

== Temporal lerp (the 4th axis, between integer frames)

@temporalLerp@ linearly interpolates a colour's world position between two frame
positions for sub-frame scrubbing\/trails. @lawLerpEndpoints@, @lawLerpOnSegment@.

== Quad4 768→513 lossy ghost

@quad4GhostError@ reuses 'SixFour.Spec.Quad4.quad4Analyze' (the lossy
opponent-quadrant projection) to compute, per leaf, the displacement from the
true OKLab leaf to its 513-DOF reconstruction. These are the ghost points +
arrows the cloud may draw — always tagged LOSSY, never as truth.
@lawGhostZeroOnSubspace@.

The projection LAWS here are golden-pinned (see @Properties.CloudProjection@).
The Swift port (@PaletteCloudView.swift@) ports this math but is NOT yet pinned
bit-for-bit against it: there is no @Codegen.CloudProjection@ emitter or
golden-vector parity test, and the perspective @eye@ + population→radius range
currently diverge in the renderer. Closing that (a codegen emitter + parity
test) is the remaining spec-first debt before P4 ships.
-}
module SixFour.Spec.CloudProjection
  ( -- * World basis
    Vec3(..)
    -- ** Fixed canonical OKLab box → world
  , canonicalCentre
  , canonicalScale
  , oklabToWorld
    -- * Camera
  , rotateYawPitch
  , orthographic
  , perspective
  , Screen(..)
    -- * Axis-pair planar shadows
  , AxisPair(..)
  , axisPairOrbit
    -- * Gamut hull
  , aabbHull
    -- * Non-positional channels
  , populationRadius
  , radiusMin
  , radiusMax
    -- * Temporal axis
  , temporalLerp
    -- * Quad4 lossy ghost
  , quad4GhostError
    -- * Laws
  , lawWorldIsometry
  , lawRotationIsometry
  , lawOrthographicInPlaneExact
  , lawOrthographicContracts
  , lawPerspectiveDistorts
  , lawHullContainsAll
  , lawHullDeterministic
  , lawRadiusMonotone
  , lawRadiusBounded
  , lawLerpEndpoints
  , lawLerpOnSegment
  , lawGhostZeroOnSubspace
  ) where

import Data.List (foldl')

import SixFour.Spec.Color (OKLab(..))
import SixFour.Spec.Quad4 (Quad4Palette, reconstruct, quad4Analyze)

-- | A 3-vector in world space (after the OKLab→world map and any rotation).
data Vec3 = Vec3 !Double !Double !Double
  deriving (Eq, Show)

-- | A 2-D screen point (projection target).
data Screen = Screen !Double !Double
  deriving (Eq, Show)

-- | Vector subtraction in 3-D.
vsub :: Vec3 -> Vec3 -> Vec3
vsub (Vec3 x y z) (Vec3 x' y' z') = Vec3 (x - x') (y - y') (z - z')

-- | Euclidean norm of a 3-D vector.
vnorm :: Vec3 -> Double
vnorm (Vec3 x y z) = sqrt (x * x + y * y + z * z)

-- | Euclidean distance between two 3-D points.
vdist :: Vec3 -> Vec3 -> Double
vdist a b = vnorm (vsub a b)

-- * World basis -----------------------------------------------------------

-- | Fixed canonical OKLab centre @(Lᶜ, aᶜ, bᶜ)@. NOT data-derived (so the axes
-- never drift between frames — the explicit fix for "nothing is held fixed to
-- read"): @L@ centred at mid-lightness 0.5, the opponent axes at neutral 0.
canonicalCentre :: OKLab
canonicalCentre = OKLab 0.5 0.0 0.0

-- | The single isotropic world scale. Chosen so the widest nominal half-range
-- (@L@ half-range 0.5) maps to 1.0 → @s = 1\/0.5 = 2@. Applied identically to
-- L, a, b so the map is a similarity (distance-true up to the constant @s@).
-- The a\/b nominal half-range 0.4 maps to 0.8, so the chroma disc sits inside
-- the unit box — correct, not clipped.
canonicalScale :: Double
canonicalScale = 2.0

-- | @OKLab (L,a,b)@ → world @(x,y,z)@. AXIS LAW: @a→x@, @L→y@ (up), @b→z@.
-- Centred then isotropically scaled. The ONLY world placement; per-axis
-- normalisation is forbidden (it would distort perceptual distance).
oklabToWorld :: OKLab -> Vec3
oklabToWorld (OKLab l a b) =
  let OKLab lc ac bc = canonicalCentre
      s              = canonicalScale
  in Vec3 ((a - ac) * s) ((l - lc) * s) ((b - bc) * s)

-- * Camera ----------------------------------------------------------------

-- | Orbit: yaw about world up-axis Y, then pitch about X. Identical convention
-- to the voxel cube (@VoxelCubeView@). A composition of two rotations, hence an
-- orthogonal (isometric) transform.
rotateYawPitch :: Double -> Double -> Vec3 -> Vec3
rotateYawPitch yaw pitch (Vec3 x y z) =
  let cy = cos yaw;   sy = sin yaw
      -- yaw about Y: (x,z) rotate
      x1 = cy * x + sy * z
      z1 = -sy * x + cy * z
      cp = cos pitch; sp = sin pitch
      -- pitch about X: (y,z) rotate
      y2 = cp * y - sp * z1
      z2 = sp * y + cp * z1
  in Vec3 x1 y2 z2

-- | Orthographic projection: keep @(x,y)@ as screen @(u,v)@; @z@ is depth only
-- (returned by the caller separately for sorting). A 1-Lipschitz contraction —
-- the honest projection. (Screen flips Y for top-down pixel coords in the view
-- layer; that is a renderer concern, not a spec one.)
orthographic :: Vec3 -> Screen
orthographic (Vec3 x y _z) = Screen x y

-- | Perspective projection with eye at @+eye@ on the camera Z axis looking toward
-- the origin: @(u,v) = (x,y) · eye\/(eye − z)@. The depth-dependent magnification
-- is exactly what makes it distance-DISHONEST; it is the labelled explore mode.
-- @eye@ must exceed every point's @z@ (no point behind the eye).
perspective :: Double -> Vec3 -> Screen
perspective eye (Vec3 x y z) =
  let w = eye / (eye - z)
  in Screen (x * w) (y * w)

-- * Axis-pair planar shadows ----------------------------------------------

-- | The three faithful planar shadows = a snap-to view that puts a chosen OKLab
-- axis pair flat to the screen. Each is a specific @(yaw, pitch)@ of the orbit
-- (so picking a plane and orbiting are the SAME control). With L→y, a→x, b→z:
--
--   * @PlaneAB@  (chroma disc, the default top-down): look down −Y onto the a×b
--     plane → @(yaw, pitch) = (0, −π\/2)@. u = a, v = b.
--   * @PlaneLA@  (front, lightness × green–red): identity → @(0, 0)@. u = a, v = L.
--   * @PlaneLB@  (side, lightness × blue–yellow): yaw +π\/2 → @(π\/2, 0)@. u = b, v = L.
data AxisPair = PlaneAB | PlaneLA | PlaneLB
  deriving (Eq, Show, Enum, Bounded)

-- | The @(yaw, pitch)@ orbit angles that snap an 'AxisPair' flat to the screen.
axisPairOrbit :: AxisPair -> (Double, Double)
axisPairOrbit PlaneLA = (0, 0)
axisPairOrbit PlaneLB = (pi / 2, 0)
axisPairOrbit PlaneAB = (0, -pi / 2)

-- * Gamut hull ------------------------------------------------------------

-- | Axis-aligned bounding box of a non-empty OKLab set, as @(loCorner, hiCorner)@
-- in OKLab. Deterministic and order-independent (min\/max fold) — no float
-- convex-hull tie-break. The honest gamut extent of a (sub)palette.
aabbHull :: [OKLab] -> (OKLab, OKLab)
aabbHull []       = (OKLab 0 0 0, OKLab 0 0 0)
aabbHull (c : cs) = foldl' step (c, c) cs
  where
    step (OKLab lo ao bo, OKLab lh ah bh) (OKLab l a b) =
      ( OKLab (min lo l) (min ao a) (min bo b)
      , OKLab (max lh l) (max ah a) (max bh b) )

-- * Population → radius ----------------------------------------------------

-- | Smallest dot radius (world units): a slot at the significance floor.
radiusMin :: Double
radiusMin = 0.6

-- | Largest dot radius (world units): a slot covering the whole frame.
radiusMax :: Double
radiusMax = 3.0

-- | Population → dot radius. Area ∝ population ⇒ radius ∝ √population, scaled so
-- @count == 0@ ⇒ 'radiusMin' and @count == maxCount@ ⇒ 'radiusMax'. The
-- non-positional density channel (from @perFrameCells[..].count@).
populationRadius :: Int -> Int -> Double
populationRadius maxCount count
  | maxCount <= 0 = radiusMin
  | otherwise     =
      let frac = fromIntegral (max 0 (min count maxCount)) / fromIntegral maxCount
      in radiusMin + (radiusMax - radiusMin) * sqrt frac

-- * Temporal axis ----------------------------------------------------------

-- | Linear interpolation of a world position between two frames' positions, by
-- @t ∈ [0,1]@. The sub-frame scrub\/trail interpolation along the 4th axis.
temporalLerp :: Double -> Vec3 -> Vec3 -> Vec3
temporalLerp t (Vec3 x0 y0 z0) (Vec3 x1 y1 z1) =
  Vec3 (lerp x0 x1) (lerp y0 y1) (lerp z0 z1)
  where lerp a b = a + (b - a) * t

-- * Quad4 lossy ghost ------------------------------------------------------

-- | Per-leaf displacement (in OKLab) from the true leaves to their 513-DOF Quad4
-- reconstruction. Reuses the LOSSY 'quad4Analyze' projection — these are the
-- ghost points\/arrows the cloud may draw, always tagged lossy. For 256 input
-- leaves returns 256 @(trueLeaf, ghostLeaf)@ pairs.
quad4GhostError :: [OKLab] -> [(OKLab, OKLab)]
quad4GhostError leaves =
  let ghost = reconstruct (quad4Analyze leaves)
  in zip leaves ghost

-- * Laws ===================================================================

-- | World map is a similarity: world distance == 'canonicalScale' × OKLab
-- distance, exactly (up to @tol@). This is the distance-truth foundation.
lawWorldIsometry :: Double -> OKLab -> OKLab -> Bool
lawWorldIsometry tol c1 c2 =
  let od = okDist c1 c2
      wd = vdist (oklabToWorld c1) (oklabToWorld c2)
  in abs (wd - canonicalScale * od) <= tol

-- | Orbit preserves 3-D distance (rotation is an isometry).
lawRotationIsometry :: Double -> Double -> Double -> Vec3 -> Vec3 -> Bool
lawRotationIsometry tol yaw pitch p q =
  let d0 = vdist p q
      d1 = vdist (rotateYawPitch yaw pitch p) (rotateYawPitch yaw pitch q)
  in abs (d1 - d0) <= tol

-- | Orthographic projection is EXACT for any pair sharing a depth (both in the
-- view plane): screen distance == 3-D distance when @z@ is equal. This is the
-- precise sense in which "screen distance = perceptual distance".
lawOrthographicInPlaneExact :: Double -> Double -> Double -> Double -> Double -> Double -> Bool
lawOrthographicInPlaneExact tol x0 y0 x1 y1 z =
  let p = Vec3 x0 y0 z
      q = Vec3 x1 y1 z          -- same depth
      Screen u0 v0 = orthographic p
      Screen u1 v1 = orthographic q
      sd = sqrt ((u1 - u0) ** 2 + (v1 - v0) ** 2)
      d3 = vdist p q
  in abs (sd - d3) <= tol

-- | Orthographic projection never EXPANDS distance (1-Lipschitz). On-screen
-- distance ≤ true 3-D distance — so the projection can only under-state, never
-- over-state, perceptual separation.
lawOrthographicContracts :: Double -> Vec3 -> Vec3 -> Bool
lawOrthographicContracts tol p q =
  let Screen u0 v0 = orthographic p
      Screen u1 v1 = orthographic q
      sd = sqrt ((u1 - u0) ** 2 + (v1 - v0) ** 2)
      d3 = vdist p q
  in sd <= d3 + tol

-- | Perspective DISTORTS: an axis-aligned segment of fixed 3-D length projects
-- to different screen lengths at different depths (the distance lie). We assert
-- the two screen lengths differ by more than @gap@ for a near\/far pair.
lawPerspectiveDistorts :: Double -> Bool
lawPerspectiveDistorts gap =
  let eye  = 4.0
      near = (Vec3 (-0.5) 0 0.0, Vec3 0.5 0 0.0)   -- length 1, depth 0
      far  = (Vec3 (-0.5) 0 2.0, Vec3 0.5 0 2.0)   -- length 1, depth 2
      slen (a, b) = let Screen ua va = perspective eye a
                        Screen ub vb = perspective eye b
                    in sqrt ((ub - ua) ** 2 + (vb - va) ** 2)
  in abs (slen far - slen near) > gap

-- | The AABB hull contains every input point (each coordinate within
-- @[loCorner, hiCorner]@).
lawHullContainsAll :: [OKLab] -> Bool
lawHullContainsAll [] = True
lawHullContainsAll cs =
  let (OKLab llo alo blo, OKLab lhi ahi bhi) = aabbHull cs
  in all (\(OKLab l a b) ->
            l >= llo && l <= lhi && a >= alo && a <= ahi && b >= blo && b <= bhi) cs

-- | The hull is order-independent (deterministic): @aabbHull cs == aabbHull (reverse cs)@.
lawHullDeterministic :: [OKLab] -> Bool
lawHullDeterministic cs = aabbHull cs == aabbHull (reverse cs)

-- | Radius is monotone non-decreasing in population.
lawRadiusMonotone :: Int -> Int -> Int -> Bool
lawRadiusMonotone maxC c1 c2 =
  c1 > c2 || populationRadius maxC c1 <= populationRadius maxC c2 + 1e-12

-- | Radius stays within @['radiusMin', 'radiusMax']@.
lawRadiusBounded :: Int -> Int -> Bool
lawRadiusBounded maxC count =
  let r = populationRadius maxC count
  in r >= radiusMin - 1e-12 && r <= radiusMax + 1e-12

-- | @temporalLerp 0 = fst@, @temporalLerp 1 = snd@ (endpoints exact).
lawLerpEndpoints :: Double -> Vec3 -> Vec3 -> Bool
lawLerpEndpoints tol p q =
  vclose tol (temporalLerp 0 p q) p && vclose tol (temporalLerp 1 p q) q

-- | The lerp lies on the segment: @dist(p, lerp) + dist(lerp, q) == dist(p, q)@.
lawLerpOnSegment :: Double -> Double -> Vec3 -> Vec3 -> Bool
lawLerpOnSegment tol t0 p q =
  let t = max 0 (min 1 t0)
      m = temporalLerp t p q
  in abs (vdist p m + vdist m q - vdist p q) <= tol

-- | On the Quad4 subspace (leaves that ARE a Quad4 reconstruction) the ghost
-- error is zero — the lossy projection is exact there. (For arbitrary leaves the
-- error is nonzero; that nonzero displacement IS the honest "this is lossy" cue.)
lawGhostZeroOnSubspace :: Double -> Quad4Palette -> Bool
lawGhostZeroOnSubspace tol qp =
  let leaves = reconstruct qp
  in all (\(t, g) -> okClose tol t g) (quad4GhostError leaves)

-- internal ----------------------------------------------------------------

-- | Euclidean distance between two OKLab colours.
okDist :: OKLab -> OKLab -> Double
okDist (OKLab l a b) (OKLab l' a' b') =
  sqrt ((l - l') ** 2 + (a - a') ** 2 + (b - b') ** 2)

-- | Two OKLab colours within @tol@ on every channel (L∞ ball).
okClose :: Double -> OKLab -> OKLab -> Bool
okClose tol (OKLab l a b) (OKLab l' a' b') =
  abs (l - l') <= tol && abs (a - a') <= tol && abs (b - b') <= tol

-- | Two 3-D vectors within @tol@ on every component (L∞ ball).
vclose :: Double -> Vec3 -> Vec3 -> Bool
vclose tol (Vec3 x y z) (Vec3 x' y' z') =
  abs (x - x') <= tol && abs (y - y') <= tol && abs (z - z') <= tol
