{- |
Module      : V2SkiLevels
Description : EXPLORATION - NOT WIRED. "SKI nested-function stack, explored by levels."
              The octree-level stack of renders as a chain of B-compositions, peeled one
              reduction at a time, with each level tagged I / S / K per the blessed
              expand/contract reading (spec/exploration/V2-SKI-EXPAND-CONTRACT.md).

  THREAD of the SixFour/OneSix two-lens exploration. This module is BASE-ONLY and is NOT
  in any cabal file, Map, or gate. It is checkable with:  runghc V2SkiLevels.hs

  WHAT IT MODELS. A render at octree depth d is a STACK of d levels. Each level is a
  (palette, index) pair, and its contribution is the per-level B-composition
  @levelFn = palette . index = B palette index@. The whole stack renders by NESTED
  composition @renderStack = foldr (.) id (map levelFn levels)@: a chain of B-compositions,
  i.e. an SKI stack of nested functions. "Explore by levels" = peel that stack one
  @step@/reduction at a time; the number of peels to normal form is the ponder depth d.

  THE BLESSED ROLE ASSIGNMENT (V2-SKI-EXPAND-CONTRACT.md Section 2, REAL, not re-derived):
    * I = the HELD / reversible rung. levelFn = id on its band (a bijection: nothing
      created, nothing lost). Referent: @unliftOct . liftOct == id@.
    * K = pool DOWN = weakening (the affine structural rule). levelFn DISCARDS detail and
      is non-injective downward. Referent: @scalarCollapseLossy = ocCoarse . liftOct@
      (keeps the coarse DC, drops the detail). It is the ONLY way to lose information.
    * S = invent UP = contraction (the full-SKI structural rule). levelFn DUPLICATES: a
      single coarse cell is used TWICE (kept as anchor, and fed to the inventor that
      manufactures detail), so the output cardinality grows. Referent: @liftKeyed book
      coarse@ where @coarse@ appears twice (PairedResidual.hs:83). S is the ONLY role that
      can increase the distinct-output count, and is barred on the byte-exact floor because
      the floor is a bijection (BCI excludes contraction).

  TWICENESS: one rung = exactly TWO octree levels (levelsPerStep = 2): @rung = level . level@.

  HONESTY (the project rejects forced jargon; claim a structure only if its axioms hold):

    * What is REAL: @renderStack = foldr (.) id (map levelFn levels)@ is genuine function
      composition, and function composition IS the B combinator (B = S (K S) K, proven in
      GifSki.hs and re-witnessed here as lawBChainIsNesting: a chain of B's reduces to
      nested application). The substructural grading is real and load-bearing: I = bijection
      (length and value preserved), K = non-injective shrink (a collision witness exhibits
      lost information), S = the unique cardinality-increasing move. These are checked at the
      boundary, with teeth (mislabelling S as I claims invention is the identity, which FAILS).

    * What is near-DEFINITIONAL (marked <>): lawNestedRenderIsBStack is true essentially by
      the meaning of @foldr (.) id@; its CONTENT is the order-sensitivity tooth (reversing
      the level order changes the render) plus the calculus witness lawBChainIsNesting, not
      the fold identity itself.

    * What is DECORATIVE / suggestive (marked <>): naming a level "K" or "S" does not make
      the octree a term-rewrite system. The real structure is the substructural grading
      (BCI/BCK/SKI = reversible/affine/contraction), NOT syntactic reduction; we keep the
      I/S/K names only where a level genuinely is a bijection / a discard / a duplication.
      This file is AXIS-AGNOSTIC: it does NOT seat I on Red. Per V2 the I carrier sits on
      luma (the (1,1,1) balance axis, the Eisenstein chroma kernel), no single primary;
      bands here are abstract DC/detail, not R/G/B channels.

    * The LZW bridge (Owner ask #2), split into FACT and SUGGESTION: the FACT is the
      dictionary back-reference COUNT (@reuseCount@) = how many emitted codes reuse a stored
      multi-symbol phrase = an exact, round-trip-verified count of explicit SHARING. The
      SUGGESTION (NOT a checked axiom) is reading each such reuse as the S/contraction move
      and the growing dictionary as "the latent". LZW growth is structurally analogous to
      contraction, not literally the SKI S-rule; only the count is load-bearing.
-}
module V2SkiLevels where

import Data.List (intercalate, nub, sort)

-- ===========================================================================
-- (1) The combinator calculus (mirrors GifSki.hs verbatim: grounds the B reading)
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
    isRedexHead (App I _)                 = True
    isRedexHead (App (App K _) _)         = True
    isRedexHead (App (App (App S _) _) _) = True
    isRedexHead _                         = False
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
-- (2) The level stack: per-level (palette, index) = B-composition, tagged I/S/K
-- ===========================================================================
--
-- A Frame is one octree band's worth of cells. A level transforms a Frame: its index
-- reshapes/reindexes the cells, its palette recolours them, and levelFn = palette . index
-- is the per-level B-composition. The stack renders by foldr (.) id (a chain of B's).

-- | A band of cells (abstract DC/detail values; NOT R/G/B channels).
type Frame = [Int]

-- | The expand/contract role of a level, per V2-SKI-EXPAND-CONTRACT.md Section 2.
data Role = RoleI   -- ^ held / reversible bijection (I)
          | RoleS   -- ^ invent UP / contraction, the only cardinality-increasing move (S)
          | RoleK   -- ^ pool DOWN / weakening, discards detail, non-injective (K)
  deriving (Eq, Show)

-- | One level: a role tag plus its (palette, index) pair. @lvIndex@ reshapes the cells
--   (the discrete CONTENT move), @lvPalette@ recolours them (the VALUE move).
data Level = Level
  { lvRole    :: Role
  , lvPalette :: Frame -> Frame   -- ^ slot -> colour, applied AFTER the index
  , lvIndex   :: Frame -> Frame   -- ^ (x,y) -> slot, the reshape/reindex
  }

-- | A level's render contribution, the per-level B-composition @palette . index@.
levelFn :: Level -> (Frame -> Frame)
levelFn l = lvPalette l . lvIndex l

-- | Render a STACK of levels by nested composition: a right-fold of B-compositions.
--   @renderStack [f1,f2,f3] x = f1 (f2 (f3 x))@. This is the SKI stack of nested functions.
renderStack :: [Level] -> Frame -> Frame
renderStack ls = foldr (.) id (map levelFn ls)

-- --- the three role primitives -------------------------------------------------------

-- | I-index: identity reshape (the held rung keeps every cell where it is).
heldIndex :: Frame -> Frame
heldIndex = id

-- | K-index: pool DOWN. Keep the coarse cell of each (coarse, detail) pair, DROP the
--   detail. Non-injective (the discarded detail is unrecoverable) = true weakening.
poolDown :: Frame -> Frame
poolDown (coarse:_detail:rest) = coarse : poolDown rest
poolDown [coarse]              = [coarse]
poolDown []                    = []

-- | S-index: invent UP. Each coarse cell becomes (coarse, inventFrom coarse): the single
--   @coarse@ is used TWICE (kept as anchor, fed to the inventor) = genuine contraction.
expandUp :: Frame -> Frame
expandUp = concatMap (\coarse -> [coarse, inventFrom coarse])

-- | The detail an S-level manufactures from a coarse cell (the @g x@ in @S f g x = f x (g x)@).
inventFrom :: Int -> Int
inventFrom coarse = coarse + 100

-- | The three canonical levels. Palettes are bijective recolours (length-preserving), so
--   every cardinality change is carried by the index (the structural move), as intended.
iLevel, kLevel, sLevel :: Level
iLevel = Level RoleI id          heldIndex   -- held: palette=id, index=id  => levelFn = id
kLevel = Level RoleK (map negate) poolDown   -- pool: discard detail (negate is just a bijective recolour)
sLevel = Level RoleS id          expandUp    -- invent: duplicate coarse, manufacture detail

-- | The twiceness: one rung is exactly TWO octree levels (levelsPerStep = 2).
levelsPerStep :: Int
levelsPerStep = 2

-- | One rung up = the level operator applied twice (x2 cells per level => x4 per rung).
rung :: Frame -> Frame
rung = levelFn sLevel . levelFn sLevel

-- | A demo stack mixing all three roles (depth d = 3).
demoStack :: [Level]
demoStack = [sLevel, iLevel, kLevel]

-- --- peeling: explore the stack one reduction at a time -------------------------------

-- | One peel = fire the INNERMOST (rightmost) level, the one @foldr (.) id@ applies first.
--   This reduces a d-stack to a (d-1)-stack, resolving one level of the render.
peelStep :: ([Level], Frame) -> Maybe ([Level], Frame)
peelStep ([], _)  = Nothing
peelStep (ls, fr) = Just (init ls, levelFn (last ls) fr)

-- | Apply 'peelStep' n times (bounded; stops early if the stack empties).
peelN :: Int -> ([Level], Frame) -> ([Level], Frame)
peelN n st
  | n <= 0    = st
  | otherwise = case peelStep st of
                  Just st' -> peelN (n - 1) st'
                  Nothing  -> st

-- ===========================================================================
-- (2b) LZW over an index string: the "compute" over the discrete content.
-- ===========================================================================
--
-- HONEST SCOPE. What is REAL and measured here: the LZW dictionary back-reference COUNT,
-- i.e. how many emitted codes point at a previously-built MULTI-symbol phrase. That is an
-- exact count of explicit phrase SHARING (a stored substring reused), and it is round-trip
-- verified (decode . encode == id, including the KwKwK decoder edge case).
--
-- What is SUGGESTIVE ONLY (NOT a checked axiom): reading each such reuse as "the S /
-- contraction structural move" (one phrase used in two places = duplication = sharing), and
-- "the growing dictionary IS the latent". LZW dictionary growth is structurally ANALOGOUS
-- to contraction/sharing, but it is NOT literally the SKI S-rule; so we keep only the COUNT
-- as load-bearing and label the combinator reading a suggestion. (Owner ask #2: the bridge
-- is intuition, the number is fact.)

-- | LZW encode a string of small-integer symbols. Alphabet = the sorted distinct symbols
--   (codes 0..|alphabet|-1); multi-symbol phrases take the next free codes as first seen.
--   Returns (emitted codes, final dictionary code->phrase).
lzwEncode :: [Int] -> ([Int], [(Int,[Int])])
lzwEncode [] = ([], [])
lzwEncode input = go initDict next0 [] input []
  where
    alpha    = sort (nub input)
    initDict = [ (i,[a]) | (i,a) <- zip [0..] alpha ]
    next0    = length alpha
    codeOf dict s = fst (head [ p | p@(_,str) <- dict, str == s ])
    go dict _    w []     acc = (reverse (codeOf dict w : acc), dict)
    go dict next w (c:cs) acc =
      let wc = w ++ [c] in
      if any ((== wc) . snd) dict
        then go dict next wc cs acc
        else go (dict ++ [(next,wc)]) (next + 1) [c] cs (codeOf dict w : acc)

-- | LZW decode, given the alphabet (sorted distinct symbols) and the codes. Returns the
--   decoded string AND a flag: did the KwKwK edge fire (a code referencing the entry being
--   defined THIS step, the classic LZW special case)? The flag keeps that branch honest
--   (a law asserts it is actually reached, i.e. not dead code).
lzwDecode :: [Int] -> [Int] -> ([Int], Bool)
lzwDecode _     []        = ([], False)
lzwDecode alpha (k0:rest) = go initDict (length alpha) first rest first False
  where
    initDict   = [ (i,[a]) | (i,a) <- zip [0..] alpha ]
    strOf d k  = head [ s | (i,s) <- d, i == k ]
    inDict d k = any ((== k) . fst) d
    first      = strOf initDict k0
    go _ _    _ []     out fired = (out, fired)
    go d next w (k:ks) out fired =
      let (entry, fired')
            | inDict d k = (strOf d k, fired)
            | k == next  = (w ++ [head w], True)        -- KwKwK edge: code defined this step
            | otherwise  = error "lzwDecode: bad code"
          d' = d ++ [(next, w ++ [head entry])]
      in go d' (next + 1) entry ks (out ++ entry) fired'

-- | The phrase-SHARING count: how many emitted codes reference a MULTI-symbol phrase
--   (length >= 2). This is the real, load-bearing quantity (see the section note).
reuseCount :: [Int] -> Int
reuseCount input =
  let (codes, dict) = lzwEncode input
  in length [ () | c <- codes, length (phraseOf dict c) >= 2 ]
  where phraseOf dict k = head [ s | (i,s) <- dict, i == k ]

-- ===========================================================================
-- (3) Laws (each a Bool, tested at the boundary with teeth)
-- ===========================================================================

-- | Sample frames (all non-empty; even and odd lengths to exercise poolDown).
samples :: [Frame]
samples = [[1,2,3,4], [5,6], [7,8,9,0], [2,2,2,2], [3,1,4,1,5]]

-- | The render of a d-level stack IS the nested application f1 (f2 (... (fd x))). We
--   exhibit d=2 and d=3 explicitly; the CONTENT (this fold identity is near-definitional)
--   is the TEETH: reversing the level order changes the render, so the nesting is genuine
--   and order-sensitive, not a commutative blend. <>
lawNestedRenderIsBStack :: Bool
lawNestedRenderIsBStack = and (twoLevel ++ threeLevel ++ orderTeeth)
  where
    twoLevel =
      [ renderStack [sLevel, kLevel] x == levelFn sLevel (levelFn kLevel x)
      | x <- samples ]
    threeLevel =
      [ renderStack [sLevel, iLevel, kLevel] x
          == levelFn sLevel (levelFn iLevel (levelFn kLevel x))
      | x <- samples ]
    -- TEETH: the stack is a NESTED composition, not order-free. Reverse it and it differs.
    orderTeeth =
      [ renderStack demoStack x /= renderStack (reverse demoStack) x
      | x <- samples ]

-- | Peeling the outermost-applied (innermost/rightmost) level is one reduction step. A
--   d-stack reaches normal form (empty stack) in EXACTLY d peels = the ponder depth.
--   INVARIANT: at every k, (remaining levels) applied to (current frame) == the final
--   render (the already-resolved part stays consistent). TEETH: peeling d-1 times leaves a
--   non-empty stack whose frame is NOT the final render (a wrong peel count = wrong residual).
lawPeelOneLevelIsOneStep :: Bool
lawPeelOneLevelIsOneStep = and (depthIsD ++ invariant ++ teeth)
  where
    d     = length demoStack
    final x = renderStack demoStack x
    -- d peels empty the stack and land exactly on the final render; d-1 do NOT empty it.
    depthIsD =
      [ let (rem', fr) = peelN d (demoStack, x)
        in null rem' && fr == final x | x <- samples ]
      ++ [ not (null (fst (peelN (d - 1) (demoStack, x)))) | x <- samples ]
      ++ [ d == length demoStack ]                       -- ponder depth = stack depth
    -- INVARIANT for every k in 0..d: resolved frame + remaining levels == final render.
    invariant =
      [ let (rem', fr) = peelN k (demoStack, x)
        in renderStack rem' fr == final x
      | x <- samples, k <- [0 .. d] ]
    -- TEETH: stop one peel short => still levels left AND frame /= final render.
    teeth =
      [ let (rem', fr) = peelN (d - 1) (demoStack, x)
        in not (null rem') && fr /= final x
      | x <- samples ]

-- | The roles match the expand/contract reading, at the boundary:
--     I  = identity on its band (value AND length preserved), a bijection;
--     K  = non-injective shrink (a collision witness proves information is lost),
--          and never increases length;
--     S  = the UNIQUE move that increases the distinct-output count / length.
--   TEETH: mislabelling S as I would claim invention is the identity (levelFn sLevel == id),
--   which is FALSE (the expanded frame differs from its input).
lawLevelRolesMatchExpandContract :: Bool
lawLevelRolesMatchExpandContract = and (iIsId ++ kLoses ++ sInvents ++ onlySincreases ++ teeth)
  where
    nonEmpty = samples
    -- I: identity on the band (so reversible: id is its own inverse), length preserved.
    iIsId =
      [ levelFn iLevel x == x | x <- samples ]
      ++ [ length (levelFn iLevel x) == length x | x <- samples ]
    -- K: a CONCRETE collision => two distinct inputs collapse to one output (info lost),
    --    and K never grows the band.
    kLoses =
      [ levelFn kLevel [1,2,3,4] == levelFn kLevel [1,9,3,8]   -- detail 2/9 and 4/8 discarded
      , ([1,2,3,4] :: [Int]) /= [1,9,3,8] ]
      ++ [ length (levelFn kLevel x) <= length x | x <- samples ]
    -- S: strictly increases both raw length and distinct-cell count (genuine invention).
    sInvents =
      [ length (levelFn sLevel x) > length x | x <- nonEmpty ]
      ++ [ length (nub (levelFn sLevel x)) > length (nub x) | x <- nonEmpty ]
    -- S is the ONLY role that can increase length: I and K never do.
    onlySincreases =
      [ not (length (levelFn iLevel x) > length x) | x <- samples ]
      ++ [ not (length (levelFn kLevel x) > length x) | x <- samples ]
    -- TEETH: claiming S is the held identity (S == I) is false.
    teeth = [ levelFn sLevel x /= x | x <- nonEmpty ]

-- | One rung is EXACTLY two levels (levelsPerStep = 2): @rung == level . level@, and one
--   rung scales the band by 4 (= two x2 levels). TEETH: a rung is NOT a single level
--   (length 4n /= 2n), so a stop-count off by one mis-sizes the band.
lawTwicenessIsTwoLevels :: Bool
lawTwicenessIsTwoLevels = and (isTwoCompose ++ scalesX4 ++ teeth ++ [levelsPerStep == 2])
  where
    isTwoCompose =
      [ rung x == levelFn sLevel (levelFn sLevel x) | x <- samples ]
      ++ [ renderStack [sLevel, sLevel] x == rung x | x <- samples ]   -- a 2-stack == the rung
    scalesX4 = [ length (rung x) == 4 * length x | x <- samples ]
    -- TEETH: a rung (2 levels) differs from a single level (4n vs 2n cells).
    teeth = [ length (rung x) /= length (levelFn sLevel x) | x <- samples, not (null x) ]

-- | The calculus witness for "a chain of B-compositions": @B f (B g h) x@ reduces to the
--   nested application @f (g (h x))@. This is the REAL content behind renderStack's fold.
lawBChainIsNesting :: Bool
lawBChainIsNesting = and (chains ++ orderTeeth)
  where
    quads  = [ (I,I,I,K), (K,I,I,S), (I,K,I, K # I), (S,K,I, I) ]
    chains = [ nf (b # f # (b # g # h) # x) == nf (f # (g # (h # x))) | (f,g,h,x) <- quads ]
    -- TEETH: the chain is a genuine NESTING, not order-blind, so the equality above is not
    -- a vacuous identity. Witness (I,K,S,I): the inner two functions do NOT commute, so the
    -- B-chain equals f(g(h x)) = K(S I) but DIFFERS from the swapped nesting f(h(g x)) =
    -- S(K I). If composition were order-free both would coincide; they do not.
    orderTeeth =
      let (f,g,h,x) = (I, K, S, I)
      in [ nf (b # f # (b # g # h) # x) == nf (f # (g # (h # x)))
         , nf (b # f # (b # g # h) # x) /= nf (f # (h # (g # x))) ]

-- | Confluence (Church-Rosser) on the chain terms: normal-order and inner-first reduction
--   reach the SAME normal form (mirrors GifSki; keeps the second reducer honest).
lawConfluence :: Bool
lawConfluence = and [ nf t == nfInner t | t <- terms ]
  where terms = [ b # I # (b # I # I) # K
                , b # K # I # S
                , S # K # K # I
                , b # S # K # (K # I) ]

-- | LZW reuse = explicit phrase SHARING, measured (Owner ask #2). REAL teeth:
--   (a) round-trip: decode (encode x) == x for the whole corpus, INCLUDING inputs that
--       drive the KwKwK decoder edge -- and that edge actually FIRES (not dead code);
--   (b) the SHARING <=> COMPRESSION invariant: the code stream is shorter than the input
--       IFF reuseCount > 0 (phrase sharing is the only thing that compresses);
--   (c) the discriminating TOOTH: [3,3] has a REPEATED SYMBOL yet reuseCount == 0, because
--       its 2-symbol phrase is built but never reused -- so the count measures phrase
--       SHARING, NOT mere symbol repetition (a naive "has a duplicate" metric would say 1);
--   (d) all-distinct strings share nothing (reuseCount == 0); a phrase-reusing string does
--       (reuseCount > 0); reuse is non-decreasing under more repetition and unbounded
--       (rep 5 strictly exceeds rep 2).
--   The "each reuse == an S / contraction move" reading is SUGGESTIVE only (section note). <>
lawLzwReuseIsSharingCount :: Bool
lawLzwReuseIsSharingCount =
  and (roundTrips ++ kwkwkLive ++ shareIffCompress ++ repeatNoShare ++ anchors ++ grows)
  where
    rep n  = concat (replicate n [0,1])
    corpus = [ [0,1,1,1], [0,1,2,3], [0,1,0,1,0,1], [5,5,5,5,5]
             , [1,2,1,2,1,2,1], [7], [3,3], rep 4 ]
    enc x  = fst (lzwEncode x)
    dec x  = lzwDecode (sort (nub x)) (enc x)
    -- (a) every input survives encode then decode unchanged.
    roundTrips = [ fst (dec x) == x | x <- corpus ]
    -- (a') the KwKwK branch is genuinely reached by at least one corpus input.
    kwkwkLive  = [ any (snd . dec) corpus ]
    -- (b) shorter code stream EXACTLY when some phrase is reused.
    shareIffCompress = [ (length (enc x) < length x) == (reuseCount x > 0) | x <- corpus ]
    -- (c) TOOTH: a repeated SYMBOL is not phrase sharing. [3,3] repeats yet shares nothing;
    --     nub [3,3] /= [3,3] confirms the repeat is real, so reuseCount==0 is discriminating.
    repeatNoShare = [ reuseCount [3,3] == 0, nub ([3,3] :: [Int]) /= [3,3] ]
    -- (d) anchors: distinct => no share; an obviously reused phrase => share.
    anchors = [ reuseCount [0,1,2,3] == 0, reuseCount [0,1,0,1,0,1] > 0 ]
    -- (d') non-decreasing under more repetition, and unbounded (rep 5 > rep 2).
    grows = [ reuseCount (rep n) <= reuseCount (rep (n + 1)) | n <- [2 .. 5] ]
            ++ [ reuseCount (rep 5) > reuseCount (rep 2) ]

-- ===========================================================================
-- (4) Runner
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawNestedRenderIsBStack  (foldr(.)id = f1(f2(f3 x)))", lawNestedRenderIsBStack)
  , ("lawPeelOneLevelIsOneStep (d peels to NF, depth = d)",  lawPeelOneLevelIsOneStep)
  , ("lawLevelRolesMatchEC     (I=id, K=lossy, S=invent)",   lawLevelRolesMatchExpandContract)
  , ("lawTwicenessIsTwoLevels  (rung = level . level)",      lawTwicenessIsTwoLevels)
  , ("lawBChainIsNesting       (B f (B g h) x = f(g(h x)))", lawBChainIsNesting)
  , ("lawConfluence            (two orders, one NF)",        lawConfluence)
  , ("lawLzwReuseIsSharing     (reuse=share, [3,3] tooth)",  lawLzwReuseIsSharingCount)
  ]

main :: IO ()
main = do
  putStrLn "V2SkiLevels.hs  -- EXPLORATION (NOT WIRED): the SKI level stack, explored by levels"
  putStrLn (replicate 72 '-')
  mapM_ (\(n,ok) -> putStrLn (verdict ok ++ "  " ++ n)) laws
  putStrLn (replicate 72 '-')
  let passed = length (filter snd laws)
      total  = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  let x0 = [1,2,3,4]
  putStrLn ("demo stack roles (top->bottom) = " ++ show (map lvRole demoStack)
            ++ "   depth d = " ++ show (length demoStack))
  putStrLn ("renderStack demoStack " ++ show x0 ++ " = " ++ show (renderStack demoStack x0))
  putStrLn ("peel trace (remaining roles, frame):")
  mapM_ (\k -> let (rem', fr) = peelN k (demoStack, x0)
               in putStrLn ("  peel " ++ show k ++ ": "
                            ++ "[" ++ intercalate "," (map (show . lvRole) rem') ++ "]  "
                            ++ show fr))
        [0 .. length demoStack]
  putStrLn ("one rung = " ++ show levelsPerStep ++ " levels: length "
            ++ show (length x0) ++ " -> " ++ show (length (rung x0)) ++ " (x4)")
  putStrLn ("B = S (K S) K = " ++ show b)
  let lzwIn = [0,1,1,1]
  putStrLn ("LZW " ++ show lzwIn ++ " -> codes " ++ show (fst (lzwEncode lzwIn))
            ++ "  reuse(share)=" ++ show (reuseCount lzwIn)
            ++ "  KwKwK fired=" ++ show (snd (lzwDecode (sort (nub lzwIn)) (fst (lzwEncode lzwIn))))
            ++ "  [3,3] reuse=" ++ show (reuseCount [3,3]) ++ " (repeat, no share)")
  putStrLn ""
  putStrLn "HONEST NOTE: the substructural grading is REAL (I=bijection, K=non-injective"
  putStrLn "weakening, S=cardinality-increasing contraction; checked with collision/length"
  putStrLn "teeth). lawNestedRenderIsBStack is near-definitional; its content is the"
  putStrLn "order tooth + lawBChainIsNesting (a B-chain really reduces to nested application)."
  putStrLn "The I/S/K NAMES are suggestive, not a claim that the octree is a rewrite system;"
  putStrLn "roles are seated on abstract bands, never on Red (the V2 I carrier is luma/(1,1,1))."
  putStrLn "LZW: the reuse COUNT is fact (round-trip + [3,3] tooth); 'reuse == S-contraction'"
  putStrLn "is a SUGGESTION only, not a checked axiom."
  where verdict True  = "PASS"
        verdict False = "FAIL"

-- Silence an unused-import warning if intercalate/nub are not used in some builds.
_unused :: String
_unused = intercalate "," (map show (nub ([] :: [Int])))
