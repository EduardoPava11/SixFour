{- |
Module      : GifSki
Description : EXPLORATION - NOT WIRED. A self-contained SKI-combinator reading of the
              GIF89a value(palette) x content(index) codec, grounded on the OneSix
              hylomorphism backbone (recursion schemes are point-free combinatory logic).

  THREAD B of the SixFour/OneSix two-lens exploration. This module is BASE-ONLY and is
  NOT in any cabal file, Map, or gate. It is checkable with:  runghc GifSki.hs

  HONESTY (the project rejects forced jargon; claim a structure only if its axioms hold):

    * What is REAL: the combinator CALCULUS here is genuine. S, K, I reduce by their
      standard rules; I == S K K is a derivable theorem (lawIisSKK); rendering a pixel
      "palette (index pos)" is honest function COMPOSITION, which IS a combinator term
      (the B combinator, B = S (K S) K), and it reduces to the looked-up colour.

    * What is DECORATIVE / suggestive (marked <>): naming the palette "K" and the index
      "S" does NOT make GIF89a a K/S decomposition. The real structure of the codec is
      rank-1 SEPARABILITY (an outer product, linear algebra) plus combinatorial
      COMPLETENESS (a set-theoretic Cartesian product), NOT term rewriting. K is a
      reduction rule (syntax, universal); a palette is static data (semantics, fixed).
      SKI describes HOW you may COMPUTE the codec point-free / deforested (the hylo IS
      already point-free), not WHAT the codec IS. We keep the names only where a term
      genuinely reduces to the intended value, and flag the rest as suggestive.
-}
module GifSki where

import Data.List (intercalate)

-- ===========================================================================
-- (1) The combinator calculus
-- ===========================================================================

-- | SKI terms. @App f x@ is application; S, K, I are the primitive combinators.
data Comb = S | K | I | App Comb Comb
  deriving (Eq)

