{-# LANGUAGE ScopedTypeVariables #-}
{- |
Module      : SixFour.Spec.ThetaToDelta
Description : The taste vector θ → generator-space nudge δ — closed-form, σ-aware, the n=0 personalization map.

The canonical path's n=0 taste channel (@docs/SIXFOUR-CANONICAL-PATH.md@ §2, step 2):
turn the on-device 770-D Bradley–Terry taste vector θ
('SixFour.Spec.PreferenceUpdate', laid out as @256 leaves × 3 ++ [coverage, beauty]@)
into the generator-space override δ that 'SixFour.Spec.LeafOverride.applySigmaOverride'
/ the Zig @s4_leaf_override@ kernel consumes. δ is the TASTE-ASCENT GRADIENT in
generator space: nudging each generator @gᵢ@ along @δᵢ@ raises the leaf-linear BT
utility @u(palette) = θ_leaves · leaves@.

Because the σ-pair palette is @[g₀, σ(g₀), g₁, σ(g₁), …]@ with @σ(l,a,b) = (l,−a,−b)@,
generator @i@ appears in leaves @2i@ (= @gᵢ@) and @2i+1@ (= @σ(gᵢ)@). The chain rule
gives the closed-form per-generator gradient — and the σ involution's signature
(add @L@, subtract chroma) falls out for free, so the map respects the genome's
symmetry BY CONSTRUCTION:

@
∂u/∂Lᵢ = θ[6i+0] + θ[6i+3]   -- σ preserves L  ⇒ the two leaf weights ADD
∂u/∂aᵢ = θ[6i+1] − θ[6i+4]   -- σ negates a    ⇒ the partner weight SUBTRACTS
∂u/∂bᵢ = θ[6i+2] − θ[6i+5]   -- σ negates b
@

The map is LINEAR in θ. The @[coverage, beauty]@ tail (@θ[768], θ[769]@) is a global
palette functional, not a per-leaf weight, so it carries no per-generator gradient and
is IGNORED here — those preferences are the job of SEARCH (@n>0@), not the @n=0@ tint.
δ is scaled by 'defaultGain' and clamped to @±'deltaMaxQ16'@: the tint can recolour the
generators but can never escape the deterministic floor by an unbounded amount.

Laws (QuickCheck'd in @Properties.ThetaToDelta@; the gradient law is ε, the rest EXACT):

  * the zero taste vector is the zero override ('lawZeroThetaZeroDelta');
  * every δ component stays in @[−deltaMaxQ16, deltaMaxQ16]@ ('lawDeltaBoundedQ16');
  * the raw (unscaled, unclamped) map IS the leaf-linear taste gradient — it matches the
    central finite difference of @θ_leaves · sigmaPairLeaves(generators)@ w.r.t. every
    generator component ('lawRawIsTasteGradient');
  * the raw map is linear in θ ('lawRawLinearInTheta');
  * the @[coverage, beauty]@ tail does not affect δ ('lawCoverageBeautyIgnored').
-}
-- COMPARTMENT: SWIFT-COREAI | tag:CommitSide | STRADDLER
module SixFour.Spec.ThetaToDelta
  ( -- * Constants
    deltaMaxQ16
  , defaultGain
  , generatorsOfTheta
    -- * The map
  , thetaToDeltaRaw
  , thetaToDelta
    -- * Helpers shared with the laws
  , sigmaPairLeaves
  , leafLinearUtility
    -- * Laws (predicates; QuickCheck'd in Properties.ThetaToDelta)
  , lawZeroThetaZeroDelta
  , lawDeltaBoundedQ16
  , lawRawIsTasteGradient
  , lawRawLinearInTheta
  , lawCoverageBeautyIgnored
  ) where

import SixFour.Spec.PairTreeFixed (OKLabI)

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

-- | The per-component clamp on δ (Q16): @±8192 = ±0.125@ OKLab. The tint is bounded
-- so it can recolour but never escape the floor (the canonical path's n=0 invariant).
deltaMaxQ16 :: Int
deltaMaxQ16 = 8192

-- | The default gain mapping the float taste-gradient to Q16 OKLab units. A tunable
-- step size (the laws hold for any gain ≥ 0); pinned here so the port has one constant
-- to mirror. Resolve empirically at n=0 (open question §7.3 of the canonical path).
defaultGain :: Double
defaultGain = 4096.0

-- | The generator count implied by a θ of length @6g + 2@ (= 128 for the 770-D θ).
-- A θ shorter than @6g+2@ truncates; the tail past @6g@ is the ignored [coverage,beauty].
generatorsOfTheta :: [Double] -> Int
generatorsOfTheta theta = max 0 ((length theta - 2) `div` 6)

-- ---------------------------------------------------------------------------
-- The map
-- ---------------------------------------------------------------------------

-- | The raw (unscaled, unclamped) per-generator taste gradient: for each generator
-- @i@, @(θ[6i]+θ[6i+3], θ[6i+1]−θ[6i+4], θ[6i+2]−θ[6i+5])@. Linear in θ; the σ
-- involution's add-L / subtract-chroma signature is structural.
thetaToDeltaRaw :: [Double] -> [(Double, Double, Double)]
thetaToDeltaRaw theta =
  [ ( at (6*i+0) + at (6*i+3)
    , at (6*i+1) - at (6*i+4)
    , at (6*i+2) - at (6*i+5) )
  | i <- [0 .. generatorsOfTheta theta - 1] ]
  where
    v        = theta
    n        = length v
    at k     = if k < n then v !! k else 0

-- | The shipped map: scale the raw gradient by @gain@, round to Q16, clamp to
-- @±deltaMaxQ16@. The 128-entry δ feeds 'SixFour.Spec.LeafOverride.applySigmaOverride'.
thetaToDelta :: Double -> [Double] -> [OKLabI]
thetaToDelta gain theta =
  [ (q l, q a, q b) | (l, a, b) <- thetaToDeltaRaw theta ]
  where
    q x = clampI (round (gain * x))
    clampI = max (negate deltaMaxQ16) . min deltaMaxQ16

-- ---------------------------------------------------------------------------
-- Helpers (shared with the laws)
-- ---------------------------------------------------------------------------

-- | The σ-pair leaves of a generator list (float OKLab): @[g, σ(g)]@ per generator,
-- @σ(l,a,b) = (l,−a,−b)@. The float twin of 'SixFour.Spec.LeafOverride' reconstruction.
sigmaPairLeaves :: [(Double, Double, Double)] -> [(Double, Double, Double)]
sigmaPairLeaves = concatMap (\(l, a, b) -> [(l, a, b), (l, negate a, negate b)])

-- | The leaf-linear part of the BT utility: @θ_leaves · flatten(sigmaPairLeaves gens)@
-- (the @[coverage, beauty]@ tail of θ is dropped by the zipWith truncation). This is the
-- functional 'thetaToDeltaRaw' is the exact gradient of.
leafLinearUtility :: [Double] -> [(Double, Double, Double)] -> Double
leafLinearUtility theta gens =
  sum (zipWith (*) theta (flatten (sigmaPairLeaves gens)))
  where flatten = concatMap (\(l, a, b) -> [l, a, b])

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | The zero taste vector is the zero override: no taste ⇒ no tint.
lawZeroThetaZeroDelta :: Int -> Bool
lawZeroThetaZeroDelta g =
  let g' = max 0 (min 512 g)
  in thetaToDelta defaultGain (replicate (6*g' + 2) 0) == replicate g' (0, 0, 0)

-- | Every δ component stays within @[−deltaMaxQ16, deltaMaxQ16]@, for any θ and gain.
lawDeltaBoundedQ16 :: Double -> [Double] -> Bool
lawDeltaBoundedQ16 gain theta =
  all inBound (thetaToDelta gain theta)
  where inBound (l, a, b) = ok l && ok a && ok b
        ok v = v >= negate deltaMaxQ16 && v <= deltaMaxQ16

-- | The raw map IS the leaf-linear taste gradient: each component matches the central
-- finite difference of 'leafLinearUtility' w.r.t. that generator component (h=1e-5, ε=1e-6).
lawRawIsTasteGradient :: [Double] -> [(Double, Double, Double)] -> Bool
lawRawIsTasteGradient theta gens0 =
  let g     = generatorsOfTheta theta
      gens  = take g (gens0 ++ repeat (0, 0, 0))
      raw   = thetaToDeltaRaw theta
      h     = 1e-5
      bump i (c :: Int) d = [ if j == i then bumpC c d t else t | (j, t) <- zip [0 :: Int ..] gens ]
      bumpC 0 d (l,a,b) = (l+d,a,b)
      bumpC 1 d (l,a,b) = (l,a+d,b)
      bumpC _ d (l,a,b) = (l,a,b+d)
      fd i c = (leafLinearUtility theta (bump i c h)
                - leafLinearUtility theta (bump i c (negate h))) / (2*h)
      close x y = abs (x - y) < 1e-6
  in and [ close rl (fd i 0) && close ra (fd i 1) && close rb (fd i 2)
         | (i, (rl, ra, rb)) <- zip [0 :: Int ..] raw ]

-- | The raw map is linear in θ: @raw(θ₁ ⊕ θ₂) = raw(θ₁) ⊕ raw(θ₂)@ (componentwise,
-- when the two θ have the same generator count). ε-equality, NOT exact: the map is
-- FLOAT-linear, and @(a+c)+(b+d)@ vs @(a+b)+(c+d)@ differ in the last bit (IEEE
-- addition is not associative) — this is the float tier, not the Q16-exact tier.
lawRawLinearInTheta :: [Double] -> [Double] -> Bool
lawRawLinearInTheta t1 t2 =
  generatorsOfTheta t1 /= generatorsOfTheta t2 ||
  and (zipWith closeT (thetaToDeltaRaw (zipWith (+) t1 t2))
                      (zipWith addT (thetaToDeltaRaw t1) (thetaToDeltaRaw t2)))
  where
    addT (a,b,c) (d,e,f) = (a+d, b+e, c+f)
    closeT (a,b,c) (d,e,f) = close a d && close b e && close c f
    close x y = abs (x - y) < 1e-9

-- | The @[coverage, beauty]@ tail (the last two θ entries) does not affect δ: replacing
-- them with anything leaves the override byte-identical.
lawCoverageBeautyIgnored :: [Double] -> Double -> Double -> Bool
lawCoverageBeautyIgnored theta c b =
  generatorsOfTheta theta < 1 ||
  let g    = generatorsOfTheta theta
      core = take (6*g) (theta ++ repeat 0)
  in thetaToDelta defaultGain (core ++ [c, b])
       == thetaToDelta defaultGain (take (length theta) (core ++ repeat 0))
