{- |
Module      : SixFour.Spec.Look
Description : The math-verifiable LOOK contract (MATH.md §9).

A per-user "look" model (to be trained on MLX) maps a 64³ GIF's global palette
to a stylised one. The /aesthetics/ are learned and not verifiable — but the
transform's BEHAVIOUR is, and that behaviour is exactly what makes the shipped
control safely user-modulable. This module hardens that contract:

  * 'LookCode' — a bounded control vector in @[-1,1]^d@. It is
    **control-surface-agnostic**: named perceptual knobs, the model's raw
    latent, or a transformer-on-top all map /into/ this code. We freeze the
    code's algebra; the surface above it can iterate.
  * 'LookTransform' — any pure @LookCode -> Palette -> Palette@. A trained net
    is one inhabitant; 'affineLook' is the reference (non-learned) inhabitant.
  * Four laws every conforming transform must satisfy, **independent of
    weights**: neutral-identity (reset works), gamut-closure (no invalid
    colours), boundedness (a bounded knob has bounded effect), and continuity
    (a small knob move is a small look change). A residual, tanh-bounded,
    clamped architecture makes them hold by construction; the laws verify it.

The laws live here (not "SixFour.Spec.Laws") to stay self-contained.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.Look
  ( LookCode
  , unLookCode
  , mkLookCode
  , neutralLookCode
  , lookDim
  , LookTransform(..)
  , affineLook
  , lookBoundMax
  , lookLipschitz
  , lawLookNeutralIdentity
  , lawLookGamutClosure
  , lawLookBounded
  , lawLookContinuity
  ) where

import qualified Data.Vector as V

import SixFour.Spec.Color   (OKLab(..))
import SixFour.Spec.Palette (Palette(..))

-- | Reference control dimensionality (warmth, contrast, saturation, lift).
-- The analysis put the look manifold at ~5 dims; 4 named axes is the reference.
lookDim :: Int
lookDim = 4

-- | A bounded control vector in @[-1,1]^lookDim@. The neutral code is the
-- origin (the faithful, un-stylised baseline).
newtype LookCode = LookCode
  { unLookCode :: V.Vector Double  -- ^ the raw @[-1,1]^lookDim@ control vector
  }
  deriving (Eq, Show)

-- | Build a code; rejects wrong length or out-of-box values.
mkLookCode :: [Double] -> Maybe LookCode
mkLookCode xs
  | length xs == lookDim && all (\x -> x >= -1 && x <= 1) xs = Just (LookCode (V.fromList xs))
  | otherwise = Nothing

-- | The neutral code: the origin of the box — the faithful, un-stylised baseline.
neutralLookCode :: LookCode
neutralLookCode = LookCode (V.replicate lookDim 0)

-- | A look transform: a pure, palette-size-polymorphic function. A trained
-- model is one inhabitant; 'affineLook' is the reference inhabitant.
newtype LookTransform =
  LookTransform { applyLook :: forall k. LookCode -> Palette k -> Palette k }

-- | Reference (non-learned) inhabitant: a residual, clamped colour-space warp.
-- Neutral code ⇒ identity (each term is 0 / unit-scale at code 0).
affineLook :: LookTransform
affineLook = LookTransform $ \(LookCode v) (Palette ps) ->
  let warmth   = tanh (v V.! 0) * 0.08
      contrast = 1 + 0.5 * tanh (v V.! 1)
      sat      = 1 + 0.5 * tanh (v V.! 2)
      lift     = tanh (v V.! 3) * 0.10
      cl lo hi x = max lo (min hi x)
      warp (OKLab l a b) =
        OKLab (cl 0 1     (0.5 + (l - 0.5) * contrast + lift))
              (cl (-0.4) 0.4 (a * sat + warmth))
              (cl (-0.4) 0.4 (b * sat + warmth))
  in Palette (V.map warp ps)

-- | Generous absolute bound on per-colour displacement over the whole code box.
lookBoundMax :: Double
lookBoundMax = 0.8

-- | Lipschitz constant of the transform w.r.t. the code.
lookLipschitz :: Double
lookLipschitz = 1.5

-- internal: max per-colour OKLab distance between two palettes.
paletteDistMax :: Palette k -> Palette k -> Double
paletteDistMax (Palette a) (Palette b)
  | V.null a  = 0
  | otherwise = V.maximum (V.zipWith d a b)
  where
    d (OKLab l1 a1 b1) (OKLab l2 a2 b2) =
      sqrt ((l1 - l2) ^ (2 :: Int) + (a1 - a2) ^ (2 :: Int) + (b1 - b2) ^ (2 :: Int))

-- | Law (neutral identity): the no-look code returns the palette unchanged
-- (so 'reset' always recovers the faithful baseline).
lawLookNeutralIdentity :: Double -> LookTransform -> Palette k -> Bool
lawLookNeutralIdentity tol lt p = paletteDistMax (applyLook lt neutralLookCode p) p <= tol

-- | Law (gamut closure): the output is always in valid OKLab range.
lawLookGamutClosure :: LookTransform -> LookCode -> Palette k -> Bool
lawLookGamutClosure lt s p =
  let Palette ps = applyLook lt s p
  in V.all (\(OKLab l a b) ->
              l >= -1e-9 && l <= 1 + 1e-9 && abs a <= 0.4 + 1e-9 && abs b <= 0.4 + 1e-9)
           ps

-- | Law (boundedness): a code in the box moves any colour by at most 'lookBoundMax'.
lawLookBounded :: LookTransform -> LookCode -> Palette k -> Bool
lawLookBounded lt s p = paletteDistMax (applyLook lt s p) p <= lookBoundMax + 1e-9

-- | Law (continuity): the transform is Lipschitz in the code — small knob move,
-- small look change. The guarantee that makes a slider feel predictable.
lawLookContinuity :: LookTransform -> LookCode -> LookCode -> Palette k -> Bool
lawLookContinuity lt s s' p =
  let ds = sqrt (V.sum (V.zipWith (\x y -> (x - y) ^ (2 :: Int)) (unLookCode s) (unLookCode s')))
      dp = paletteDistMax (applyLook lt s p) (applyLook lt s' p)
  in dp <= lookLipschitz * ds + 1e-9
