{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : SixFour.Spec.CubeLadder
Description : The 16³/64³/256³ tiers as REVERSIBLE views over one feature substrate (1b) — lossless within capture, predictive only beyond.

Phase 3 of the RGBT‑4D hardening (@docs/SIXFOUR-RGBT4D-BUFFER-HARDENING-WORKFLOW.md@). The three GIF
products are three rungs of the ×4 spatial cube ladder, all views over the SAME feature substrate
(1b): @tier64@ is the substrate itself (identity), @tier16@ distils it, @tier256@ synthesises from it.

== The spatial ladder is a reversible 2-D Haar pyramid

Each ×2 step is one 2-D-Haar 'liftLevel': tile a @side×side@ grid into 2×2 blocks and lift each via
"SixFour.Spec.RGBTLift" ('liftQuad') into a coarse @R@ plane (the @(side\/2)²@ next tier) plus three
detail planes @(G,B,T)@. 'unliftLevel' inverts it EXACTLY. So 'distill'/'synthesize' over the
__captured__ tiers are mutual inverses ('lawLadderBijective') — 64³↔16³ loses nothing (the detail is
carried, not discarded).

== Loss is isolated to synthesis BEYOND captured resolution

'synthBeyond' upsamples with __zeroed detail__ (no captured high-frequency to draw on) — which is
exactly nearest-neighbour block replication ('lawSynthBeyondIsNearestNeighbour', the deterministic
floor matching 'SixFour.Spec.Export.replicate2D'). It is exact only where the detail was already zero
('lawSynthBeyondExactOnSmooth'); elsewhere it must INVENT detail. That invention — the NN super-res of
"SixFour.Spec.Upscale256" replacing the zero-detail floor — is the one non-invertible step, and it
lives strictly above captured resolution. The ladder itself never loses.

The grids here are scalar (one OKLab channel); the cube applies them per channel, per feature frame.
-}
module SixFour.Spec.CubeLadder
  ( -- * One reversible 2-D-Haar level
    liftLevel
  , unliftLevel
    -- * The captured ladder (lossless)
  , distill
  , synthesize
    -- * Synthesis beyond capture (predictive floor)
  , synthBeyond
    -- * The three tiers as views on one substrate (1b)
  , tier16
  , tier64
  , tier256
    -- * Laws (QuickCheck'd in Properties.CubeLadder)
  , lawLevelReversible
  , lawLadderBijective
  , lawDistillCoarseGamutClosed
  , lawSynthBeyondIsNearestNeighbour
  , lawSynthBeyondExactOnSmooth
  , lawTier64IsIdentity
  ) where

import SixFour.Spec.RGBTLift (liftQuad, unliftQuad)
import SixFour.Spec.Export   (replicate2D)

-- | One 2-D-Haar lift level: a @side×side@ row-major grid (side even) → its @(side\/2)²@ coarse @R@
-- plane plus the @(side\/2)²@ detail triples @(G,B,T)@, lifting each 2×2 block with 'liftQuad'.
liftLevel :: Int -> [Int] -> ([Int], [(Int, Int, Int)])
liftLevel side g =
  let h      = side `div` 2
      at x y = g !! (y * side + x)
      lifted = [ liftQuad ( at (2*bx) (2*by),     at (2*bx+1) (2*by)
                          , at (2*bx) (2*by+1),   at (2*bx+1) (2*by+1) )
               | by <- [0 .. h - 1], bx <- [0 .. h - 1] ]
  in ( [ r | (r,_,_,_) <- lifted ], [ (g',b',t') | (_,g',b',t') <- lifted ] )

-- | Inverse of 'liftLevel': rebuild the @2h×2h@ grid from the coarse @h²@ plane and its @h²@ detail
-- triples (each 2×2 block via 'unliftQuad').
unliftLevel :: Int -> [Int] -> [(Int, Int, Int)] -> [Int]
unliftLevel h coarse details =
  let side  = 2 * h
      quads = zipWith (\r (g',b',t') -> unliftQuad (r, g', b', t')) coarse details
      pick (a,b,c,d) ox oy = if oy == 0 then (if ox == 0 then a else b)
                                        else (if ox == 0 then c else d)
  in [ pick (quads !! ((y `div` 2) * h + (x `div` 2))) (x `mod` 2) (y `mod` 2)
     | y <- [0 .. side - 1], x <- [0 .. side - 1] ]

-- | Distil @levels@ ×2 steps: returns the coarsest plane plus the detail planes (finest first).
distill :: Int -> Int -> [Int] -> ([Int], [[(Int, Int, Int)]])
distill levels side g = go levels side g []
  where go 0 _ cur acc = (cur, acc)
        go n s cur acc = let (c, d) = liftLevel s cur in go (n - 1) (s `div` 2) c (acc ++ [d])

-- | Exact inverse of 'distill': rebuild the full grid from the coarse plane + detail planes.
synthesize :: Int -> ([Int], [[(Int, Int, Int)]]) -> [Int]
synthesize coarseSide (coarse, dets) = go coarse (reverse dets) coarseSide
  where go cur []       _ = cur
        go cur (d : ds) s = go (unliftLevel s cur d) ds (s * 2)

-- | Synthesise UP @levels@ ×2 steps from a coarse grid with __no detail__ (zeroed) — the
-- deterministic floor (nearest-neighbour block replication). What lies above captured resolution
-- before the NN fills in real detail.
synthBeyond :: Int -> Int -> [Int] -> [Int]
synthBeyond coarseSide levels coarse = go coarse coarseSide levels
  where go cur _ 0 = cur
        go cur s n = go (unliftLevel s cur (replicate (s * s) (0, 0, 0))) (s * 2) (n - 1)

-- | The native tier: the feature substrate itself, unresampled.
tier64 :: [Int] -> [Int]
tier64 = id

-- | The distilled tier: ×4 down (2 levels) — the coarse plane, gamut-closed.
tier16 :: Int -> [Int] -> [Int]
tier16 side g = fst (distill 2 side g)

-- | The synthesised tier: ×4 up (2 levels) from the substrate, zero-detail floor (the NN replaces
-- the floor with predicted detail above captured resolution).
tier256 :: Int -> [Int] -> [Int]
tier256 side = synthBeyond side 2

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.CubeLadder)
-- ============================================================================

