{- |
Module      : SixFour.Spec.PaletteSearch
Description : The KEYSTONE — AlphaGo-style search over global-palette candidates.

The look-NN proposes a global palette; this module is the SEARCH that turns a
proposal into a SET of diverse candidates (the AlphaGo/KataGo lesson: a strong
net gives one answer; the search generates the options). See docs/SIXFOUR-VISION.md.

DESIGN (the honest ADT model):
- The search is parametrized over an ABSTRACT 'Oracle' (policy + value). The
  look-NN is untrained, so the search must not depend on it; a deterministic
  'stubOracle' validates the mechanics in GHCi / QuickCheck.
- A 'SearchState' is a COMPLETE candidate palette — a 'HaarPalette' (always
  'wellFormed'); every state reconstructs to 256 leaves. (No partial trees.)
- A 'Move' perturbs one Haar coefficient by a delta. It is LOSSLESS and
  REVERSIBLE ('invertMove'), and preserves 'wellFormed' (it only changes a value,
  never the structure).
- The 'SearchTree' is a PERSISTENT rose tree. 'mctsStep' descends by PUCT, expands
  + evaluates a leaf, and BACKS UP by returning an updated tree (children commit).
  Pure; an explicit 'Seed' is threaded (no IO) so the search is reproducible.
- Selection is real PUCT: @Q + c·P·√N/(1+n)@. @c = 0@ ⇒ pure exploitation;
  raising @c@ (or the policy prior) ⇒ exploration. Determinism by seeded tie-break.
- 'extractGallery' picks @k@ DIVERSE candidates via 'Preference.greedyGallery' over
  fixed-length (768) OKLab embeddings — the diverse option set the user swipes.

Reuse: 'PairTree' (HaarPalette / reconstruct / analyze / wellFormed — the lossless
move grammar), 'Preference.greedyGallery' (DPP diverse selection), 'Diversity'
(a deterministic value metric for the stub). GHC-boot deps only.
-}
module SixFour.Spec.PaletteSearch
  ( -- * Abstract oracle (policy + value); the NN plugs in here
    Oracle(..)
    -- * States and moves
  , SearchState
  , Move(..)
  , applyMove
  , invertMove
    -- * The persistent search tree
  , SearchTree(..)
  , leafNode
  , meanValue
  , subtreeVisits
    -- * Selection / iteration / halting
  , Hyperparams(..)
  , defaultHyperparams
  , puct
  , childrenFromPolicy
  , mctsStep
  , Halting(..)
  , runSearch
    -- * The diverse option set
  , Gallery(..)
  , paletteEmbedding
  , extractGallery
    -- * Deterministic RNG
  , Seed
  , stepSeed
    -- * A deterministic oracle for GHCi / tests
  , stubOracle
    -- * Laws (predicates; QuickCheck'd in Properties.PaletteSearch)
  , lawMoveRoundTrip
  , lawMovePreservesWellFormed
  , lawPuctExploitLimit
  , lawBackupCountsVisits
  , lawDeterministic
  , lawGalleryBounded
  ) where

import Data.List (foldl', maximumBy)
import Data.Ord  (comparing)

import SixFour.Spec.Color      (OKLab(..))
import SixFour.Spec.PairTree   (HaarPalette(..), reconstruct, wellFormed, treeDepth)
import SixFour.Spec.Preference (Embedding, greedyGallery)
import SixFour.Spec.Diversity  (gaussianColorEntropy)

-- ---------------------------------------------------------------------------
-- OKLab + list helpers (local; PairTree does not export its vector ops)
-- ---------------------------------------------------------------------------

-- | Componentwise sum of two OKLab triples (local; PairTree's vector ops aren't exported).
addOK :: OKLab -> OKLab -> OKLab
addOK (OKLab l a b) (OKLab l' a' b') = OKLab (l + l') (a + a') (b + b')

-- | Componentwise negation of an OKLab triple.
negOK :: OKLab -> OKLab
negOK (OKLab l a b) = OKLab (negate l) (negate a) (negate b)

-- | ε-approximate palette equality. A move round-trip (add δ then −δ) is exact in
-- ℝ but only ε-close in IEEE 'Double' (@x + 0.1 − 0.1 ≠ x@), so the round-trip law
-- compares within a tolerance rather than with @==@.
haarClose :: Double -> HaarPalette -> HaarPalette -> Bool
haarClose eps (HaarPalette r1 l1) (HaarPalette r2 l2) =
  okClose r1 r2 && length l1 == length l2 && and (zipWith levelClose l1 l2)
  where
    okClose (OKLab a b c) (OKLab a' b' c') =
      abs (a - a') < eps && abs (b - b') < eps && abs (c - c') < eps
    levelClose xs ys = length xs == length ys && and (zipWith okClose xs ys)

-- | Apply @f@ to the element at @i@; identity if out of range (total).
modifyAt :: Int -> (a -> a) -> [a] -> [a]
modifyAt i f xs
  | i < 0 || i >= length xs = xs
  | otherwise = [ if j == i then f x else x | (j, x) <- zip [0 ..] xs ]

-- | Replace the element at @i@; identity if out of range (total).
setAt :: Int -> a -> [a] -> [a]
setAt i v = modifyAt i (const v)

-- ---------------------------------------------------------------------------
-- States and moves
-- ---------------------------------------------------------------------------

-- | A search state is a COMPLETE candidate palette (a Haar pyramid).
type SearchState = HaarPalette

-- | A move perturbs the offset at @(mvLevel, mvIndex)@ by @mvDelta@. Reversible
-- (see 'invertMove'), lossless, and 'wellFormed'-preserving (it changes a value,
-- not the structure). Out-of-range targets act as the identity (totality).
data Move = Move
  { mvLevel :: Int
  , mvIndex :: Int
  , mvDelta :: OKLab
  } deriving (Eq, Show)

-- | Apply a 'Move' to a 'SearchState' — the deterministic state transition the search explores.
applyMove :: Move -> SearchState -> SearchState
applyMove (Move lv ix d) (HaarPalette rt lvls) =
  HaarPalette rt (modifyAt lv (modifyAt ix (addOK d)) lvls)

-- | The inverse perturbation. @applyMove (invertMove m) . applyMove m == id@.
invertMove :: Move -> Move
invertMove m = m { mvDelta = negOK (mvDelta m) }

-- ---------------------------------------------------------------------------
-- The abstract oracle (the NN's interface; never depended on directly)
-- ---------------------------------------------------------------------------

-- | Policy (moves with priors) + value. NO 'Show' — it carries functions.
data Oracle = Oracle
  { oPolicy :: SearchState -> [(Move, Double)]   -- ^ proposed moves + priors P(a|s)
  , oValue  :: SearchState -> Double             -- ^ value / reward V(s)
  }

-- ---------------------------------------------------------------------------
-- The persistent search tree
-- ---------------------------------------------------------------------------

-- | An MCTS node: the palette state it stands for, its visit count, accumulated value, and children.
data SearchTree = SearchTree
  { stState    :: SearchState
  , stVisits   :: Int
  , stValueSum :: Double
  , stPrior    :: Double               -- ^ policy prior of the move that reached here
  , stChildren :: [(Move, SearchTree)] -- ^ committed children; [] until expanded
  , stExpanded :: Bool
  } deriving (Eq, Show)

-- | A fresh leaf 'SearchTree' node holding a state and its initial (prior) value, no children yet.
leafNode :: Double -> SearchState -> SearchTree
leafNode p s = SearchTree s 0 0 p [] False

-- | The backed-up mean value of a 'SearchTree' node (total value / visit count).
meanValue :: SearchTree -> Double
meanValue t
  | stVisits t == 0 = 0
  | otherwise       = stValueSum t / fromIntegral (stVisits t)

-- | Total visits in a subtree (root + all descendants) — for the backup law.
subtreeVisits :: SearchTree -> Int
subtreeVisits t = stVisits t + sum [ subtreeVisits c | (_, c) <- stChildren t ]

-- ---------------------------------------------------------------------------
-- Selection (PUCT), iteration, halting
-- ---------------------------------------------------------------------------

-- | The search's tunable knobs (PUCT exploration constant, budgets, …).
data Hyperparams = Hyperparams
  { hpC :: Double   -- ^ PUCT exploration constant. 0 ⇒ pure exploitation.
  } deriving (Eq, Show)

-- | The default MCTS hyperparameters (exploration constant, rollout budget, …).
defaultHyperparams :: Hyperparams
defaultHyperparams = Hyperparams 1.4

-- | PUCT score of a child given the parent's visit count.
-- @Q(child) + c · P(child) · √N(parent) / (1 + n(child))@.
puct :: Hyperparams -> Int -> SearchTree -> Double
puct hp parentN child =
  meanValue child
    + hpC hp * stPrior child * sqrt (fromIntegral parentN) / (1 + fromIntegral (stVisits child))

-- | Expand a state into committed children via the oracle's policy.
childrenFromPolicy :: Oracle -> SearchState -> [(Move, SearchTree)]
childrenFromPolicy o s = [ (m, leafNode p (applyMove m s)) | (m, p) <- oPolicy o s ]

-- | One MCTS iteration over the persistent tree: descend by PUCT to a leaf,
-- expand + evaluate it, and back the value up — returning the updated tree, the
-- leaf value, and the advanced seed. Pure and deterministic.
mctsStep :: Oracle -> Hyperparams -> Seed -> SearchTree -> (SearchTree, Double, Seed)
mctsStep o hp seed t
  | not (stExpanded t) =
      -- Leaf: expand (commit children) + evaluate, count this visit.
      let kids = childrenFromPolicy o (stState t)
          v    = oValue o (stState t)
      in ( t { stChildren = kids
             , stExpanded = True
             , stVisits   = stVisits t + 1
             , stValueSum = stValueSum t + v }
         , v, seed )
  | null (stChildren t) =
      -- Terminal (policy proposed nothing): re-evaluate, count the visit.
      let v = oValue o (stState t)
      in (t { stVisits = stVisits t + 1, stValueSum = stValueSum t + v }, v, seed)
  | otherwise =
      -- Internal: select the best child by PUCT (seed breaks ties), recurse, back up.
      let parentN     = stVisits t
          scored      = [ (puct hp parentN c, i) | (i, (_, c)) <- zip [0 ..] (stChildren t) ]
          (bestI, sd) = argmaxWithSeed scored seed
          (mv, child) = stChildren t !! bestI
          (child', v, sd') = mctsStep o hp sd child
          kids'       = setAt bestI (mv, child') (stChildren t)
      in ( t { stChildren = kids'
             , stVisits   = stVisits t + 1
             , stValueSum = stValueSum t + v }
         , v, sd' )

-- | Argmax over (score, index); ties broken deterministically by the seed.
argmaxWithSeed :: [(Double, Int)] -> Seed -> (Int, Seed)
argmaxWithSeed scored seed =
  let best      = fst (maximumBy (comparing fst) scored)
      tied      = [ i | (s, i) <- scored, s == best ]
      seed'     = stepSeed seed
      pick      = tied !! (seed' `mod` max 1 (length tied))
  in (pick, seed')

-- | The stopping rule for a search run.
data Halting
  = HaltOnVisits Int     -- ^ stop after N root iterations
  | HaltOnValue Double   -- ^ stop once the root mean value reaches the threshold
  deriving (Eq, Show)

-- | Run the search from a root state to the halting condition.
runSearch :: Oracle -> Hyperparams -> Halting -> Seed -> SearchTree -> SearchTree
runSearch o hp halt seed0 root0 = go seed0 root0 (budget halt)
  where
    budget (HaltOnVisits n) = n
    budget (HaltOnValue _)  = 100000   -- safety bound; value halting checks below
    go _ t 0 = t
    go seed t k =
      case halt of
        HaltOnValue thr | meanValue t >= thr && stVisits t > 0 -> t
        _ -> let (t', _, seed') = mctsStep o hp seed t in go seed' t' (k - 1)

-- ---------------------------------------------------------------------------
-- The diverse option set (DPP gallery)
-- ---------------------------------------------------------------------------

-- | A diversity-curated set of high-value palette states surfaced for the user to pick from.
data Gallery = Gallery
  { galStates :: [SearchState]
  , galValues :: [Double]
  } deriving (Eq, Show)

-- | Fixed-length embedding of a palette: its 256 reconstructed leaves flattened
-- to @3·256 = 768@ reals. All states are complete, so this is always 768-D.
paletteEmbedding :: SearchState -> Embedding
paletteEmbedding s = concatMap (\(OKLab l a b) -> [l, a, b]) (reconstruct s)

-- | All nodes of the tree (root first), each a distinct candidate palette.
allNodes :: SearchTree -> [SearchTree]
allNodes t = t : concat [ allNodes c | (_, c) <- stChildren t ]

-- | Pick @k@ DIVERSE, high-value candidates via the DPP greedy gallery
-- ('Preference.greedyGallery'): quality = node mean value, embedding = the 768-D
-- palette vector, @alpha@ = quality weight, @ell@ = RBF length scale.
extractGallery :: Int -> Double -> Double -> SearchTree -> Gallery
extractGallery k alpha ell t =
  let nodes = filter ((> 0) . stVisits) (allNodes t)   -- only EVALUATED candidates
      items = [ (meanValue n, paletteEmbedding (stState n)) | n <- nodes ]
      idxs  = greedyGallery k alpha ell items
  in Gallery [ stState (nodes !! i) | i <- idxs ]
             [ meanValue (nodes !! i) | i <- idxs ]

-- ---------------------------------------------------------------------------
-- Deterministic RNG (LCG) — no IO, reproducible by seed
-- ---------------------------------------------------------------------------

-- | The deterministic RNG state threaded through rollouts (advanced by 'stepSeed').
type Seed = Int

-- | Advance the deterministic RNG seed one step (the reproducible rollout randomness).
stepSeed :: Seed -> Seed
stepSeed s = (1103515245 * s + 12345) `mod` 2147483648

-- ---------------------------------------------------------------------------
-- A deterministic stub oracle (uniform policy + a real diversity value)
-- ---------------------------------------------------------------------------

-- | A deterministic oracle for GHCi / tests: it proposes a small fixed set of
-- coefficient perturbations (uniform priors) and values a palette by its OKLab
-- colour entropy (a real, deterministic diversity metric). No NN, no IO.
stubOracle :: Oracle
stubOracle = Oracle
  { oPolicy = \s ->
      let d  = max 1 (treeDepth s)
          ms = [ Move lv 0 (OKLab dl da db)
               | lv <- [0 .. min 2 (d - 1)]
               , (dl, da, db) <- [(0.05, 0, 0), (-0.05, 0, 0), (0, 0.05, 0), (0, 0, 0.05)] ]
          p  = 1 / fromIntegral (length ms)
      in [ (m, p) | m <- ms ]
  , oValue = \s ->
      let cols = reconstruct s
          ws   = replicate (length cols) (1 / fromIntegral (length cols))
      in gaussianColorEntropy cols ws
  }

-- ---------------------------------------------------------------------------
-- Laws (predicates; exercised by Properties.PaletteSearch)
-- ---------------------------------------------------------------------------

-- | A move composed with its inverse is the identity (lossless, reversible).
lawMoveRoundTrip :: Move -> SearchState -> Bool
lawMoveRoundTrip m s = haarClose 1e-9 (applyMove (invertMove m) (applyMove m s)) s

-- | A move preserves well-formedness (structure unchanged; only a value moves).
lawMovePreservesWellFormed :: Move -> SearchState -> Bool
lawMovePreservesWellFormed m s = wellFormed s == wellFormed (applyMove m s)

-- | At @c = 0@ PUCT reduces to pure exploitation (= the child's mean value).
lawPuctExploitLimit :: Int -> SearchTree -> Bool
lawPuctExploitLimit parentN child =
  puct (Hyperparams 0) parentN child == meanValue child

-- | After @n@ root iterations the root has been visited exactly @n@ times.
lawBackupCountsVisits :: Oracle -> Int -> Seed -> SearchTree -> Bool
lawBackupCountsVisits o n seed tree =
  n < 0 || stVisits (runSearch o defaultHyperparams (HaltOnVisits n) seed tree) == n + stVisits tree

-- | Same seed ⇒ identical search tree (no IO; reproducible).
lawDeterministic :: Oracle -> Int -> Seed -> SearchTree -> Bool
lawDeterministic o n seed tree =
  let r = runSearch o defaultHyperparams (HaltOnVisits (max 0 n)) seed tree
  in r == runSearch o defaultHyperparams (HaltOnVisits (max 0 n)) seed tree

-- | The gallery never returns more than @k@ options.
lawGalleryBounded :: Int -> SearchTree -> Bool
lawGalleryBounded k t = length (galStates (extractGallery k 1.0 0.5 t)) <= max 0 k