infixl 9 #
-- | Application as an operator, so terms read left-to-right.
(#) :: Comb -> Comb -> Comb
(#) = App

instance Show Comb where
  show S            = "S"
  show K            = "K"
  show I            = "I"
  show (App f x)    = "(" ++ show f ++ " " ++ show x ++ ")"

-- | One leftmost-outermost (normal-order) reduction step, if any redex exists.
--   Rules:  I x -> x ;  K x y -> x ;  S f g x -> f x (g x).
step :: Comb -> Maybe Comb
step (App I x)                 = Just x
step (App (App K x) _y)        = Just x
step (App (App (App S f) g) x) = Just (App (App f x) (App g x))
step (App f x)                 =
  case step f of                   -- try the function position first (outermost-left)
    Just f' -> Just (App f' x)
    Nothing -> case step x of      -- then the argument
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

-- | Reduce to weak head normal form (head reductions only; arguments left alone).
whnf :: Comb -> Comb
whnf = go (10000 :: Int)
  where go 0 t = t
        go n t = case headStep t of
                   Just t' -> go (n - 1) t'
                   Nothing -> t
        headStep (App I x)                 = Just x
        headStep (App (App K x) _y)        = Just x
        headStep (App (App (App S f) g) x) = Just (App (App f x) (App g x))
        headStep (App f x)                 = fmap (`App` x) (headStep f)
        headStep _                         = Nothing

-- | A SECOND, deliberately different reduction order (reduce the ARGUMENT first when the
--   head is not yet a redex) used only to WITNESS confluence: SKI is Church-Rosser, so
--   normalising by either order must reach the same normal form on terminating terms.
stepInner :: Comb -> Maybe Comb
stepInner (App f x) =
  case (isRedexHead (App f x), stepInner x) of
    (True, _)        -> step (App f x)          -- head is a redex: take it
    (False, Just x') -> Just (App f x')         -- otherwise dig into the argument first
    (False, Nothing) -> fmap (`App` x) (stepInner f)
  where
    isRedexHead (App I _)               = True
    isRedexHead (App (App K _) _)       = True
    isRedexHead (App (App (App S _) _) _) = True
    isRedexHead _                       = False
stepInner _ = Nothing

nfInner :: Comb -> Comb
nfInner = go (10000 :: Int)
  where go 0 t = t
        go n t = case stepInner t of
                   Just t' -> go (n - 1) t'
                   Nothing -> t

-- | Composition combinator @B f g x = f (g x)@, as a closed SKI term: @B = S (K S) K@.
b :: Comb
b = S # (K # S) # K

-- ===========================================================================
-- (2) The GIF89a reading
-- ===========================================================================
--
-- A pixel is rendered as  colour = palette (index position).  We model:
--   * a POSITION as a distinct normal-form token (here: I, standing for "this pixel"),
--   * the INDEX as a function position -> slot,
--   * the PALETTE as a function slot -> colour,
--   * rendering as the COMPOSITION  palette . index  =  B palette index.
--
-- We instantiate the simplest honest case: a CONSTANT palette (every slot maps to one
-- colour -- this is exactly  K colour, ignoring its slot argument) and the identity
-- index (the pixel's slot is itself). Then  render pos == colour, by reduction.

-- | A colour token (a distinct closed normal form so equality is meaningful).
colour :: Comb
colour = K # K            -- an arbitrary fixed normal form standing for "a palette colour"

-- | A pixel position token.
position :: Comb
position = S # K          -- another distinct normal form standing for "this pixel"

-- | The palette as the CONSTANT map @K colour@ : feed it any slot, get @colour@ back.
--   (<> "palette == K" is suggestive: a real palette is a 256-entry table, not the K rule;
--    we use K only because a constant-palette lookup genuinely reduces like @K x y = x@.)
paletteK :: Comb
paletteK = K # colour

-- | The index as the identity @I@ (the slot of a pixel is the pixel itself, here).
indexI :: Comb
indexI = I

-- | Render one pixel: @palette (index position)@ written point-free as @B palette index@.
render :: Comb
render = b # paletteK # indexI

-- ===========================================================================
-- (3) Example laws (each a Bool)
-- ===========================================================================

-- | I IS derivable: @S K K x@ reduces to @x@ (so I = SKK, the byte-exact identity floor).
lawIisSKK :: Bool
lawIisSKK = and [ nf (S # K # K # t) == nf t | t <- sampleTerms ]
  where sampleTerms = [colour, position, S, K, I, K # I]

-- | K reduces per its rule: @K x y -> x@ (the constant palette colour, independent of slot).
lawKConst :: Bool
lawKConst = and [ nf (K # x # y) == nf x | (x, y) <- pairs ]
  where pairs = [(colour, position), (S, K), (I, colour)]

-- | S reduces per its rule: @S f g x -> f x (g x)@ (the index distributing over a position).
lawSDistributes :: Bool
lawSDistributes = and [ nf (S # f # g # x) == nf (f # x # (g # x)) | (f,g,x) <- triples ]
  where triples = [(K, K, colour), (K, I, position), (I, K, K), (S, K, I)]

-- | The composition combinator behaves: @B f g x == f (g x)@.
lawComposition :: Bool
lawComposition = and [ nf (b # f # g # x) == nf (f # (g # x)) | (f,g,x) <- triples ]
  where triples = [(paletteK, indexI, position), (K, I, colour), (I, I, S)]

-- | The render term "palette[index(position)]" reduces to the looked-up colour.
--   This is the one place the GIF reading is REAL: a constant-palette lookup of any
--   position yields that palette's colour, by pure reduction.
lawRenderLooksUpColour :: Bool
lawRenderLooksUpColour = nf (render # position) == nf colour

-- | Confluence (Church-Rosser) on the small terms used: normalising by the normal-order
--   strategy and by the inner-first strategy reaches the SAME normal form.
lawConfluence :: Bool
lawConfluence = and [ nf t == nfInner t | t <- terms ]
  where terms = [ S # K # K # colour
                , K # colour # position
                , S # K # I # colour
                , render # position
                , b # paletteK # indexI # position
                , S # (K # S) # K # K # I # S ]

-- | 'nf' is idempotent on these terms (a sanity check that reduction has truly settled).
lawNfIdempotent :: Bool
lawNfIdempotent = and [ nf (nf t) == nf t | t <- terms ]
  where terms = [render # position, S # K # K # colour, b # K # I # S]

-- ===========================================================================
-- (4) Runner
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawIisSKK            (I = S K K)",               lawIisSKK)
  , ("lawKConst            (K x y -> x : palette)",    lawKConst)
  , ("lawSDistributes      (S f g x -> f x (g x))",    lawSDistributes)
  , ("lawComposition       (B f g x = f (g x))",       lawComposition)
  , ("lawRenderLooksUp     (palette[index pos]=col)",  lawRenderLooksUpColour)
  , ("lawConfluence        (two orders, one NF)",      lawConfluence)
  , ("lawNfIdempotent      (nf . nf = nf)",            lawNfIdempotent)
  ]

main :: IO ()
main = do
  putStrLn "GifSki.hs  -- EXPLORATION (NOT WIRED): GIF89a value/content as an SKI reading"
  putStrLn (replicate 72 '-')
  mapM_ (\(n,ok) -> putStrLn (verdict ok ++ "  " ++ n)) laws
  putStrLn (replicate 72 '-')
  let passed = length (filter snd laws)
      total  = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  putStrLn ("render (point-free) = " ++ show render)
  putStrLn ("render position reduces to: " ++ show (nf (render # position))
            ++ "   (== colour: " ++ show (nf (render # position) == nf colour) ++ ")")
  putStrLn ("B = S (K S) K = " ++ show b)
  putStrLn ""
  putStrLn "HONEST NOTE: the calculus is real (I=SKK, render reduces to the colour);"
  putStrLn "the names palette=K / index=S are SUGGESTIVE. GIF89a's true structure is"
  putStrLn "rank-1 separability (outer product) + Cartesian completeness, not K/S rewriting."
  where verdict True  = "PASS"
        verdict False = "FAIL"

-- Silence an unused-import warning if intercalate is not used in some builds.
_unused :: String
_unused = intercalate "," []
