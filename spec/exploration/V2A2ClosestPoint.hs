{- |
Module      : V2A2ClosestPoint
Description : EXPLORATION (NOT WIRED, base-only, runghc). PROOFS for the true A2 closest-point
              onto the index-3 sublattice Lambda. The closest-point itself (closestLambda,
              metricCost, inLambda) now lives in V2TrainingLattice as the WIRED training-target
              snapper (trainingTarget = closestLambda); this module proves it is the genuine
              nearest Lambda point and strictly beats the old luma-only snapToLambda.

  Check:  runghc V2A2ClosestPoint.hs

  THE GAP (owner directive 2026-06-29): V2TrainingLattice.snapToLambda only moves LUMA to enter
  the congruence class Lambda = {(l,ca,cb) : l == ca+cb (mod 3)}. That is NOT the nearest lattice
  point under the training metric
        metricCost (l0,c0) (l1,c1) = (l1 - l0)^2 + N(c1 - c0)     -- squared-Euclidean, == trainLoss
  (the very geometry of V2TrainingLattice.trainLoss). closestLambda is the genuine closest point.

  WHAT IS REAL: the metric, the candidate moves and the argmin are honest. The global minimum cost
  is provably <= 1 (a single luma +-1 step always re-enters Lambda when the residual /= 0), and the
  candidate set enumerates every cost-<=1 move, so the argmin is the GLOBAL minimum (cross-checked
  by a radius-3 brute force).

  HONEST BOUNDARY: under this metric a unit luma step and a minimal unit chroma shift BOTH cost 1,
  so a chroma move never costs strictly LESS than the best luma step (they tie). closestLambda is
  strictly cheaper than snapToLambda only on snap's SUBOPTIMAL down-by-2 move (cost 1 < 4 squared).

  Reuses V2TrainingLattice. Base-only, runghc-checkable, NOT in any cabal file, Map, or gate.
-}
module V2A2ClosestPoint where

import V2TrainingLattice
  ( Eisen(..)
  , enorm
  , esub
  , emul
  , luma
  , chroma
  , snapToLambda
  , Pt
  , metricCost
  , inLambda
  , closestLambda
  )

-- | snapToLambda as a point-to-point move, for cost comparison (it only shifts luma).
snapPt :: Pt -> Pt
snapPt (l, c) = snapToLambda l c

-- | A spread of training targets, including all three residue classes r in {0,1,2} and both chroma
--   signs (so the chroma-shift branch is genuinely exercised, not just luma).
sampleTargets :: [Pt]
sampleTargets = [ (l, Eisen a b) | l <- [-3 .. 6], a <- [-3 .. 3], b <- [-3 .. 3] ]

-- ===========================================================================
-- Laws
-- ===========================================================================

-- | The result ALWAYS lies in Lambda (inverts to integer sRGB). TEETH: the closest point is a
--   genuine selection, not "everything is already in Lambda" -- there exist sampled targets whose
--   own identity is NOT in Lambda, yet the result is.
lawClosestIsInLambda :: Bool
lawClosestIsInLambda =
     all (inLambda . closestLambda) sampleTargets
  && any (\t -> not (inLambda t)) sampleTargets        -- tooth: off-Lambda targets exist
  && not (inLambda (2, Eisen 0 0))                     -- tooth witness: r = 2 is off Lambda ...
  && inLambda (closestLambda (2, Eisen 0 0))           -- ... but its closest point is on Lambda

-- | A point already in Lambda is returned UNCHANGED (cost-0 identity wins). TEETH: closestLambda
--   is NOT the identity function -- there exist off-Lambda targets whose result differs from input.
lawClosestIdempotent :: Bool
lawClosestIdempotent =
     all (\t -> closestLambda t == t) [ t | t <- sampleTargets, inLambda t ]
  && any (\t -> closestLambda t /= t) sampleTargets    -- tooth: it actually moves some targets

