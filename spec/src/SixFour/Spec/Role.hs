{- |
Module      : SixFour.Spec.Role
Description : The specialist↔generalist axis as a MEASURABLE metric — @effectiveGenomeDim@ = the participation ratio @(Σλ)²/Σλ²@ of a creator's genes in genome space (1.0 = pure specialist, all genes on one axis; higher = generalist, genes span many independent directions). The METRIC is defined and proven NOW (no users); only per-user values and the named cut-points await a real corpus.

This is the ROLE axis of the swap economy (rank = "SixFour.Spec.Trade" demand + "SixFour.Spec.Lineage"
influence; affiliation = "SixFour.Spec.Affiliation"; role is orthogonal to both). It is the SAME
participation-ratio idea as "SixFour.Spec.Diversity" @effectiveDim@ (3-D OKLab colour spread),
generalised from 3 dimensions to the N-D genome space — and computed WITHOUT eigendecomposition or an
N×N covariance, via the pairwise-Gram identity @tr(Σ²) = (1/n²) Σ_{a,b} ⟨cₐ,c_b⟩²@ on the centred
genes (cheap when a creator has few genes in a high-D space).

  * 'effectiveGenomeDim' — the spectrum itself: the effective number of genome dimensions a creator's
    portfolio explores. Degenerate (empty / singleton / all-identical) ⇒ 1.0 (max specialist), exactly
    as @demand@ is 0 before any trade. Bounded in @[1, n]@ ('lawEffectiveDimAtLeastOne',
    'lawEffectiveDimBoundedByCount'), permutation- and translation-invariant (proven in
    @Properties.Role@).
  * 'moreSpecialistThan' \/ 'moreGeneralistThan' — the comparison the (uncalibrated) spectrum supports
    today: strictly relative, no named bands yet.

HONEST (the pre-users boundary): the metric is earned and validated on synthetic extremes now —
colinear genes score exactly 1 ('lawColinearIsSpecialist'), genes on k orthogonal axes score exactly k
('lawAxisPairsGiveDimK'). What awaits users is CALIBRATION: the thresholds that carve this continuum
into "specialist" / "generalist" roles need a measured population — the metric cannot invent them.

GHC-boot-only. Laws QuickCheck'd in @Properties.Role@.
-}
-- COMPARTMENT: SWIFT-APP-SOCIAL | tag:DisplaySide
module SixFour.Spec.Role
  ( -- * Genome portfolios
    GeneVector
  , Portfolio
    -- * The specialist↔generalist spectrum
  , centroid
  , effectiveGenomeDim
  , moreSpecialistThan
  , moreGeneralistThan
    -- * Laws (QuickCheck'd in @Properties.Role@)
  , lawEffectiveDimAtLeastOne
  , lawEffectiveDimBoundedByCount
  , lawColinearIsSpecialist
  , lawAxisPairsGiveDimK
  ) where

-- | A gene as a point in genome space (e.g. the 384-DOF σ-pair genome). Stand-in vector; wiring to
-- the concrete genome is a later connection, exactly as 'SixFour.Spec.Trade.GeneId' abstracts the hash.
type GeneVector = [Double]

-- | A creator's published genes — the point cloud whose SPREAD is their role.
type Portfolio = [GeneVector]

-- | Numerical floor for "no spread" (all genes coincide).
eps :: Double
eps = 1e-12

-- | Dot product of two equal-length vectors.
dot :: GeneVector -> GeneVector -> Double
dot a b = sum (zipWith (*) a b)

-- | The centroid (mean gene) of a non-empty portfolio.
centroid :: Portfolio -> GeneVector
centroid p =
  let n = fromIntegral (length p)
      d = length (head p)
  in map (/ n) (foldr (zipWith (+)) (replicate d 0) p)

-- | The specialist↔generalist spectrum: the effective number of genome dimensions the portfolio
-- explores, @(Σλ)²/Σλ²@ of the gene covariance. @1.0@ = pure specialist (genes colinear), rising to
-- the portfolio's rank for a generalist. Degenerate portfolios (fewer than two genes, or all
-- identical) return @1.0@. Computed via the pairwise Gram of centred genes — no eigendecomposition.
effectiveGenomeDim :: Portfolio -> Double
effectiveGenomeDim p
  | length p < 2 = 1
  | otherwise =
      let mu = centroid p
          cs = map (\g -> zipWith (-) g mu) p          -- centred genes
          n  = fromIntegral (length p)
          trS  = sum [ dot c c | c <- cs ] / n          -- tr Σ  = Σλ
          trS2 = sum [ let g = dot a b in g * g         -- tr Σ² = Σλ²
                     | a <- cs, b <- cs ] / (n * n)
      in if trS2 <= eps then 1 else (trS * trS) / trS2

-- | Is @a@ more of a specialist than @b@ (narrower genome spread)? Strictly relative — the spectrum
-- has no absolute "specialist" band until it is calibrated on a real population.
moreSpecialistThan :: Portfolio -> Portfolio -> Bool
moreSpecialistThan a b = effectiveGenomeDim a < effectiveGenomeDim b

-- | Is @a@ more of a generalist than @b@ (wider genome spread)?
moreGeneralistThan :: Portfolio -> Portfolio -> Bool
moreGeneralistThan a b = effectiveGenomeDim a > effectiveGenomeDim b

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws (QuickCheck'd in @Properties.Role@).
-- ─────────────────────────────────────────────────────────────────────────────

-- | The spectrum is at least 1 (a portfolio always occupies at least one effective dimension).
lawEffectiveDimAtLeastOne :: Portfolio -> Bool
lawEffectiveDimAtLeastOne p = effectiveGenomeDim p >= 1 - 1e-9

-- | The spectrum never exceeds the number of genes (you cannot span more independent directions than
-- you have data points).
lawEffectiveDimBoundedByCount :: Portfolio -> Bool
lawEffectiveDimBoundedByCount p =
  effectiveGenomeDim p <= fromIntegral (max 1 (length p)) + 1e-9

-- | SYNTHETIC EXTREME (max specialist): genes that are all scalar multiples of one direction score
-- exactly 1 — colinear genes explore a single genome dimension. Provable with no users.
lawColinearIsSpecialist :: GeneVector -> [Double] -> Bool
lawColinearIsSpecialist v ts =
  let v' = if all (== 0) v then 1 : drop 1 v else v      -- ensure a non-zero direction
      p  = [ map (* t) v' | t <- ts ]
  in length p < 2 || abs (effectiveGenomeDim p - 1) < 1e-6

-- | SYNTHETIC EXTREME (generalist of degree k): genes at @±eᵢ@ on k orthogonal axes score exactly k —
-- the portfolio spreads isotropically over k genome dimensions. Provable with no users.
lawAxisPairsGiveDimK :: Int -> Bool
lawAxisPairsGiveDimK k
  | k < 1     = True
  | otherwise =
      let axis i = [ if j == i then 1 else 0 | j <- [1 .. k] ] :: GeneVector
          p = concat [ [axis i, map negate (axis i)] | i <- [1 .. k] ]
      in abs (effectiveGenomeDim p - fromIntegral k) < 1e-6
