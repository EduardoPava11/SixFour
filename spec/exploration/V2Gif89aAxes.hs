{- |
Module      : V2Gif89aAxes
Description : EXPLORATION - NOT WIRED. "R,G,B,x,y,t == GIF89a, typed." A base-only,
              runghc-checkable typing of the owner's correspondence between the six
              axes of a SixFour point and the GIF89a wire structure.

  THREAD of the SixFour V2 exploration. This module is BASE-ONLY (imports only
  Data.List), is NOT in any cabal file, Map, or gate, and is checkable with:
      runghc V2Gif89aAxes.hs

  THE CORRESPONDENCE (owner-ask #1), typed exactly:

    * a Slot is an Int 0..255.
    * Palette  : Slot      -> RGB    is the colour VALUE head   (what the slot HOLDS).
    * IndexMap : (Int,Int) -> Slot   is the discrete CONTENT head (WHERE / which slot).
    * a Frame at time t is (Palette, IndexMap); t indexes the frame (per-frame palette).
    * render (x,y) = palette (index (x,y))  =  function composition  =  the B combinator
      B = S (K S) K, B palette index = palette . index.

  This EXTENDS GifSki.hs (which proved the B-composition reduction with a CONSTANT
  palette + identity index) by adding: the real (palette, index) function split, the
  six-axis VALUE/DOMAIN/FRAME factorisation, the value/argument asymmetry theorem
  (re-base of lawPositionDistinguishesSameColour), and the Eisenstein chroma-kernel
  tie that grounds the colour VALUE axis in the V2 Z[w] substrate.

  HONESTY (the project rejects forced jargon; claim a structure only if its axioms hold):

    * What is REAL (hard theorems):
        - render = palette . index is genuine function COMPOSITION, and composition IS
          the B combinator (lawRenderIsBComposition both as Haskell (.) and as a Comb
          reduction with non-commutativity teeth).
        - palette DOF and index DOF are INDEPENDENT: the slot chosen at (x,y) does not
          depend on the palette, and the colour of a slot does not depend on (x,y)
          (lawSixAxesFactor, with diagonal-varies teeth so it is not vacuous).
        - position carries DISTINGUISHING information colour alone cannot
          (lawValueArgumentAsymmetry, re-base of lawPositionDistinguishesSameColour).
        - gray (k,k,k) is the KERNEL of the Eisenstein chroma map R->1, G->w, B->w^2
          because 1 + w + w^2 = 0 (lawGrayIsEisensteinKernel); a non-gray colour is not,
          and even a one-step-off-gray colour is already OUT of the kernel (boundary teeth).
        - the value/content split carries a slot-permutation GAUGE (relabel the index by
          sigma and the palette by sigma^-1 and render is unchanged) - the same sigma_t
          Upscale256.alignSlots realises (lawSixAxesFactor gauge tooth).
        - LZW over the index map is LOSSLESS (decode . encode == id) and its dictionary
          REFERENCE count is a real measure of repeated-substring SHARING that is positive
          on structured input and zero on no-repeat input, including the KwKwK self-
          reference that a naive decoder fails (lawLzwReuseIsSharing).

    * What is SUGGESTIVE (marked <>): naming palette the "value/K-like" leg and index
      the "content/S-like" leg does NOT make GIF89a an S/K decomposition; and reading an
      LZW dictionary reference as the S/contraction combinator move is a metaphor, not a
      beta-reduction. As GifSki notes, the real structure of the codec is rank-1
      SEPARABILITY (an outer product) plus Cartesian COMPLETENESS plus a prefix-dictionary
      coder, not term rewriting. We claim the combinator reading only where a term
      genuinely reduces (the B-composition of render), and flag the rest. The LZW reuse
      COUNT and round-trip are kept as theorems; only the combinator picture is flagged.
-}
module V2Gif89aAxes where

import Data.List (intercalate)

-- ===========================================================================
-- (1) The combinator calculus (trimmed from GifSki.hs, for the B-composition witness)
-- ===========================================================================

-- | SKI terms. @App f x@ is application; S, K, I are the primitive combinators.
data Comb = S | K | I | App Comb Comb
  deriving (Eq)

infixl 9 #
-- | Application as an operator, so terms read left-to-right.
(#) :: Comb -> Comb -> Comb
(#) = App

instance Show Comb where
  show S         = "S"
  show K         = "K"
  show I         = "I"
  show (App f x) = "(" ++ show f ++ " " ++ show x ++ ")"

-- | One leftmost-outermost (normal-order) reduction step, if any redex exists.
--   Rules:  I x -> x ;  K x y -> x ;  S f g x -> f x (g x).
step :: Comb -> Maybe Comb
step (App I x)                 = Just x
step (App (App K x) _y)        = Just x
step (App (App (App S f) g) x) = Just (App (App f x) (App g x))
step (App f x)                 =
  case step f of
    Just f' -> Just (App f' x)
    Nothing -> case step x of
                 Just x' -> Just (App f x')
                 Nothing -> Nothing
step _ = Nothing

-- | Normal form by iterating 'step' (bounded so a runaway term cannot hang the check).
nf :: Comb -> Comb
nf = go (10000 :: Int)
  where go 0 t = t
        go n t = case step t of
                   Just t' -> go (n - 1) t'
                   Nothing -> t

-- | Composition combinator @B f g x = f (g x)@, as a closed SKI term: @B = S (K S) K@.
b :: Comb
b = S # (K # S) # K

-- ===========================================================================
-- (2) The typed correspondence:  R,G,B,x,y,t  ==  GIF89a
-- ===========================================================================

-- | A colour-table slot, 0..255 (the GIF89a Local Color Table is 256 entries).
type Slot = Int

-- | A colour VALUE: basic GIF89a 8-bit (R,G,B). This is what a slot HOLDS.
type RGB = (Int, Int, Int)

-- | The colour VALUE head: @Slot -> RGB@ (the Local Color Table, one per frame).
type Palette = Slot -> RGB

-- | The discrete CONTENT head: @(x,y) -> Slot@ (the row-major index map).
type IndexMap = (Int, Int) -> Slot

-- | A frame at one time @t@ is its own (palette, index map) pair (per-frame LCT).
type Frame = (Palette, IndexMap)

-- | render(x,y) = palette (index (x,y)) = the B-combinator composition  palette . index.
render :: Frame -> (Int, Int) -> RGB
render (pal, idx) = pal . idx

-- | The two projection legs, named so the independence law can state cross-derivatives.
selectSlot :: Frame -> (Int, Int) -> Slot         -- the CONTENT leg (index only)
selectSlot (_pal, idx) p = idx p

colourOf :: Frame -> Slot -> RGB                  -- the VALUE leg (palette only)
colourOf (pal, _idx) s = pal s

-- --- two concrete palettes (VALUE heads), genuinely different -----------------

pal0 :: Palette
pal0 s = case s `mod` 4 of
  0 -> (255,   0,   0)
  1 -> (  0, 255,   0)
  2 -> (  0,   0, 255)
  _ -> ( 40,  40,  40)

pal1 :: Palette
pal1 s = case s `mod` 4 of
  0 -> ( 10,  10,  10)
  1 -> ( 20,  20,  20)
  2 -> ( 30,  30,  30)
  _ -> (250, 250, 250)

-- --- two concrete index maps (CONTENT heads), genuinely different -------------

idx0 :: IndexMap
idx0 (x,y) = (x + 2*y) `mod` 256

idx1 :: IndexMap
idx1 (x,y) = (3*x + y) `mod` 256

-- | A small grid of sample positions (x,y).
positions :: [(Int,Int)]
positions = [ (x,y) | x <- [0..7], y <- [0..7] ]

-- | The 256 slots.
slots :: [Slot]
slots = [0..255]

-- ===========================================================================
-- (3) A P6-style six-axis point and its two metrics (re-base of RelationalMemory)
-- ===========================================================================

-- | A six-axis point (r,g,b, x,y,t): colour VALUE (r,g,b) + position (x,y) + frame t.
data P6 = P6 { p6R, p6G, p6B, p6X, p6Y, p6T :: !Int } deriving (Eq, Show)

-- | L1 distance over the COLOUR axes only (what a position-blind / palette-only view sees).
dColour :: P6 -> P6 -> Int
dColour a c = abs (p6R a - p6R c) + abs (p6G a - p6G c) + abs (p6B a - p6B c)

-- | L1 distance over ALL SIX axes (the full metric key: colour + position + frame).
d6 :: P6 -> P6 -> Int
d6 a c = dColour a c
       + abs (p6X a - p6X c) + abs (p6Y a - p6Y c) + abs (p6T a - p6T c)

-- | Build the six-axis point a pixel occupies under a frame at time t.
pixelP6 :: Frame -> Int -> (Int,Int) -> P6
pixelP6 fr t (x,y) = let (r,g,bl) = render fr (x,y) in P6 r g bl x y t

-- ===========================================================================
-- (4) Eisenstein chroma: R->1, G->w, B->w^2 over Z[w], w^2 = -1 - w
-- ===========================================================================

-- | An Eisenstein integer @a + b*w@ (w = exp(2*pi*i/3)).
data Eisen = Eisen Int Int deriving (Eq, Show)

eadd :: Eisen -> Eisen -> Eisen
eadd (Eisen a b') (Eisen c d) = Eisen (a + c) (b' + d)

-- | Scale an Eisenstein integer by an Int (R,G,B are non-negative integer weights).
escale :: Int -> Eisen -> Eisen
escale k (Eisen a b') = Eisen (k*a) (k*b')

-- The three primaries as Eisenstein units, 120 degrees apart; w^2 = -1 - w so 1+w+w^2 = 0.
eR, eG, eB :: Eisen
eR = Eisen 1 0          -- R -> 1     (0 deg)
eG = Eisen 0 1          -- G -> w     (120 deg)
eB = Eisen (-1) (-1)    -- B -> w^2   (240 deg)  = -1 - w

-- | chroma(r,g,b) = r*1 + g*w + b*w^2, reduced in Z[w]. Equals Eisen (r-b) (g-b).
chroma :: RGB -> Eisen
chroma (r,g,bl) = escale r eR `eadd` escale g eG `eadd` escale bl eB

-- ===========================================================================
-- (4b) LZW over the index map: the dictionary is the latent; a reference = SHARING
-- ===========================================================================
--
-- Owner ask #2: "we think in per-frame palettes, index maps, and LZW." The index map
-- is the discrete latent; LZW is the COMPUTE over it. An LZW dictionary REFERENCE
-- reuses a repeated index substring = explicit SHARING (the reuse COUNT is a REAL,
-- measurable fact; the dictionary GROWS with structure).
--
-- SUGGESTIVE (flagged, NOT claimed as an axiom): reading a dictionary reference as the
-- S/contraction combinator move ("share one subterm at two use sites") is a metaphor.
-- LZW is a prefix-dictionary string coder; it does not beta-reduce. We keep the reuse
-- COUNT and the lossless round-trip as theorems and label the combinator reading as a
-- picture only.

-- | LZW encode a stream of slot indices (singletons 0..255 seed the dictionary; new
--   codes start at 256). Output codes >= 256 are dictionary references (shared substrings).
lzwEncode :: [Int] -> [Int]
lzwEncode = goEnc initEncDict 256 []
  where
    initEncDict = [ ([c], c) | c <- [0 .. 255] ]
    -- invariant: w is always a string already present in dict (or [] at the very start,
    -- where it is never looked up), so 'look' is total on every reachable call.
    look dict s = case lookup s dict of
                    Just c  -> c
                    Nothing -> error "lzwEncode: unreachable (w always in dict)"
    goEnc :: [([Int], Int)] -> Int -> [Int] -> [Int] -> [Int]
    goEnc dict _    w []       = [ look dict w | not (null w) ]
    goEnc dict next w (k : ks) =
      let wk = w ++ [k]
      in case lookup wk dict of
           Just _  -> goEnc dict next wk ks
           Nothing -> look dict w : goEnc ((wk, next) : dict) (next + 1) [k] ks

-- | The CORRECT LZW decode, including the self-referential KwKwK special case (a code
--   used the instant it is defined, before the decoder has it). Inverts 'lzwEncode'.
lzwDecode :: [Int] -> [Int]
lzwDecode []        = []
lzwDecode (c0 : cs) = [c0] ++ goDec initDecDict 256 [c0] cs
  where
    initDecDict = [ (c, [c]) | c <- [0 .. 255] ]
    goDec :: [(Int, [Int])] -> Int -> [Int] -> [Int] -> [Int]
    goDec _    _    _    []       = []
    goDec dict next prev (c : cs') =
      let entry   = case lookup c dict of
                      Just e  -> e
                      Nothing -> prev ++ [head prev]      -- KwKwK: code == next, not yet stored
          newDict = (next, prev ++ [head entry]) : dict
      in entry ++ goDec newDict (next + 1) entry cs'

-- | A NAIVE decoder WITHOUT the KwKwK special case: on a not-yet-stored code it cannot
--   proceed and stops. Used as a counter-witness that the special case has teeth.
lzwDecodeNaive :: [Int] -> [Int]
lzwDecodeNaive []        = []
lzwDecodeNaive (c0 : cs) = [c0] ++ goN initDecDict 256 [c0] cs
  where
    initDecDict = [ (c, [c]) | c <- [0 .. 255] ]
    goN :: [(Int, [Int])] -> Int -> [Int] -> [Int] -> [Int]
    goN _    _    _    []       = []
    goN dict next prev (c : cs') =
      case lookup c dict of
        Nothing    -> []                                  -- naive coder breaks on KwKwK
        Just entry -> entry ++ goN ((next, prev ++ [head entry]) : dict) (next + 1) entry cs'

-- ===========================================================================
-- (5) Laws (each a Bool, each with TEETH)
-- ===========================================================================

-- | LAW 1. render == palette . index, as Haskell composition AND as the B combinator.
--   TEETH: (a) render agrees with the explicit composition pointwise on a real frame;
--          (b) the B combinator reduces b f g x -> f (g x); and crucially
--          (c) composition is NON-COMMUTATIVE: there is a witness where f (g x) and
--              g (f x) reach DIFFERENT normal forms, so "palette after index" is a
--              real ordered fact, not a symmetric coincidence.
lawRenderIsBComposition :: Bool
lawRenderIsBComposition =
      -- (a) the typed render is exactly the composition palette . index
      and [ render fr p == pal (idx p) | p <- positions ]
      -- (b) the B combinator realises composition on combinator witnesses
   && and [ nf (b # f # g # x) == nf (f # (g # x)) | (f,g,x) <- triples ]
      -- (c) ordered, not commutative: at least one witness separates f(g x) from g(f x)
   && or  [ nf (f # (g # x)) /= nf (g # (f # x)) | (f,g,x) <- triples ]
  where
    fr@(pal, idx) = (pal0, idx0)
    triples = [ (K, S, I), (K, I, S), (S, K, I) ]

-- | LAW 2. The six axes FACTOR: VALUE (r,g,b) is disjoint from DOMAIN (x,y) and FRAME (t).
--   The slot chosen at (x,y) depends ONLY on the index map (palette-blind); the colour
--   of a slot depends ONLY on the palette (position-blind).
--   TEETH (not vacuous): the OFF-diagonal derivatives are zero WHILE the ON-diagonal
--   derivatives are non-zero. Concretely: swapping the palette leaves every selected
--   slot unchanged yet DOES change some rendered colour (so the palette really differs);
--   swapping the index leaves every slot's colour unchanged yet DOES move some position
--   to a different slot (so the index really differs).
lawSixAxesFactor :: Bool
lawSixAxesFactor =
      -- off-diagonal 1: slot selection is independent of the palette.
      -- HONEST: this holds DEFINITIONALLY (selectSlot is typed to ignore the palette);
      -- it documents the type-level disjointness, it is not where the teeth live.
      and [ selectSlot (pal0, idx0) p == selectSlot (pal1, idx0) p | p <- positions ]
      -- off-diagonal 2: a slot's colour is independent of the index map (also definitional).
   && and [ colourOf (pal0, idx0) s == colourOf (pal0, idx1) s | s <- slots ]
      -- diagonal teeth 1: the palette swap is real (some colour actually changes)
   && or  [ render (pal0, idx0) p /= render (pal1, idx0) p | p <- positions ]
      -- diagonal teeth 2: the index swap is real (some position moves to a new slot)
   && or  [ selectSlot (pal0, idx0) p /= selectSlot (pal0, idx1) p | p <- positions ]
      -- GAUGE TOOTH (non-tautological): the value/content split has a slot-permutation
      -- GAUGE symmetry (the same sigma_t that Upscale256.alignSlots realises). Relabel
      -- every slot by sigma in the index and by sigma^-1 in the palette and render is
      -- UNCHANGED, even though BOTH heads genuinely differ. This needs sigma . sigma^-1
      -- == id (a real fact), so it cannot pass vacuously.
   && and [ render (palG, idxG) p == render (pal0, idx0) p | p <- positions ]
   && or  [ idxG p /= idx0 p | p <- positions ]              -- the index really moved
   && or  [ palG s /= pal0 s | s <- slots ]                  -- the palette really moved
  where
    sigma    s = (s + 1) `mod` 256          -- a concrete slot permutation
    sigmaInv s = (s - 1) `mod` 256          -- its inverse: sigma . sigmaInv == id
    idxG p = sigma (idx0 p)                  -- relabel content by sigma
    palG s = pal0 (sigmaInv s)               -- compensate the value by sigma^-1

-- | LAW 3. Value/argument asymmetry: two pixels at DIFFERENT (x,y) routed through the
--   SAME slot carry the SAME RGB VALUE yet are DISTINCT CONTENT. A colour-only (palette-
--   blind) comparison wrongly EQUATES them; the full six-axis metric separates them.
--   This is the re-base of lawPositionDistinguishesSameColour.
--   TEETH: dColour collapses every same-slot pair to 0 while d6 is strictly positive;
--          and dColour is NOT constantly 0 (a genuinely different-colour pair is > 0),
--          so the colour metric is real, not trivially blind.
lawValueArgumentAsymmetry :: Bool
lawValueArgumentAsymmetry =
      -- for every pair of distinct positions the same frame routes to the same slot,
      -- the colour-only view is blind (==0) but the full metric distinguishes (>0).
      and [ dColour pa pc == 0 && d6 pa pc > 0
          | (p, q) <- sameSlotPairs
          , let pa = pixelP6 fr 0 p
                pc = pixelP6 fr 0 q ]
      -- teeth: there really ARE such pairs (the law is not vacuously over an empty set)
   && not (null sameSlotPairs)
      -- teeth: dColour is a real metric, not constantly zero (different colours -> > 0)
   && dColour (P6 0 0 255 0 1 0) (P6 255 0 0 2 0 0) > 0
  where
    fr = (pal0, idx0)
    sameSlotPairs =
      [ (p, q)
      | p <- positions, q <- positions
      , p < q
      , selectSlot fr p == selectSlot fr q ]   -- same slot => same RGB under one palette

-- | LAW 4. Gray is the Eisenstein KERNEL. Under R->1, G->w, B->w^2 (with 1+w+w^2 = 0),
--   every gray pixel (k,k,k) maps to chroma ZERO, and no non-gray colour does.
--   TEETH: the gray set maps to Eisen 0 0 (kernel membership), AND a curated set of
--          non-gray colours each maps to a NON-zero Eisenstein integer (the kernel is
--          exactly the gray axis, not all of Z[w]); plus the defining syzygy
--          eR + eG + eB == 0 holds.
lawGrayIsEisensteinKernel :: Bool
lawGrayIsEisensteinKernel =
      -- the syzygy 1 + w + w^2 = 0 that MAKES gray the kernel
      (eR `eadd` eG `eadd` eB) == Eisen 0 0
      -- every gray pixel is in the kernel
   && and [ chroma (k,k,k) == Eisen 0 0 | k <- [0,1,7,40,128,200,255] ]
      -- no non-gray colour is in the kernel (teeth: kernel == gray axis exactly)
   && and [ chroma col /= Eisen 0 0 | col <- nonGray ]
      -- BOUNDARY TOOTH: the kernel is EXACTLY the gray axis, so a colour ONE STEP off
      -- gray (k,k,k+-1) is already OUT of the kernel. Without this, "no non-gray colour"
      -- could be passing only on colours that are far from the diagonal.
   && and [ chroma (k,k,k+1) == Eisen (-1) (-1) | k <- [0,40,128,254] ]
   && and [ chroma (k,k+1,k) == Eisen 0    1    | k <- [0,40,128,254] ]
   && and [ chroma (k+1,k,k) == Eisen 1    0    | k <- [0,40,127,254] ]
  where
    nonGray = [ (255,0,0), (0,255,0), (0,0,255), (128,64,200)
              , (17,200,99), (255,128,0), (3,251,7), (200,200,1) ]

-- | LAW 5. LZW over the index map: the dictionary REFERENCE is real SHARING, the codec
--   is lossless, and the famous KwKwK self-reference is handled (the combinator reading
--   is suggestive, the reuse COUNT and round-trip are theorems).
--   TEETH: (a) decode . encode == id on every stream (lossless, the real theorem);
--          (b) the reuse count (codes >= 256 = shared substrings) is POSITIVE on a
--              repetitive index stream and ZERO on a no-repeat stream, so "the dictionary
--              grows with structure" is non-vacuous (sharing tracks structure);
--          (c) the KwKwK boundary: the self-referential code (258 here, used the instant
--              it is defined) is actually EMITTED, the CORRECT decoder round-trips it, and
--              a NAIVE decoder lacking the special case FAILS on it (counter-witness).
lawLzwReuseIsSharing :: Bool
lawLzwReuseIsSharing =
      -- (a) lossless: decode inverts encode on every stream (incl. empty + KwKwK)
      and [ lzwDecode (lzwEncode s) == s | s <- streams ]
      -- (b) sharing tracks structure: reuse > 0 on repetitive, == 0 on no-repeat
   && reuseCount kwkwk    >  0
   && reuseCount norepeat == 0
      -- (c) KwKwK boundary: the self-referential code is emitted, correct decoder
      --     round-trips, naive decoder (no special case) FAILS => the case has teeth
   && elem 258 (lzwEncode kwkwk)
   && lzwDecode      (lzwEncode kwkwk) == kwkwk
   && lzwDecodeNaive (lzwEncode kwkwk) /= kwkwk
  where
    kwkwk    = [0,1,0,1,0,1,0]                 -- "ABABABA": forces the LZW anomaly at 258
    norepeat = [0,1,2,3,4]                      -- strictly increasing: no substring repeats
    streams  = [ kwkwk, norepeat, [], [7], [3,3,3,3], [9,9,8,9,9,8,9,9,8] ]
    reuseCount s = length (filter (>= 256) (lzwEncode s))

-- | The FRAME axis (t) is real, not type-level decoration. (a) Per-frame palette: the SAME index
--   under two frames' palettes renders DIFFERENT colours, so which frame (t) you are in carries
--   colour information (the GIF89a Local Color Table is per-frame). (b) d6 SEES the frame axis while
--   dColour is BLIND: two points with identical colour and (x,y) but different t are separated by
--   d6 (=1) yet collapsed by dColour (=0). TEETH: (a) needs a genuine palette disagreement; (b) pins
--   d6 == 1 exactly (a t-blind metric would give 0).
lawFrameAxisCarriesInfo :: Bool
lawFrameAxisCarriesInfo =
     any (\p -> render (pal0, idx0) p /= render (pal1, idx0) p) positions      -- (a) per-frame palette
  && all (\p -> let q0 = pixelP6 (pal0, idx0) 0 p
                    q1 = pixelP6 (pal0, idx0) 1 p
                in dColour q0 q1 == 0 && d6 q0 q1 == 1) positions              -- (b) d6 sees t, dColour blind

-- ===========================================================================
-- (6) Runner (mirrors GifSki.hs exactly)
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawRenderIsBComposition  (render = palette . index = B)", lawRenderIsBComposition)
  , ("lawSixAxesFactor         (value DOF _|_ index DOF)",      lawSixAxesFactor)
  , ("lawValueArgumentAsymmetry(same slot, distinct (x,y))",    lawValueArgumentAsymmetry)
  , ("lawGrayIsEisensteinKernel(gray (k,k,k) -> chroma 0)",     lawGrayIsEisensteinKernel)
  , ("lawLzwReuseIsSharing      (dict ref = sharing; KwKwK ok)", lawLzwReuseIsSharing)
  , ("lawFrameAxisCarriesInfo   (t real: per-frame palette, d6 sees t)", lawFrameAxisCarriesInfo)
  ]

main :: IO ()
main = do
  putStrLn "V2Gif89aAxes.hs  -- EXPLORATION (NOT WIRED): R,G,B,x,y,t == GIF89a, typed"
  putStrLn (replicate 72 '-')
  mapM_ (\(n,ok) -> putStrLn (verdict ok ++ "  " ++ n)) laws
  putStrLn (replicate 72 '-')
  let passed = length (filter snd laws)
      total  = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  putStrLn ("render (pal0,idx0) at (1,1) = "
            ++ show (render (pal0,idx0) (1,1))
            ++ "   == pal0 (idx0 (1,1)) = " ++ show (pal0 (idx0 (1,1))))
  putStrLn ("B = S (K S) K = " ++ show b)
  putStrLn ("chroma of gray (128,128,128) = " ++ show (chroma (128,128,128))
            ++ "   (the Eisenstein kernel)")
  putStrLn ("LZW [0,1,0,1,0,1,0] -> codes " ++ show (lzwEncode [0,1,0,1,0,1,0])
            ++ "   (258 = the shared KwKwK reference; decode round-trips)")
  putStrLn ""
  putStrLn "HONEST NOTE: render = palette . index (the B combinator), the value/index DOF"
  putStrLn "split (with its slot-permutation gauge), the position-distinguishes-equal-colour"
  putStrLn "asymmetry, the gray = Z[w] chroma kernel, and the LZW reuse-COUNT + lossless"
  putStrLn "round-trip are REAL theorems. Naming palette the 'K/value' leg and index the"
  putStrLn "'S/content' leg, and reading an LZW dictionary reference as the S/contraction"
  putStrLn "move, are SUGGESTIVE: the codec's true structure is rank-1 separability (outer"
  putStrLn "product) + Cartesian completeness + a prefix-dictionary coder, not S/K rewriting."
  where verdict True  = "PASS"
        verdict False = "FAIL"

-- Silence an unused-import warning if intercalate is not used in some builds.
_unused :: String
_unused = intercalate "," []
