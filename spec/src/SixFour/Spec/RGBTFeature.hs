{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : SixFour.Spec.RGBTFeature
Description : The 1b feature layer — the entropy-weighted temporal coherence substrate over the RGBT buffer.

Phase 2 of the RGBT‑4D hardening (@docs/SIXFOUR-RGBT4D-BUFFER-HARDENING-WORKFLOW.md@): the
__universal feature layer__ (1b) every tier reads. Over the stride‑1 circular buffer
('SixFour.Spec.GroupRGBT.circularWindows'), each frame is re-expressed as a __weighted temporal
blend__ of its 4‑frame R/G/B/T window — a per-pixel convex combination whose lane weights are the
entropy-derived 'SixFour.Spec.Entropy.RGBTWeights' (2b: the semantic lanes are weighted by how much
information each axis carries). The result is a temporally-coherent frame /per frame/ (64→64): the
per-frame structure — and the "every pixel filled" completeness invariant — survive untouched
('lawFeaturePreservesCompleteness'), because a convex blend of in-gamut pixels is in-gamut.

This is the lossy coherence VIEW; the lossless resolution ladder is the SPATIAL bijection in
"SixFour.Spec.RGBTLift" (@2×2↔1@) plus the disjoint temporal lift (Phase 3). Two distinct roles:
the buffer gives every tier a coherent substrate, the lift gives the ladder its losslessness.

Properties that pin it:

  * 'lawFeaturePerFrameCountUnchanged' — 64 frames in, 64 out (1b keeps per-frame).
  * 'lawFeaturePreservesCompleteness'  — every feature pixel lies within its window's range
    (no invented colour, no holes/transparency) — the captured completeness is preserved.
  * 'lawFeatureRWeightIsIdentity'      — all weight on the R lane (the frame's own position) ⇒ the
    feature is the identity, so the weights genuinely drive it and the original is recoverable.
  * 'lawFeatureGaugeConsistent'        — rotation-equivariant, so canonicalising the loop phase
    ("SixFour.Spec.CanonicalPhase") canonicalises the feature layer (the @C_n@ gauge is respected).
-}
-- COMPARTMENT: METAL-GPU | tag:none | STRADDLER
module SixFour.Spec.RGBTFeature
  ( -- * The feature layer
    rgbtFeature
  , featureFrame
    -- * Laws (QuickCheck'd in Properties.RGBTFeature)
  , lawFeaturePerFrameCountUnchanged
  , lawFeaturePreservesCompleteness
  , lawFeatureRWeightIsIdentity
  , lawFeatureGaugeConsistent
  ) where

import SixFour.Spec.Collapse       (PxQ16)
import SixFour.Spec.Entropy        (RGBTWeights(..))
import SixFour.Spec.GroupRGBT      (circularWindows)
import SixFour.Spec.CanonicalPhase (rotateBy)

-- | Integer lane weights (Q10) from the entropy 'RGBTWeights', clamped non-negative — the
-- four lane weights @(R, G, B, T)@ for the temporal blend.
laneWeights :: RGBTWeights -> (Int, Int, Int, Int)
laneWeights (RGBTWeights l a b t) = (q l, q a, q b, q t)
  where q w = max 0 (round (w * 1024))

-- | Weighted floor-average of the four window pixels at one position (per OKLab channel).
-- A convex combination, so the result stays within the four inputs' per-channel range. Zero
-- total weight falls back to the R (lane-0) pixel.
blend4 :: (Int, Int, Int, Int) -> PxQ16 -> PxQ16 -> PxQ16 -> PxQ16 -> PxQ16
blend4 (w0, w1, w2, w3) (l0,a0,b0) (l1,a1,b1) (l2,a2,b2) (l3,a3,b3) =
  let s = w0 + w1 + w2 + w3
      avg x0 x1 x2 x3 = if s <= 0 then x0 else (w0*x0 + w1*x1 + w2*x2 + w3*x3) `div` s
  in (avg l0 l1 l2 l3, avg a0 a1 a2 a3, avg b0 b1 b2 b3)

-- | Blend one 4-frame window into a single feature frame, per pixel position. Frames are
-- truncated to the shortest in the window (a no-op for the equal-length capture).
featureFrame :: (Int, Int, Int, Int) -> [[PxQ16]] -> [PxQ16]
featureFrame ws (f0 : f1 : f2 : f3 : _) =
  let p = minimum (map length [f0, f1, f2, f3])
  in [ blend4 ws (f0 !! i) (f1 !! i) (f2 !! i) (f3 !! i) | i <- [0 .. p - 1] ]
featureFrame _ _ = []

-- | The 1b feature layer: over the stride‑1 circular RGBT buffer, blend each frame's 4‑frame
-- window into one temporally-coherent feature frame, lanes weighted by 'RGBTWeights'. Maps @T@
-- frames to @T@ feature frames.
rgbtFeature :: RGBTWeights -> [[PxQ16]] -> [[PxQ16]]
rgbtFeature rw frames =
  let ws = laneWeights rw
  in [ featureFrame ws win | win <- circularWindows 4 frames ]

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.RGBTFeature)
-- ============================================================================

-- | The feature layer keeps the per-frame count: @|rgbtFeature rw fs| = |fs|@ (one coherent
-- feature frame per input frame — 1b preserves per-frame).
lawFeaturePerFrameCountUnchanged :: RGBTWeights -> [[PxQ16]] -> Bool
lawFeaturePerFrameCountUnchanged rw fs = length (rgbtFeature rw fs) == length fs

-- | Completeness / opacity survives: every feature pixel channel lies within the per-channel
-- range of the four source pixels at that position — a convex blend invents nothing outside the
-- captured gamut and leaves no hole. (Assumes equal-length frames, as the capture guarantees.)
lawFeaturePreservesCompleteness :: RGBTWeights -> [[PxQ16]] -> Bool
lawFeaturePreservesCompleteness rw fs =
  and [ okFrame win ff | (win, ff) <- zip (circularWindows 4 fs) (rgbtFeature rw fs) ]
  where
    okFrame (f0 : f1 : f2 : f3 : _) ff =
      and [ inRange [f0 !! i, f1 !! i, f2 !! i, f3 !! i] (ff !! i)
          | i <- [0 .. length ff - 1]
          , all ((> i) . length) [f0, f1, f2, f3] ]
    okFrame _ _ = True
    inRange srcs (fl, fa, fb) =
      within (map (\(l,_,_) -> l) srcs) fl
      && within (map (\(_,a,_) -> a) srcs) fa
      && within (map (\(_,_,b) -> b) srcs) fb
    within xs v = null xs || (v >= minimum xs && v <= maximum xs)

-- | All weight on the R lane (the frame's own position 0) ⇒ the feature is the identity:
-- @rgbtFeature (RGBTWeights 1 0 0 0) fs ≡ fs@ (EXACT). So the weights genuinely control the
-- blend and the source frames are exactly recoverable as a special case.
lawFeatureRWeightIsIdentity :: [[PxQ16]] -> Bool
lawFeatureRWeightIsIdentity fs = rgbtFeature (RGBTWeights 1 0 0 0) fs == fs

-- | The feature layer is rotation-equivariant — @rgbtFeature rw (rotateBy k fs) ≡ rotateBy k
-- (rgbtFeature rw fs)@ — so it respects the loop's @C_n@ gauge: canonicalising the frame phase
-- ("SixFour.Spec.CanonicalPhase") canonicalises the feature layer too.
lawFeatureGaugeConsistent :: RGBTWeights -> Int -> [[PxQ16]] -> Bool
lawFeatureGaugeConsistent rw k fs =
  rgbtFeature rw (rotateBy k fs) == rotateBy k (rgbtFeature rw fs)
