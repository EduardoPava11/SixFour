{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Properties.STBN3D (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector.Unboxed as U
import           Data.Proxy          (Proxy(..))
import           GHC.TypeLits        (KnownNat, natVal)

import SixFour.Spec.STBN3D (Mask3D(..), generateSTBN3D, horizontalBlueScore)

-- The two STBN3D-specific tests preserved from the retired Properties.Hybrid:
-- the mask has the expected byte count, and its horizontal spectrum is bluer
-- than white noise (positive horizontalBlueScore). These guard the production
-- blue-noise mask that ships as Resources/stbn3d-8.bin and is loaded by
-- PaletteGenerator.swift via STBN3DMaskLoader.

tests :: TestTree
tests = testGroup "STBN3D (3D spatio-temporal blue-noise mask — load-bearing for blue-noise dither)"

  [ testProperty "generateSTBN3D produces nt·nh·nw bytes (size contract)" $
      once $
        let Mask3D v = generateSTBN3D @4 @4 @4
        in U.length v == 64

  , testProperty "generateSTBN3D produces 8³ = 512 bytes at the production tile size" $
      once $
        let Mask3D v = generateSTBN3D @8 @8 @8
        in U.length v == 512

  , testProperty "8³ production mask has non-negative horizontalBlueScore (spectrum bluer than white)" $
      once $
        horizontalBlueScore (generateSTBN3D @8 @8 @8) >= 0

  , testProperty "4³ test mask has non-negative horizontalBlueScore" $
      once $
        horizontalBlueScore (generateSTBN3D @4 @4 @4) >= 0
  ]
