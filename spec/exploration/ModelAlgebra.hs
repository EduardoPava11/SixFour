{- |
Module      : ModelAlgebra
Description : EXPLORATION (NOT WIRED, base-only, runghc). THE MODEL AS ALGEBRA.
              The pyramid 16^3<->32^3<->64^3<->128^3<->256^3 is already abstracted
              (A7 octants, Z[1/2] reversible refinement, Eisenstein chroma, S256 gauge).
              This module is the functional NOTE for the next step: abstracting the MODEL
              itself into discrete geometry + algebraic number theory. Three compatible
              identities, each with executable law witnesses:

  (T) TROPICAL:  a ReLU net with integer weights IS a tropical rational map over the
      max-plus semiring; argmin-energy inference = evaluation in the semiring.
      [Zhang/Naitzat/Lim ICML 2018 Thm 5.4, arXiv 1805.07091 -- VERIFIED 3-0.
       Rational/dyadic weights: tropical Puiseux maps, Bhatia et al. arXiv 2405.20174.
       Linear regions = Newton-polytope vertices, arXiv 2104.08135 -- VERIFIED 3-0.
       Parameter space semialgebraic in tropical function space; 0/1-loss sublevels are
       subfans of a classification fan, Brandenburg/Loho/Montufar TMLR 2024 -- VERIFIED 3-0.]

  (P) 2-ADIC:    layer transitions are the reduction maps mod 2^k on the ring of integers;
      the layer hierarchy IS the truncated 2-adic tree; energy-based models correspond to
      statistical field theories on the p-regular rooted tree.
      [Zuniga-Galindo arXiv 2402.00094 (J.FourierAnal.Appl.) -- VERIFIED 3-0;
       DBM = p-adic SFT arXiv 2302.03817/2207.13877, p=2 allowed -- VERIFIED 3-0;
       exact D^l(Z_p) discretization of p-adic CNNs arXiv 2107.07980 -- 2-1, medium.
       CAVEAT: one research group; correspondence "not fully developed" (author's words).]

  (D) DECODER:   inference on the A7 detail is closest-vector (bounded-distance) decoding.
      Shallow decoders of A_n need exponential width; Weyl-group FOLDING (reflections =
      sorting) collapses the A_n decision boundary to exactly 2n-1 affine pieces (13 for A7),
      and gradient descent PROVABLY FAILS to discover the folding -- structure must be wired,
      learning acts on the residual after folding.
      [Corlay et al., neural lattice decoders -- extracted, NOT panel-verified yet.]

  Cross-cutting, encoded below:
    * Christol: an ALGEBRAIC 2-adic sequence reduced mod 2^alpha is 2-AUTOMATIC (finite
      automaton on binary digits). The byte-exact deterministic model, where algebraic,
      is a bounded finite-state object. Witness: Catalan mod 2. [classical theorem]
    * Morton: the octree spine question "one 8-adic tree vs (Z_2)^3 product" is a WASH at
      tree level (Morton interleave is a truncation-compatible bijection) but REAL at ring
      level (Morton is not additive). By the SES reading: the choice is where a gene lives.
    * S256 gauge: permuting hidden neurons leaves the tropical normal form invariant
      (weight-space permutation gauge, cf. neural functionals NeurIPS 2023); group
      invariance provably compresses linear-region counts (|G|-sandwich, Thm 14 of 2405.20174).

  NOT encoded here (prose pointers only): Kozyrev's theorem that Haar wavelets on R+ are
  the eigenbasis of the 2-adic Vladimirov operator under digit reversal (pooling = 2-adic
  spectral theory); Mehta-Schwab exact RBM-stack = variational RG on the Ising lattice;
  LWE/Ring-LWE as hardness-of-learning (learner = lattice decoder; noiseless training = LLL,
  an exact integer algorithm; NTT gives O(n log n) exact ring ops for n a power of 2);
  dyadic-rescale int-only inference (HAWQ-V3 / gemmlowp: deployed models already close
  over Z[1/2]).

  REFUTED, do not cite: (a) "rational weights lose no practical generality" gloss on the
  OSCAR paper's Hoffman-constant algorithms; (b) the p-adic CNN contraction spec law
  L(f)*||A||_1 < 1.

  Check:  cd spec/exploration && runghc ModelAlgebra.hs

  Base-only, runghc, NOT in cabal/Map/gate. Nothing shipped is touched.
-}
module ModelAlgebra where

import Data.Bits ((.&.))
import Data.List (foldl', nub, sort, sortBy)
import Data.Ord  (comparing)
import Data.Ratio (denominator)

type Q = Rational

-- ===========================================================================
-- (0) Z[1/2]: the coefficient ring. Deliberately NOT a field (can't divide by 3);
--     kept as Rationals whose denominators are powers of two, checked by law.
-- ===========================================================================

isPow2 :: Integer -> Bool
isPow2 n = n > 0 && n .&. (n - 1) == 0

isDyadic :: Q -> Bool
isDyadic = isPow2 . denominator

-- ===========================================================================
-- (T) TROPICAL: a one-hidden-layer ReLU net with INTEGER weights, and its exact
--     tropical rational form F (-) G built constructively (Zhang/Naitzat/Lim).
--     A tropical polynomial is max_i (c_i + e_i . x): coeffs dyadic, exponents Integer.
-- ===========================================================================

-- | Monomial: (coefficient, integer exponent vector). Tropical product = pointwise sum.
type Mono = (Q, [Integer])
type TropPoly = [Mono]

-- | Hidden neuron: (outer integer weight v, (inner integer weights w, dyadic bias b)).
data Net = Net { hidden :: [(Integer, ([Integer], Q))], outBias :: Q }

-- | The concrete integer-weight net used by every (T) law. 2 inputs, 3 hidden.
demoNet :: Net
demoNet = Net
  { hidden  = [ (2, ([ 1, -2],  1/2))
              , (1, ([ 3,  1], -1  ))
              , (-3,([-1,  1],  0  )) ]
  , outBias = -5/4 }

evalNet :: Net -> [Q] -> Q
evalNet (Net hs c) x = c + sum [ fromInteger v * relu (dotIW w x + b) | (v, (w, b)) <- hs ]
  where relu z = max z 0

dotIW :: [Integer] -> [Q] -> Q
dotIW w x = sum (zipWith (\e xi -> fromInteger e * xi) w x)

evalTrop :: TropPoly -> [Q] -> Q
evalTrop p x = maximum [ c + dotIW e x | (c, e) <- p ]

-- | Tropical product (classical +) distributed over max: cartesian sum of monomials.
tropMul :: TropPoly -> TropPoly -> TropPoly
tropMul p q = [ (c1 + c2, zipWith (+) e1 e2) | (c1, e1) <- p, (c2, e2) <- q ]

tropOne :: Int -> TropPoly
tropOne d = [(0, replicate d 0)]

tropConst :: Int -> Q -> TropPoly
tropConst d c = [(c, replicate d 0)]

normalizeTrop :: TropPoly -> TropPoly
normalizeTrop = sort . nub

-- | Constructive tropicalization: f = F (-) G, each a tropical polynomial.
--   v>0 terms and c+ go to F; v<0 magnitudes and c- go to G.
--   max(v*(w.x+b), 0) is the two-monomial tropical polynomial {(v*b, v*w), (0, 0vec)}.
tropicalize :: Net -> (TropPoly, TropPoly)
tropicalize (Net hs c) = (normalizeTrop f, normalizeTrop g)
  where
    d       = length (fst (snd (head hs)))
    term v (w, b) = [ (fromInteger v * b, map (v *) w), (0, replicate d 0) ]
    f = foldl' tropMul (tropConst d (max c 0))
          [ term v wb        | (v, wb) <- hs, v > 0 ]
    g = foldl' tropMul (tropConst d (max (negate c) 0))
          [ term (negate v) wb | (v, wb) <- hs, v < 0 ]

dyadicGrid :: [[Q]]
dyadicGrid = [ [x, y] | x <- pts, y <- pts ] where pts = map (/ 4) [-8 .. 8]

-- | LAW (VERIFIED THEOREM, Zhang/Naitzat/Lim Thm 5.4 in the integer-weight regime):
--   the net and its tropical rational form agree everywhere. Exact, no floats.
lawNetIsTropicalRationalMap :: Bool
lawNetIsTropicalRationalMap =
  and [ evalNet demoNet x == evalTrop f x - evalTrop g x | x <- dyadicGrid ]
  where (f, g) = tropicalize demoNet

-- | LAW: with integer weights and dyadic biases the model CLOSES over Z[1/2]:
--   dyadic in -> dyadic out. Byte-exactness is the admission ticket to the exact regime.
lawNetClosesOverDyadic :: Bool
lawNetClosesOverDyadic = and [ isDyadic (evalNet demoNet x) | x <- dyadicGrid ]

-- | LAW (weight-space permutation gauge, the S256-palette analogue on the model side):
--   permuting hidden neurons leaves the tropical NORMAL FORM invariant. The gene is the
--   function; the neuron ordering is gauge.
lawHiddenPermutationGauge :: Bool
lawHiddenPermutationGauge =
  tropicalize demoNet == tropicalize (demoNet { hidden = perm (hidden demoNet) })
  where perm (a : b : rest) = b : a : rest
        perm xs             = xs

-- ===========================================================================
-- (T) Newton polytope: linear regions = upper-hull vertices (dim 1, exact).
-- ===========================================================================

-- | 1-D example with a deliberate NON-vertex monomial (1 + 1*x lies under the hull).
newtonExample :: [(Integer, Q)]   -- (exponent e, coefficient c): max_i (c_i + e_i * x)
newtonExample = [(0, 0), (1, 1), (2, 4), (3, 3)]

-- | Upper concave hull of the points (e, c): monotone chain, strictly decreasing slopes.
upperHull :: [(Integer, Q)] -> [(Integer, Q)]
upperHull = foldl' step [] . sortBy (comparing fst)
  where
    step (b : a : rest) p | slope a b <= slope b p = step (a : rest) p
    step acc p = p : acc
    slope (e1, c1) (e2, c2) = (c2 - c1) / (fromInteger (e2 - e1))

-- | A monomial is ATTAINED iff it strictly wins on a nonempty open interval (exact
--   rational feasibility test, no sampling).
attained :: [(Integer, Q)] -> [(Integer, Q)]
attained ms = [ m | m <- ms, feasible m ]
  where
    feasible (e, c) =
      let lowers = [ (cj - c) / fromInteger (e - ej) | (ej, cj) <- ms, ej < e ]
          uppers = [ (cj - c) / fromInteger (e - ej) | (ej, cj) <- ms, ej > e ]
          ok     = null [ () | (ej, cj) <- ms, ej == e, cj > c ]
      in ok && case (lowers, uppers) of
                 ([], _)  -> True
                 (_, [])  -> True
                 (ls, us) -> maximum ls < minimum us

-- | LAW (VERIFIED THEOREM shape, arXiv 1805.07091 / 2104.08135, dim-1 witness):
--   the attained monomials are exactly the Newton-polygon upper-hull vertices;
--   region counting IS vertex counting.
lawRegionsAreNewtonVertices :: Bool
lawRegionsAreNewtonVertices =
  sort (attained newtonExample) == sort (upperHull newtonExample)
  && length (upperHull newtonExample) == 3   -- (1,1) is provably interior

-- ===========================================================================
-- (P) 2-ADIC SPINE: layers are reductions mod 2^k; Morton settles tree-vs-ring.
-- ===========================================================================

-- | LAW (Zuniga-Galindo architecture reading): the reduction maps compose,
--   reduce_j . reduce_k == reduce_j for j <= k. The pyramid's transitivity, on Z_2.
lawSpineReductionsCompose :: Bool
lawSpineReductionsCompose =
  and [ (n `mod` 2 ^ k) `mod` 2 ^ j == n `mod` 2 ^ j
      | n <- [0, 1, 5, 100, 255, 256, 12345 :: Integer]
      , k <- [0 .. 8 :: Int], j <- [0 .. k] ]

-- | Morton interleave on 3-bit coordinates: (Z/2^3)^3 -> Z/8^3.
morton :: (Integer, Integer, Integer) -> Integer
morton (x, y, z) = sum [ bit x i * 2 ^ (3 * i)
                       + bit y i * 2 ^ (3 * i + 1)
                       + bit z i * 2 ^ (3 * i + 2) | i <- [0 .. 2] ]
  where bit n i = (n `div` 2 ^ i) `mod` 2

-- | LAW (tree level): Morton is a bijection (Z/2^k)^3 == Z/8^k that COMMUTES WITH
--   TRUNCATION -- the 8-adic tree and the product of three 2-adic trees are the SAME
--   rooted tree. At tree level the spine question is a wash.
lawMortonIsTreeIso :: Bool
lawMortonIsTreeIso = bijective && truncCompatible
  where
    dom  = [ (x, y, z) | x <- [0 .. 7], y <- [0 .. 7], z <- [0 .. 7] ]
    imgs = map morton dom
    bijective = length (nub imgs) == 512 && all (\v -> 0 <= v && v < 512) imgs
    truncCompatible =
      and [ morton (x `mod` 2 ^ j, y `mod` 2 ^ j, z `mod` 2 ^ j) == morton (x, y, z) `mod` 8 ^ j
          | (x, y, z) <- dom, j <- [0 .. 3 :: Int] ]

-- | LAW (ring level): Morton is NOT additive -- carries propagate differently.
--   So "one 8-adic ring vs (Z_2)^3 product ring" is a REAL algebraic choice even though
--   the trees agree. By the SES reading: a choice = where a gene lives.
lawMortonIsNotRingHom :: Bool
lawMortonIsNotRingHom =
  morton (1, 0, 0) + morton (1, 0, 0) /= morton (2, 0, 0)

-- ===========================================================================
-- (D) DECODER: exact Conway-Sloane closest-point decoding of A7 (zero-sum vectors
--     in Z^8). Voronoi-relevant vectors of A_n are exactly the roots e_i - e_j,
--     so beating all 56 roots certifies GLOBAL optimality. Weyl group = S8 by
--     coordinate permutation; FOLDING = sorting into the fundamental chamber.
-- ===========================================================================

decodeA7 :: [Q] -> [Integer]
decodeA7 x
  | d > 0     = adjust (fromInteger d)          (sortBy (comparing snd) idelta) (subtract 1)
  | d < 0     = adjust (fromInteger (negate d)) (sortBy (comparing (negate . snd)) idelta) (+ 1)
  | otherwise = f0
  where
    f0     = map round x
    delta  = zipWith (\xi fi -> xi - fromInteger fi) x f0
    idelta = zip [0 :: Int ..] delta
    d      = sum f0
    adjust k order op =
      let picked = map fst (take k order)
      in [ if i `elem` picked then op fi else fi | (i, fi) <- zip [0 ..] f0 ]

dist2 :: [Q] -> [Integer] -> Q
dist2 x f = sum [ (xi - fromInteger fi) ^ (2 :: Int) | (xi, fi) <- zip x f ]

a7Roots :: [[Integer]]
a7Roots = [ [ unit i k - unit j k | k <- [0 .. 7] ] | i <- [0 .. 7], j <- [0 .. 7], i /= j ]
  where unit a k = if a == k then 1 else 0

-- Deterministic pseudo-random dyadic sum-zero test vectors (no ties in delta).
lcg :: [Integer]
lcg = iterate (\s -> (s * 1103515245 + 12345) `mod` 2147483648) 20260703

testVectors :: [[Q]]
testVectors = take 30 (filter tieFree (map center (chunks (drop 1 lcg))))
  where
    chunks s = let (a, b) = splitAt 8 s in a : chunks b
    center raw = let v = map (\s -> fromInteger (s `mod` 129 - 64) / 8) raw
                     m = sum v / 8
                 in map (subtract m) v
    tieFree v = let f0 = map round v
                    dl = zipWith (\xi fi -> xi - fromInteger (fi :: Integer)) v f0
                in length (nub dl) == 8

-- | LAW (Conway-Sloane exactness): the decoded point is IN the lattice (integer, zero
--   sum) and beats every Voronoi-relevant root neighbour -- global CVP optimality,
--   certified in exact rational arithmetic.
lawA7DecodeVoronoiOptimal :: Bool
lawA7DecodeVoronoiOptimal = all ok testVectors
  where
    ok x = let f = decodeA7 x
           in sum f == 0
              && and [ dist2 x f <= dist2 x (zipWith (+) f r) | r <- a7Roots ]

-- | LAW (Weyl equivariance): decode commutes with the S8 coordinate action.
lawA7DecodeWeylEquivariant :: Bool
lawA7DecodeWeylEquivariant =
  and [ decodeA7 (apply p x) == apply p (decodeA7 x) | x <- testVectors, p <- perms ]
  where
    perms   = [ reverse [0 .. 7], [1, 2, 3, 4, 5, 6, 7, 0], [3, 1, 4, 0, 5, 2, 7, 6] ]
    apply p xs = map (xs !!) p

-- | LAW (folding): decoding FACTORS THROUGH THE FOLD -- sort into the fundamental Weyl
--   chamber, decode there, unsort. This is the executable shadow of the 2n-1 = 13-piece
--   folded-boundary theorem; the design consequence is WIRE the reflections, LEARN the
--   residual (gradient descent provably does not find the folding on its own).
lawA7DecodeFactorsThroughFold :: Bool
lawA7DecodeFactorsThroughFold = all ok testVectors
  where
    ok x = let pairs  = sortBy (comparing fst) (zip x [0 :: Int ..])
               ds     = decodeA7 (map fst pairs)
               unsort = map snd (sortBy (comparing fst) (zip (map snd pairs) ds))
           in unsort == decodeA7 x

-- ===========================================================================
-- (C) CHRISTOL: algebraic mod 2^alpha => 2-automatic. Witness: the Catalan
--     numbers (algebraic generating function x*C^2 - C + 1 = 0) reduced mod 2
--     are computed by a 2-state automaton reading binary digits.
-- ===========================================================================

catalans :: [Integer]
catalans = 1 : [ sum (zipWith (*) (take n catalans) (reverse (take n catalans)))
               | n <- [1 ..] ]

-- | The finite automaton: accept iff every binary digit of n is 1 (i.e. n = 2^k - 1).
catalanDFA :: Integer -> Bool
catalanDFA = all (== 1) . digitsMSB
  where digitsMSB 0 = []
        digitsMSB n = digitsMSB (n `div` 2) ++ [n `mod` 2]

-- | LAW (Christol witness): catalan(n) mod 2 == DFA(binary digits of n), n = 0..180.
--   The byte-exact deterministic model, where its behaviour is algebraic, is a
--   provably bounded finite-state object (Rowland-Yassawi size bounds).
lawAlgebraicMod2IsAutomatic :: Bool
lawAlgebraicMod2IsAutomatic =
  and [ (c `mod` 2 == 1) == catalanDFA (fromIntegral n)
      | (n, c) <- zip [0 :: Int .. 180] catalans ]

-- ===========================================================================
-- Runner
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawNetIsTropicalRationalMap  (int-weight net == tropical F(-)G, exact)", lawNetIsTropicalRationalMap)
  , ("lawNetClosesOverDyadic       (dyadic in -> dyadic out, Z[1/2] closure)", lawNetClosesOverDyadic)
  , ("lawHiddenPermutationGauge    (neuron order is gauge; normal form fixed)", lawHiddenPermutationGauge)
  , ("lawRegionsAreNewtonVertices  (linear regions == upper-hull vertices)",    lawRegionsAreNewtonVertices)
  , ("lawSpineReductionsCompose    (layers = reductions mod 2^k, transitive)",  lawSpineReductionsCompose)
  , ("lawMortonIsTreeIso           (8-adic tree == (Z_2)^3 tree, trunc-compat)", lawMortonIsTreeIso)
  , ("lawMortonIsNotRingHom        (but NOT a ring hom: real choice = gene)",   lawMortonIsNotRingHom)
  , ("lawA7DecodeVoronoiOptimal    (Conway-Sloane beats all 56 roots, exact)",  lawA7DecodeVoronoiOptimal)
  , ("lawA7DecodeWeylEquivariant   (decode commutes with S8 action)",           lawA7DecodeWeylEquivariant)
  , ("lawA7DecodeFactorsThroughFold(sort->decode->unsort == decode; wire fold)", lawA7DecodeFactorsThroughFold)
  , ("lawAlgebraicMod2IsAutomatic  (Christol witness: Catalan mod 2 is a DFA)", lawAlgebraicMod2IsAutomatic)
  ]

main :: IO ()
main = do
  putStrLn "ModelAlgebra.hs -- EXPLORATION (NOT WIRED): the MODEL abstracted into DG + ANT"
  putStrLn (replicate 78 '-')
  mapM_ (\(n, ok) -> putStrLn ((if ok then "PASS" else "FAIL") ++ "  " ++ n)) laws
  putStrLn (replicate 78 '-')
  let passed = length (filter snd laws); total = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  let (f, g) = tropicalize demoNet
  putStrLn ("tropicalize demoNet: |F| = " ++ show (length f) ++ " monomials, |G| = "
            ++ show (length g) ++ " monomials")
  putStrLn ("newton hull vertices = " ++ show (upperHull newtonExample)
            ++ "  (monomial (1,1) is interior: never attained)")
  putStrLn ("morton(1,0,0)+morton(1,0,0) = " ++ show (morton (1,0,0) + morton (1,0,0))
            ++ " /= morton(2,0,0) = " ++ show (morton (2,0,0)))
  putStrLn ("decodeA7 (head testVectors) = " ++ show (decodeA7 (head testVectors)))
  putStrLn ""
  putStrLn "The model has three compatible identities: (T) a tropical rational map over"
  putStrLn "Z[1/2] (exact, symbolically checkable); (P) maps commuting with the mod-2^k"
  putStrLn "reductions on the 2-adic spine; (D) a bounded-distance decoder on the A7"
  putStrLn "detail lattice, where the Weyl folding must be WIRED and only the residual"
  putStrLn "learned. LANDED downstream: Spec.RootLatticeDecoder (the decoder contract) and"
  putStrLn "Spec.SpineRing (Morton gene DECIDED: product (Z_2)^3 is the algebra of record,"
  putStrLn "Morton = chart, 8-adic = view; forced by axis idempotents vs local ring)."