-- | closestLambda is NEVER worse than snapToLambda, and is STRICTLY better on some target.
--   TEETH (the whole point): the strict witness must exist. At target (2, Eisen 0 0) the residual
--   is r = 2, so snapToLambda moves luma DOWN by 2 (squared cost 4), while the closest point costs 1
--   (a unit chroma shift OR a single luma step up). We also exhibit the chroma case literally:
--   a chroma move (cost 1) is cheaper than snapToLambda's luma move (cost 4).
lawClosestNoWorseThanSnapLuma :: Bool
lawClosestNoWorseThanSnapLuma =
     all (\t -> metricCost t (closestLambda t) <= metricCost t (snapPt t)) sampleTargets
  && any (\t -> metricCost t (closestLambda t) <  metricCost t (snapPt t)) sampleTargets   -- strict witness
  && metricCost wt (closestLambda wt) == 1
  && metricCost wt (snapPt wt)        == 4              -- squared metric: luma down 2 -> 2^2 = 4
  && inLambda wt_luma && metricCost wt wt_luma == 1     -- a luma step up: cost 1
  && inLambda wt_chr  && metricCost wt wt_chr  == 1     -- a chroma unit shift: cost 1 < 4 (cheaper than snap)
  where
    wt      = (2, Eisen 0 0)          -- r = 2
    wt_luma = (3, Eisen 0 0)          -- luma up 1
    wt_chr  = (2, Eisen 1 1)          -- chroma shift, sum 2 == r, norm 1

-- | closestLambda attains the GLOBAL minimum cost over a brute-forced radius-3 neighbourhood of
--   Lambda points: the achieved cost EQUALS the brute min. TEETH: the neighbourhood genuinely
--   contains higher-cost near-miss Lambda points (max cost > the achieved min), so the law is not
--   vacuously comparing a degenerate singleton against itself.
lawClosestIsMinimal :: Bool
lawClosestIsMinimal =
     all (\t -> metricCost t (closestLambda t) == bruteMin t) sampleTargets
  && any (\t -> bruteMax t > metricCost t (closestLambda t)) sampleTargets   -- tooth: near-misses cost more
  where
    nbhd (l, Eisen ca cb) =
      [ p | l' <- [l - 3 .. l + 3]
          , a  <- [ca - 3 .. ca + 3]
          , b  <- [cb - 3 .. cb + 3]
          , let p = (l', Eisen a b)
          , inLambda p ]
    bruteMin t = minimum [ metricCost t p | p <- nbhd t ]
    bruteMax t = maximum [ metricCost t p | p <- nbhd t ]

-- | MATH BACKBONE: an INDEPENDENT ANT cross-check of the three facts the closest-point construction
--   silently rests on (no closestLambda logic appears here, so this cannot be tautological with the
--   laws above).
--   (a) RAMIFICATION  3 = (1+w)(1-w)^2, prime (1-w) ramified with NORM 3.
--   (b) IDEAL MEMBERSHIP / index-3 congruence: for every integer RGB, luma - ca - cb = 3*b, so it
--       ALWAYS lands in Lambda; exactly ONE of three consecutive luma values is in Lambda (index 3).
--   (c) EUCLIDEAN DIVISION: Z[w] is norm-Euclidean (the remainder norm strictly shrinks).
lawMathBackbone :: Bool
lawMathBackbone =
     enorm wm == 3
  && emul wm wm == Eisen 0 (-3)                                   -- (1-w)^2 = -3w
  && emul uw (emul wm wm) == Eisen 3 0                            -- (1+w)(1-w)^2 = 3
  && enorm uw == 1                                                -- tooth: the cofactor (1+w) really is a unit
  && all (\rgb -> luma rgb - reA (chroma rgb) - imA (chroma rgb) == 3 * blue rgb) rgbs
  && all (\rgb -> inLambda (luma rgb, chroma rgb)) rgbs
  && length [ l | l <- [0, 1, 2], inLambda (l, Eisen 0 0) ] == 1 -- tooth: index exactly 3, not 1
  && and [ euclideanShrinks x y | x <- esample, y <- esample, y /= Eisen 0 0 ]
  where
    wm = Eisen 1 (-1)                    -- 1 - w  (the ramified prime over 3)
    uw = Eisen 1 1                       -- 1 + w  (a unit, the ramification cofactor)
    reA (Eisen a _) = a
    imA (Eisen _ b) = b
    blue (_, _, b)  = b
    rgbs    = [ (r, g, b) | r <- [0 .. 4], g <- [0 .. 4], b <- [0 .. 4] ]
    esample = [ Eisen a b | a <- [-3 .. 3], b <- [-3 .. 3] ]
    conjE (Eisen a b) = Eisen (a - b) (negate b)                 -- complex conjugate in Z[w]
    nearest n d = (2 * n + d) `div` (2 * d)                      -- round n/d to nearest integer (d > 0)
    euclideanShrinks x y =
      let ny = enorm y
          Eisen p q = emul x (conjE y)                           -- x * conj(y); exact quotient = this / ny
          q0a = nearest p ny
          q0b = nearest q ny
      in any (\qq -> enorm (esub x (emul qq y)) < ny)
             [ Eisen (q0a + da) (q0b + db) | da <- [-1 .. 1], db <- [-1 .. 1] ]

-- ===========================================================================
-- Runner
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawClosestIsInLambda          (result inverts to integer sRGB, selection not trivial)", lawClosestIsInLambda)
  , ("lawClosestIdempotent          (on-Lambda fixed, off-Lambda actually moved)",            lawClosestIdempotent)
  , ("lawClosestNoWorseThanSnapLuma (<= snap always, STRICT witness exists)",                 lawClosestNoWorseThanSnapLuma)
  , ("lawClosestIsMinimal           (global min over radius-3 nbhd, near-misses cost more)",  lawClosestIsMinimal)
  , ("lawMathBackbone               (ramification 3=u(1-w)^2, index-3 congruence, Euclidean)", lawMathBackbone)
  ]