-- | One level is exactly reversible: @unliftLevel (side\/2) ∘ liftLevel side ≡ id@.
lawLevelReversible :: Int -> [Int] -> Bool
lawLevelReversible side g =
  not (side > 0 && even side && length g == side * side)
    || let (c, d) = liftLevel side g in unliftLevel (side `div` 2) c d == g

-- | THE within-capture law: distil then synthesise is the identity — the captured ladder is a
-- lossless bijection. @synthesize ∘ distill ≡ id@ for any @levels@ that evenly divides @side@.
lawLadderBijective :: Int -> Int -> [Int] -> Bool
lawLadderBijective levels side g =
  not (levels >= 0 && side > 0 && length g == side * side && side `mod` (2 ^ levels) == 0)
    || let (coarse, dets) = distill levels side g
           cs             = side `div` (2 ^ levels)
       in synthesize cs (coarse, dets) == g

-- | The distilled coarse plane is gamut-closed: every coarse value lies within the source grid's
-- range (the @R = LL@ block average is in-block — "SixFour.Spec.RGBTLift.lawCoarseInBlockRange").
lawDistillCoarseGamutClosed :: Int -> [Int] -> Bool
lawDistillCoarseGamutClosed side g =
  not (side > 0 && even side && length g == side * side)
    || let (coarse, _) = liftLevel side g
       in all (\r -> r >= minimum g && r <= maximum g) coarse

-- | Zero-detail synthesis IS nearest-neighbour replication: @synthBeyond h 1 ≡ replicate2D 2 h@ —
-- the deterministic floor coincides with "SixFour.Spec.Export.replicate2D".
lawSynthBeyondIsNearestNeighbour :: Int -> [Int] -> Bool
lawSynthBeyondIsNearestNeighbour h coarse =
  not (h > 0 && length coarse == h * h)
    || synthBeyond h 1 coarse == replicate2D 2 h coarse

-- | Synthesis-beyond is EXACT on a per-2×2-constant (smooth) grid — there the detail was genuinely
-- zero, so the floor loses nothing. Loss only appears where real detail existed (above capture).
lawSynthBeyondExactOnSmooth :: Int -> [Int] -> Bool
lawSynthBeyondExactOnSmooth h coarse =
  not (h > 0 && length coarse == h * h)
    || let g     = replicate2D 2 h coarse        -- a per-2×2-constant grid
           (c,_) = liftLevel (2 * h) g
       in synthBeyond h 1 c == g

-- | The native @tier64@ is the substrate itself (1b: every tier is a view on one feature layer;
-- the 64³ view is the identity).
lawTier64IsIdentity :: [Int] -> Bool
lawTier64IsIdentity g = tier64 g == g
