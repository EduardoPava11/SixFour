{- |
Module      : V2Hylo
Description : EXPLORATION - NOT WIRED. The colour-ring-INVARIANT recursion-scheme spine,
              ported from OneSix.Spec.Hylo into SixFour's V2 area.

  WHY THIS IS HERE (the V2 pivot): the two-lens exploration (workflow wpbym1x7n) established
  that the GIF89a codec's load-bearing computational core is colour-ring-INVARIANT — it is the
  reversible integer Haar lift + the recursion scheme (ana/cata/hylo), neither of which sees
  whether colour lives in OKLab/Z[i] (V1) or RGB/Z[w] (V2). phi6's ring symmetry is V1-ONLY and
  dies under Z[w] (square Z[i] is not isometric to hexagonal A2). So for V2 we keep THIS spine
  and drop phi6.

  ana  = UNZIP   (unfold a seed into a structure / spread the scale tower)
  cata = ZIP     (fold a structure back into a value / collapse the rungs)
  hylo = cata . ana, DEFORESTED (the intermediate list is never built) — the fused encode->decode.

  This is point-free combinatory logic: ana/cata take only functions, the `go` recursion is the
  embedded fixed point, and `cata . ana` is composition (the B combinator). It is the substrate the
  GifSki.hs SKI reading rides on. BASE-ONLY, NOT in any cabal/Map/gate. Check:  runghc V2Hylo.hs
-}
module V2Hylo where

-- | The base functor of a list: the shape both @ana@ and @cata@ work over.
data ListF a r = Nil | Cons a r

-- | Anamorphism — UNZIP. Unfold a seed into a structure.
ana :: (s -> ListF a s) -> s -> [a]
ana coalg = go
  where go s = case coalg s of
                 Nil       -> []
                 Cons a s' -> a : go s'

-- | Catamorphism — ZIP. Fold a structure into a value.
cata :: (ListF a r -> r) -> [a] -> r
cata alg = go
  where go []       = alg Nil
        go (x : xs) = alg (Cons x (go xs))

-- | Hylomorphism — the fused encode->decode, deforested: the list is never built.
hylo :: (ListF a r -> r) -> (s -> ListF a s) -> s -> r
hylo alg coalg = go
  where go s = case coalg s of
                 Nil       -> alg Nil
                 Cons a s' -> alg (Cons a (go s'))

-- | The coalgebra: unfold rung voxels @2^(16+k)@ from scale index @k@, halting after R4 (the 5-rung spine).
rungCoalg :: Int -> ListF Int Int
rungCoalg k
  | k > 4     = Nil
  | otherwise = Cons (2 ^ (16 + k)) (k + 1)

-- | The algebra: sum the rung ranks (the byte-accounting total).
sumAlg :: ListF Int Int -> Int
sumAlg Nil          = 0
sumAlg (Cons x acc) = x + acc

anaRungs :: Int -> [Int]
anaRungs = ana rungCoalg

cataSum :: [Int] -> Int
cataSum = cata sumAlg

hyloVoxels :: Int -> Int
hyloVoxels = hylo sumAlg rungCoalg

-- | UNZIP a flat shell list into adjacent @(lo,hi)@ pairs (drops a trailing odd element).
pairUp :: [a] -> [(a, a)]
pairUp (x : y : rest) = (x, y) : pairUp rest
pairUp _              = []

-- | ZIP pairs back into a flat list.
unPair :: [(a, a)] -> [a]
unPair = concatMap (\(a, b) -> [a, b])

-- * Laws (the colour-ring-invariant spine — true for V1 and V2 alike)

-- | The hylomorphism IS the fused fold-of-unfold, on every seed (deforestation is sound).
lawHyloFusion :: Bool
lawHyloFusion = all (\s -> hyloVoxels s == cataSum (anaRungs s)) [0 .. 6]

-- | Byte accounting — the graded rank total is the closed form @Σ_{k=0}^{4} 2^(16+k) = 2^21 − 2^16@.
lawPyramidClosedForm :: Bool
lawPyramidClosedForm = hyloVoxels 0 == 2 ^ (21 :: Int) - 2 ^ (16 :: Int)

-- | zip ∘ unzip conserves the (even-length) data — the pairing loses nothing.
lawZipUnzipConserves :: [Int] -> Bool
lawZipUnzipConserves xs = unPair (pairUp ys) == ys
  where ys = take (2 * (length xs `div` 2)) xs

main :: IO ()
main = do
  putStrLn "V2Hylo.hs  -- EXPLORATION (NOT WIRED): the colour-ring-invariant recursion spine (ported from OneSix.Hylo)"
  putStrLn "------------------------------------------------------------------------"
  let checks = [ ("lawHyloFusion        (hylo = cata . ana, deforested)", lawHyloFusion)
               , ("lawPyramidClosedForm (Sum 2^(16+k) = 2^21 - 2^16)",    lawPyramidClosedForm)
               , ("lawZipUnzipConserves (zip . unzip = id on even data)", all lawZipUnzipConserves [[], [1], [1,2], [1,2,3], [9,8,7,6,5]])
               ]
  mapM_ (\(n, ok) -> putStrLn ((if ok then "PASS  " else "FAIL  ") ++ n)) checks
  let passed = length (filter snd checks)
  putStrLn "------------------------------------------------------------------------"
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show (length checks) ++ " laws PASS" ++ (if passed == length checks then "  (all green)" else ""))
  putStrLn ""
  putStrLn ("hyloVoxels 0 = " ++ show (hyloVoxels 0) ++ "  (= 2^21 - 2^16 = " ++ show (2 ^ (21 :: Int) - 2 ^ (16 :: Int) :: Int) ++ ")")
  putStrLn "This spine is IDENTICAL for V1 (OKLab) and V2 (RGB): ana/cata/hylo never see the colour ring."