main :: IO ()
main = do
  putStrLn "V2A2ClosestPoint.hs  -- EXPLORATION (NOT WIRED): proofs for the true A2 closest-point"
  putStrLn (replicate 72 '-')
  mapM_ (\(n, ok) -> putStrLn (verdict ok ++ "  " ++ n)) laws
  putStrLn (replicate 72 '-')
  let passed = length (filter snd laws)
      total  = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  let wt = (2, Eisen 0 0) :: Pt
  putStrLn ("witness target          = " ++ show wt ++ "   (residual r = 2)")
  putStrLn ("snapToLambda gives      = " ++ show (snapPt wt)
            ++ "   cost " ++ show (metricCost wt (snapPt wt)) ++ " (luma down 2)")
  putStrLn ("closestLambda gives     = " ++ show (closestLambda wt)
            ++ "   cost " ++ show (metricCost wt (closestLambda wt)) ++ " (chroma unit shift)")
  putStrLn ""
  putStrLn "HONEST BOUNDARY: the candidate set is PROVABLY exhaustive for the GLOBAL minimum, not"
  putStrLn "merely local: a single luma +-1 step always re-enters Lambda when r /= 0, so the true"
  putStrLn "min cost is <= 1, and every cost-<=1 move is enumerated (luma +-1, the 6 unit chroma"
  putStrLn "shifts, identity). Under this metric a luma step and a minimal chroma shift BOTH cost 1,"
  putStrLn "so chroma never STRICTLY beats the best luma step (they tie); chroma is strictly cheaper"
  putStrLn "only than snapToLambda's suboptimal down-by-2 move. closestLambda is now WIRED as"
  putStrLn "V2TrainingLattice.trainingTarget; this module proves it is the genuine nearest point."
  where
    verdict True  = "PASS"
    verdict False = "FAIL"
