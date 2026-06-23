{- |
Module      : SixFour.Spec.Color
Description : sRGB ↔ OKLab transforms, bit-mirrored from ColorScience.swift.

Every constant in this module appears verbatim in
@SixFour/Color/ColorScience.swift@. The QuickCheck round-trip property
asserts the two implementations agree to within 1e-6.
-}
-- COMPARTMENT: METAL-GPU | tag:none
module SixFour.Spec.Color
  ( OKLab(..)
  , SRGB(..)
  , srgbToLinear
  , linearToSRGB
  , linearSRGBToOKLab
  , okLabToLinearSRGB
  , srgbToOKLab
  , okLabToSRGB
  , okLabDistanceSquared
    -- * Bit-exact constants exposed for codegen
  , m1, m2
  ) where

-- | OKLab triple. @L ∈ [0,1]@, @a, b ∈ roughly [-0.4, 0.4]@.
data OKLab = OKLab !Double !Double !Double
  deriving (Eq, Show)

-- | sRGB triple in @[0,1]@ (gamma-encoded).
data SRGB  = SRGB  !Double !Double !Double
  deriving (Eq, Show)

-- | sRGB gamma → linear.
srgbToLinear :: Double -> Double
srgbToLinear x
  | x <= 0.04045 = x / 12.92
  | otherwise    = ((x + 0.055) / 1.055) ** 2.4

-- | Linear → sRGB gamma.
linearToSRGB :: Double -> Double
linearToSRGB x
  | x <= 0.0031308 = 12.92 * x
  | otherwise      = 1.055 * (x ** (1.0 / 2.4)) - 0.055

-- | Björn Ottosson's M1 matrix (linear sRGB → LMS), row-major.
-- Source: <https://bottosson.github.io/posts/oklab/>
m1 :: ((Double, Double, Double), (Double, Double, Double), (Double, Double, Double))
m1 =
  ( (0.4122214708, 0.5363325363, 0.0514459929)
  , (0.2119034982, 0.6806995451, 0.1073969566)
  , (0.0883024619, 0.2817188376, 0.6299787005)
  )

-- | M2 matrix (LMS' → OKLab).
m2 :: ((Double, Double, Double), (Double, Double, Double), (Double, Double, Double))
m2 =
  ( ( 0.2104542553,  0.7936177850, -0.0040720468)
  , ( 1.9779984951, -2.4285922050,  0.4505937099)
  , ( 0.0259040371,  0.7827717662, -0.8086757660)
  )

-- | Linear-sRGB → OKLab (Ottosson: the @M1@ matrix, per-channel cube root, then @M2@).
linearSRGBToOKLab :: (Double, Double, Double) -> OKLab
linearSRGBToOKLab (r, g, b) =
  let ((m1_00, m1_01, m1_02), (m1_10, m1_11, m1_12), (m1_20, m1_21, m1_22)) = m1
      ((m2_00, m2_01, m2_02), (m2_10, m2_11, m2_12), (m2_20, m2_21, m2_22)) = m2
      l  = m1_00 * r + m1_01 * g + m1_02 * b
      m  = m1_10 * r + m1_11 * g + m1_12 * b
      s  = m1_20 * r + m1_21 * g + m1_22 * b
      lc = cbrt l
      mc = cbrt m
      sc = cbrt s
      bigL = m2_00 * lc + m2_01 * mc + m2_02 * sc
      aOut = m2_10 * lc + m2_11 * mc + m2_12 * sc
      bOut = m2_20 * lc + m2_21 * mc + m2_22 * sc
  in OKLab bigL aOut bOut

-- | OKLab → linear-sRGB — the exact inverse of 'linearSRGBToOKLab' (@M2⁻¹@, cube, @M1⁻¹@).
okLabToLinearSRGB :: OKLab -> (Double, Double, Double)
okLabToLinearSRGB (OKLab bigL aIn bIn) =
  -- Inverse of M2 is hard-coded (taken from Ottosson's reference impl).
  let l_ = bigL + 0.3963377774 * aIn + 0.2158037573 * bIn
      m_ = bigL - 0.1055613458 * aIn - 0.0638541728 * bIn
      s_ = bigL - 0.0894841775 * aIn - 1.2914855480 * bIn
      l  = l_ * l_ * l_
      m  = m_ * m_ * m_
      s  = s_ * s_ * s_
      r  =  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
      g  = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
      b  = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
  in (r, g, b)

-- | Convenience: sRGB-gamma triple → OKLab.
srgbToOKLab :: SRGB -> OKLab
srgbToOKLab (SRGB r g b) =
  linearSRGBToOKLab (srgbToLinear r, srgbToLinear g, srgbToLinear b)

-- | Convenience: OKLab → sRGB-gamma triple (unclamped — callers clamp/round).
okLabToSRGB :: OKLab -> SRGB
okLabToSRGB lab =
  let (lr, lg, lb) = okLabToLinearSRGB lab
  in SRGB (linearToSRGB lr) (linearToSRGB lg) (linearToSRGB lb)

-- | Squared Euclidean distance in OKLab — perceptually uniform-ish, cheap.
okLabDistanceSquared :: OKLab -> OKLab -> Double
okLabDistanceSquared (OKLab l1 a1 b1) (OKLab l2 a2 b2) =
  let dL = l1 - l2
      dA = a1 - a2
      dB = b1 - b2
  in dL*dL + dA*dA + dB*dB

-- | Real cube root that handles negatives (Haskell's '**' goes complex).
cbrt :: Double -> Double
cbrt x
  | x < 0     = - ((-x) ** (1/3))
  | otherwise =    x  ** (1/3)
