{- |
Module      : SixFour.Spec.ChromaRotation
Description : The chroma-swipe rotation gauge — SO(2)/Cn on the (a,b) plane (L fixed), with the bit-exact C4 subgroup and float-guidance detents.

The "turn" gesture: the user rotates the swipe frame clockwise/counter-clockwise.
Base @up/down = a@ (red-green), @left/right = b@ (yellow-blue); a turn applies
@R_theta@ to the @(a,b)@ chroma plane while __L is fixed__ (L is the universal
axis, "SixFour.Spec.XYTLabDuality" @lawUniversalIsTL@). At 45deg the diagonals
blend (orange @+a+b@, purple @+a-b@); near the gray axis @(a,b)->(0,0)@ the
rotation is the SO(2) FIXED POINT (hue undefined) = the "collapse proximity"
('isDegenerate').

This is a sibling of "SixFour.Spec.CanonicalPhase" (the temporal-loop gauge) but
on the chroma plane, and it continuously breaks "SixFour.Spec.GenomePair"'s exact
@a perp b@ orthogonality.

== Exact vs float (honest determinism boundary)

Only the QUARTER-TURN subgroup @C4@ ('rotateQuarter': 90/180/270 + identity) is
bit-exact integer Q16 (sign swaps/negations) — these are the laws that gate. The
user's detents @C12@/@C8@/@C6@ (30/45/60deg) have irrational @cos@/@sin@, so
'rotateChroma' is __float-guidance__ that must re-enter the Zig Q16 floor
(@zero-genome == floor@) before GIF bytes, exactly the Core AI L-inference rule.
@C4@ lives inside the 30deg and 45deg detent grids (not 60deg) — 'lawQuarterInDetent'.

GHC-boot-only. Laws QuickCheck'd in @Properties.ChromaRotation@.
-}
module SixFour.Spec.ChromaRotation
  ( -- * Detents (the option space)
    Detent(..)
  , detentCount
  , detentStepDeg
    -- * The bit-exact quarter-turn subgroup C4
  , rotateQuarter
  , canonicalQuarter
    -- * The collapse-proximity guard
  , isDegenerate
    -- * Float-guidance rotation (the 30/45/60 detents; NOT bit-exact)
  , rotateChroma
    -- * Laws (QuickCheck'd in @Properties.ChromaRotation@)
  , lawRotateQuarterComposes
  , lawRotateFixesGray
  , lawRightAngleFullTurn
  , lawCanonicalChromaGaugeFixed
  , lawGrayIsDegenerate
  , lawDetentSteps
  , lawQuarterInDetent
  , lawFloatMatchesQuarterAtRightAngle
  ) where

-- | The cyclic detent sets the user can turn through: @C12@ = 30deg steps,
-- @C8@ = 45deg, @C6@ = 60deg.
data Detent = C12 | C8 | C6
  deriving (Eq, Show, Enum, Bounded)

-- | Number of detents in a turn (the cyclic order @n@).
detentCount :: Detent -> Int
detentCount C12 = 12
detentCount C8  = 8
detentCount C6  = 6

-- | The angular step of a detent, in degrees: @360 / n@ (30, 45, 60).
detentStepDeg :: Detent -> Int
detentStepDeg d = 360 `div` detentCount d

-- | The bit-exact quarter-turn @R_(90*q)@ on the @(a,b)@ chroma plane (L untouched
-- elsewhere). Integer-exact for all @q@ (sign swaps), order 4.
rotateQuarter :: Int -> (Int, Int) -> (Int, Int)
rotateQuarter q (a, b) = case q `mod` 4 of
  0 -> ( a,  b)
  1 -> (-b,  a)
  2 -> (-a, -b)
  _ -> ( b, -a)

-- | The C4 necklace gauge-fix: the lexicographically-greatest of a palette's four
-- quarter-turn images, so quarter-rotation-equivalent looks collapse to ONE
-- canonical form (the chroma analogue of "SixFour.Spec.CanonicalPhase").
canonicalQuarter :: [(Int, Int)] -> [(Int, Int)]
canonicalQuarter pal = maximum [ map (rotateQuarter q) pal | q <- [0 .. 3] ]

-- | The collapse-proximity guard: a chroma point within @floorR@ of the gray axis
-- (@a^2 + b^2 < floorR^2@) is degenerate — its hue is undefined and the swipe
-- angle is noise.
isDegenerate :: Int -> (Int, Int) -> Bool
isDegenerate floorR (a, b) = a * a + b * b < floorR * floorR

-- | Float-guidance rotation by an arbitrary angle (radians) on @(a,b)@, L fixed.
-- NOT bit-exact (irrational @cos@/@sin@ at 30/45/60deg); its result must re-enter
-- the Zig Q16 floor before GIF bytes. Only 'rotateQuarter' is bit-exact.
rotateChroma :: Double -> (Double, Double) -> (Double, Double)
rotateChroma th (a, b) = (a * cos th - b * sin th, a * sin th + b * cos th)

-- | C4 is a group action: @R_p . R_q = R_(p+q)@ (exact, cyclic mod 4).
lawRotateQuarterComposes :: Int -> Int -> (Int, Int) -> Bool
lawRotateQuarterComposes p q v =
  rotateQuarter p (rotateQuarter q v) == rotateQuarter (p + q) v

-- | The gray axis is the SO(2) fixed point: @R_theta (0,0) = (0,0)@ for every turn.
lawRotateFixesGray :: Int -> Bool
lawRotateFixesGray q = rotateQuarter q (0, 0) == (0, 0)

-- | A full turn is the identity: @R_(4*k) = id@.
lawRightAngleFullTurn :: Int -> (Int, Int) -> Bool
lawRightAngleFullTurn k v = rotateQuarter (4 * k) v == v

-- | THE KEYSTONE: the canonical form is invariant under any quarter-turn — every
-- rotation of a look has the SAME canonical form (exact), so rotation-equivalent
-- looks dedup to one node.
lawCanonicalChromaGaugeFixed :: Int -> [(Int, Int)] -> Bool
lawCanonicalChromaGaugeFixed r pal =
  canonicalQuarter (map (rotateQuarter r) pal) == canonicalQuarter pal

-- | The gray axis is always degenerate for a positive floor.
lawGrayIsDegenerate :: Int -> Bool
lawGrayIsDegenerate floorR = floorR <= 0 || isDegenerate floorR (0, 0)

-- | The detent steps are 30/45/60 and each divides the circle.
lawDetentSteps :: Bool
lawDetentSteps =
     detentStepDeg C12 == 30 && detentStepDeg C8 == 45 && detentStepDeg C6 == 60
  && all (\d -> 360 `mod` detentCount d == 0) [minBound .. maxBound]

-- | The bit-exact C4 (90deg) lives inside the 30deg and 45deg detent grids, but
-- NOT the 60deg grid (90 is a multiple of 30 and 45, not of 60).
lawQuarterInDetent :: Bool
lawQuarterInDetent =
     90 `mod` detentStepDeg C12 == 0
  && 90 `mod` detentStepDeg C8  == 0
  && 90 `mod` detentStepDeg C6  /= 0

-- | The float-guidance path agrees with the exact subgroup at a right angle:
-- @rotateChroma (pi/2) ~ rotateQuarter 1@.
lawFloatMatchesQuarterAtRightAngle :: Int -> Int -> Bool
lawFloatMatchesQuarterAtRightAngle a b =
  let (a', b') = rotateQuarter 1 (a, b)
      (fa, fb) = rotateChroma (pi / 2) (fromIntegral a, fromIntegral b)
  in abs (fa - fromIntegral a') < 1e-6 && abs (fb - fromIntegral b') < 1e-6
