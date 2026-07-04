{- |
Module      : SixFour.Spec.MixSKI
Description : WHAT SKI SAYS ABOUT MIXING THE VIEWS — the correction that grounds the cube-brush change in the landed combinator algebra ("SixFour.Spec.CombinatorExactSequence": K = the collapse surjection, I = the reversible splitting, S = the section, and THE GENE LIVES ON S). The incoming data is three bin streams — 16×16 coarse, 32×32 mid, 64×64 fine — which are K-images of ONE signal (the sums carrier; toggling views = walking the K-chain). The user paints voxels IN a view, picking REAL measured bins; the mixed 64³ is a per-region CHOICE OF SECTION over the K-chain — and since K and I are canonical (summation and reversibility leave zero degrees of freedom), the ONLY choice in the whole pipeline is the mix. Teaching the network to produce custom 64³ GIFs is therefore, verbatim in the algebra: TRAINING S. The user's paint is a gene specification; the network learns the user's section.

The three exact statements ('washQ' = S₀∘K, collapse-then-replicate with the
zero-detail section, over ℚ so the structure is exact and rounding stays a
single final realization step):

  * 'lawSectionFactorsThroughChain': the depth-d pull IS the (2−d)-fold wash,
    and washes COMPOSE along the chain — washQ 4 ∘ washQ 2 = washQ 4 = the
    coarse pull. The mix never leaves the K-chain; every mixed region is a
    composite of canonical maps applied a chosen number of times. K∘S = id is
    what makes each view's picks FAITHFUL: what you picked in the 16-view is
    exactly what the 16-view of the output shows.
  * 'lawMixesShareCoarseViews': pooling ANY mixed render back to the coarse
    view recovers the coarse view of the TRUTH — all 3^8 mixes are
    K-INDISTINGUISHABLE. The user's mixing moves detail only; the coarse
    marginals are invariant. (This is why mixing is safe: no mix can lie to
    the coarse view.)
  * 'lawMixesAreDistinguishable': on a witness volume, distinct fields give
    distinct renders IN EVERY REGION (all three depths pairwise differ) — the
    section space genuinely carries 3^8 distinguishable outputs. Combined
    with the previous law: the mix is exactly the fiber of K — pure gene, no
    marginal content. S carries all the freedom; K certifies it carries
    nothing else.

CORRECTION RECORDED (vs the first CubeBrush framing): v1 mixes ship REAL bins
at each depth (the pull of measured data), not network invention — the
network's learnable object is the FIELD (the section = the gene), trained on
the user's picks; invention inside grants remains the W1-gated upgrade path.
The CubeBrush stroke algebra (semilattice, finest-wins, full bandwidth) is
unchanged — a pick in view r IS a depth-r cube; only the UI reading (toggle
views, paint in the current view at its own granularity) and the network's
target (the mix, not the content) are corrected. See docs/CUBE-BRUSH-PLAN.md
amendment.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.MixSKI
  ( -- * The wash: S₀ ∘ K over exact rationals
    VQ
  , liftQ
  , washQ
    -- * Laws
  , lawSectionFactorsThroughChain
  , lawMixesShareCoarseViews
  , lawMixesAreDistinguishable
  ) where

import Data.Ratio ((%))

import SixFour.Spec.PullField
  ( Volume, volumeFromList, Field, renderPull, side )
import SixFour.Spec.FidelityLadder (renderPullQ)

-- | A rational-valued volume (exact means compose; bytes round once at the end).
type VQ = (Int, Int, Int) -> Rational

-- | Lift an integer volume to ℚ.
liftQ :: Volume -> VQ
liftQ v = fromInteger . v

-- | One wash at block side b: collapse to the b-block mean and replicate back
-- — the composite S₀ ∘ K with the zero-detail section, exact over ℚ.
washQ :: Int -> VQ -> VQ
washQ b v (x, y, t) =
  let x0 = (x `div` b) * b
      y0 = (y `div` b) * b
      t0 = (t `div` b) * b
      s  = sum [ v (x0 + i, y0 + j, t0 + k)
               | i <- [0 .. b - 1], j <- [0 .. b - 1], k <- [0 .. b - 1] ]
  in s * (1 % fromIntegral (b * b * b))

allVoxels :: [(Int, Int, Int)]
allVoxels = [ (x, y, t) | t <- [0 .. side - 1], y <- [0 .. side - 1], x <- [0 .. side - 1] ]

-- | LAW (the mix never leaves the K-chain): the depth-1 pull is ONE wash, the
-- depth-0 pull is the composed chain washQ 4 ∘ washQ 2 — and composing equals
-- washing directly at 4 (means of means are means, exactly, over ℚ). Every
-- mixed region is canonical maps applied a chosen number of times; the only
-- choice is HOW MANY — the section.
lawSectionFactorsThroughChain :: [Integer] -> Bool
lawSectionFactorsThroughChain xs =
  and [ washQ 2 vq p == renderPullQ (const 1) v p | p <- allVoxels ]
    && and [ washQ 4 (washQ 2 vq) p == washQ 4 vq p | p <- allVoxels ]
    && and [ washQ 4 vq p == renderPullQ (const 0) v p | p <- allVoxels ]
  where
    v = volumeFromList xs
    vq = liftQ v

-- | LAW (all mixes are K-indistinguishable): pooling ANY mixed render back to
-- the coarse view recovers the coarse view of the truth — the user's mixing
-- moves detail only; the coarse marginals are invariant. No mix can lie to
-- the 16-view.
lawMixesShareCoarseViews :: [Int] -> [Integer] -> Bool
lawMixesShareCoarseViews ds xs =
  and [ washQ 4 mixed p == washQ 4 (liftQ v) p | p <- allVoxels ]
  where
    fld :: Field
    fld r = max 0 (min 2 (take 8 (ds ++ repeat 0) !! max 0 (min 7 r)))
    v = volumeFromList xs
    mixed = renderPullQ fld v

-- | LAW (the section carries real freedom): on the witness volume, the three
-- depth renders differ pairwise INSIDE EVERY REGION — so distinct fields give
-- distinct renders (field ↦ render is injective on the witness), and the mix
-- space genuinely carries 3^8 = 6561 distinguishable outputs. With the
-- previous law: the mix is exactly the K-fiber — pure gene, no marginal
-- content.
lawMixesAreDistinguishable :: Bool
lawMixesAreDistinguishable =
  and [ differsInRegion r d d' | r <- [0 .. 7], d <- [0 .. 2], d' <- [d + 1 .. 2] ]
  where
    v = volumeFromList [ toInteger ((x + 2 * y + 5 * t) `mod` 97)
                       | t <- [0 .. side - 1], y <- [0 .. side - 1], x <- [0 .. side - 1] ]
    regionVoxels r =
      let rx = r `mod` 2; ry = (r `div` 2) `mod` 2; rt = r `div` 4
      in [ (rx * 4 + i, ry * 4 + j, rt * 4 + k) | i <- [0 .. 3], j <- [0 .. 3], k <- [0 .. 3] ]
    differsInRegion r d d' =
      any (\p -> renderPull (const d) v p /= renderPull (const d') v p) (regionVoxels r)
