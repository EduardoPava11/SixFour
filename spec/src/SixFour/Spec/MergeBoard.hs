{- |
Module      : SixFour.Spec.MergeBoard
Description : THE MERGE — the post-capture decision game, exact. 2048 inverted: the capture opens as the COARSE board (the 16-view, the calm high-energy whole) and the player DECOMPOSES large color into fine, spending banked signal — every accepted move is an S/K/I verb on a region of the 64² plane, and the ordered DECISION WORD is the training record. The board is a 4×4 partition of the plane at rung depths 0/1/2 (16/32/64, "SixFour.Spec.CubeBrush" depth vocabulary); a mixed board is a LEGAL render (the per-region scale choice "SixFour.Spec.RenderSelect" already draws); the goal is the fully-constructed 64-board, the honest ceiling.

== The three verbs (the moves ARE the combinators)

  * __S — split__: reveal one rung finer in a region. Costs signal, and the
    price is the S-tower price: 'splitCost' d = 2^d packets
    ('lawSplitCostIsSTower' — stacking another S doubles the references,
    "SixFour.Spec.WeaveOrder" @lawSTowerCostsExponential@). A split from
    depth 0 is the spatial-pair verb (@S_xy@), from depth 1 the full fine
    verb (@S_xyt@) — 'skiVerbOf', the "SixFour.Spec.AxisSKI" reading.
  * __K — merge back__: pool a region one rung coarser. K KEEPS: it never
    pays and never refunds ('lawKKeepsAndNeverPays') — mass is conserved,
    only the fine claim is withdrawn.
  * __I — hold__: the explicit no-op; free, always legal on the board.

== The pour economy (2048's "a new tile arrives each turn")

Signal arrives ONLY by replaying the capture's own burst in 4-frame slices:
one 'GPour' deposits 'pourDeposit' = 4 frame-units, at most 'pourCap' = 16
pours — exactly the window: @16 × 4 = 64 =@ 'windowUnits'
('lawEconomyIsTheWindow'). The ledger is exact: signal = deposits − spends,
never negative ('lawSignalLedgerConserved').

== The phase gate is ENERGY, and it demands real measurement

Splitting 32→64 unlocks only when the banked 32-evidence crosses one full
window: 'threshold32' = 'windowUnits'. Evidence banks where the board is
MEASURING when the slice lands — each pour credits 'pourDeposit' per region
at depth ≥ 1 — so the all-coarse board banks NOTHING toward the gate
('lawBankNeedsMeasurement'): you must commit S at 32 before the 64 rung can
open. That is the independent-rungs contract inside the game: evidence is
measured, never derived. Banked evidence never un-banks — K withdraws the
claim, not the measurement — so the unlock is monotone ('lawUnlockMonotone').

== The decision word is the whole state (the training-data guarantee)

Every ACCEPTED op — pours included — appends itself to the board's word;
every rejected op is a total no-op. Hence the KEYSTONE
'lawWordReplaysBoard': replaying a board's own word from 'initBoard'
reproduces the board EXACTLY, every field. The word is a faithful, ordered,
self-contained record — what ships in the @.s4cr@ (v3 @dw@ key,
"SixFour.Spec.CaptureRecord") and what "SixFour.Spec.ChoiceTraining" /
"SixFour.Spec.MixSKI" train on. And the order is REAL information the board
marginal cannot see: an S;K round-trip restores the depths but extends the
word and the spend ('lawOrderSurvivesCancellation') — the WeaveOrder lesson
(@lawOrderIsInvisibleToTheMeasure@) replayed at the game layer.

== Cost of victory

Full construction needs net +2 depth on all 16 regions: at least 32 S-moves,
at least 16×1 + 16×2 = 48 packets spent ('lawWinCostsTheLadder').
'canonicalConstruction' is the pinned tight run: 12 pours, 48 spent, ends at
signal 0 ('lawCanonicalRunConstructs') — the burst funds the whole game with
exactly four pours of slack for exploration.

== Honest boundary

Pure integer game algebra; totals by construction ('step' answers every op
with a 'Verdict'). Rendering of a board is delegated: the depth field is
constant on regions ('depthAtPixel', 'lawBoardPartitionsPlane' — every plane
pixel in exactly one region), and per-region scale rendering is
"SixFour.Spec.RenderSelect"'s landed law, referenced not re-proven. The
board partition never overlaps, so "SixFour.Spec.CubeBrush"'s finest-wins
semilattice is trivially satisfied; the canonical-cube-set realization is
CubeBrush's surjectivity law. GHC-boot-only.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.MergeBoard
  ( -- * The board — a 4×4 partition of the 64² plane at rung depths
    boardSide
  , regionCount
  , regionSide
  , planeSide
  , minDepth
  , maxDepth
  , Region
  , Depth
  , Board (..)
  , initBoard
  , depthAt
  , countAtLeast
  , fullyConstructed
    -- * Moves and verdicts
  , MoveOp (..)
  , GameOp (..)
  , Reject (..)
  , Verdict (..)
  , step
  , playAll
    -- * The pour economy and the S-tower price
  , pourDeposit
  , pourCap
  , splitCost
    -- * The energy gate (phase 2)
  , threshold32
  , phase2Unlocked
    -- * The SKI reading of a move
  , SkiVerb (..)
  , skiVerbOf
    -- * The plane partition (the render bridge)
  , regionOfPixel
  , depthAtPixel
    -- * The pinned tight construction
  , canonicalConstruction
    -- * Laws
  , lawInitIsCoarsest
  , lawEconomyIsTheWindow
  , lawSplitCostIsSTower
  , lawStepTotalAndRecorded
  , lawSignalLedgerConserved
  , lawDepthCeiling
  , lawUnlockMonotone
  , lawBankNeedsMeasurement
  , lawPhaseGateIsEnergy
  , lawKKeepsAndNeverPays
  , lawOrderSurvivesCancellation
  , lawWordReplaysBoard
  , lawBoardPartitionsPlane
  , lawWinCostsTheLadder
  , lawCanonicalRunConstructs
  ) where

import SixFour.Spec.WeaveOrder (windowUnits)

-- ─────────────────────────────────────────────────────────────────────────────
-- The board
-- ─────────────────────────────────────────────────────────────────────────────

-- | Regions per side: the board is 4×4 (2048's own board size, and the
-- quadtree branching of the 64² plane two levels above the region grain).
boardSide :: Int
boardSide = 4

-- | Total regions: 16.
regionCount :: Int
regionCount = boardSide * boardSide

-- | GIF pixels per region side: 64 / 4 = 16 — one region is a 16×16 px block.
regionSide :: Int
regionSide = planeSide `div` boardSide

-- | The spatial plane side of the honest ceiling: 64.
planeSide :: Int
planeSide = 64

-- | The coarsest depth (the 16-rung; "SixFour.Spec.CubeBrush" depth 0).
minDepth :: Int
minDepth = 0

-- | The finest depth (the 64-rung, the ceiling; CubeBrush depth 2).
maxDepth :: Int
maxDepth = 2

-- | A region index, raster order, @0 .. 'regionCount' − 1@.
type Region = Int

-- | A region's granularity: 0 = 16, 1 = 32, 2 = 64 (rung index k = 2 − depth).
type Depth = Int

-- | The whole game state. Everything is integer; 'bWord' is the ordered
-- record of every ACCEPTED op, oldest first — the decision word.
data Board = Board
  { bDepths :: [Depth]  -- ^ 'regionCount' entries, raster order
  , bSignal :: Int      -- ^ banked, unspent frame-units
  , bSpent  :: Int      -- ^ frame-units spent on splits (monotone)
  , bPours  :: Int      -- ^ pours ingested, @≤ 'pourCap'@
  , bBank32 :: Int      -- ^ banked 32-evidence frame-units (monotone)
  , bWord   :: [GameOp] -- ^ the decision word: accepted ops in order
  } deriving (Eq, Show)

-- | The opening board: all-coarse (the 16-view IS the launch view), zero
-- ledger, empty word. The first pour is the player's first move.
initBoard :: Board
initBoard = Board (replicate regionCount minDepth) 0 0 0 0 []

-- | The depth of one region (callers pass in-range regions; 'step' itself
-- rejects out-of-range ops with 'OffBoard' rather than calling this).
depthAt :: Board -> Region -> Depth
depthAt b r = bDepths b !! r

-- | How many regions sit at depth ≥ d — the pour's crediting count.
countAtLeast :: Depth -> Board -> Int
countAtLeast d b = length (filter (>= d) (bDepths b))

-- | The win: every region at the ceiling — the 64³ is constructed.
fullyConstructed :: Board -> Bool
fullyConstructed b = all (== maxDepth) (bDepths b)

-- ─────────────────────────────────────────────────────────────────────────────
-- Moves and verdicts
-- ─────────────────────────────────────────────────────────────────────────────

-- | The three verbs on a region.
data MoveOp = OpS | OpK | OpI
  deriving (Eq, Show, Enum, Bounded)

-- | One game op: bank a pour, or play a verb on a region.
data GameOp = GPour | GMove Region MoveOp
  deriving (Eq, Show)

-- | Why a move was refused (refusals are total no-ops, never recorded).
data Reject
  = OffBoard        -- ^ region index outside @0 .. regionCount−1@
  | AlreadyFinest   -- ^ S on a depth-2 region: the ceiling is honest
  | AlreadyCoarsest -- ^ K on a depth-0 region
  | PhaseLocked     -- ^ S from depth 1 before 'threshold32' is banked
  | NoSignal        -- ^ S without 'splitCost' banked
  | PoursExhausted  -- ^ pour past 'pourCap': the burst has no more slices
  deriving (Eq, Show)

-- | A move either happens (and is recorded) or is refused (and nothing
-- changes).
data Verdict = Accept | Rejected Reject
  deriving (Eq, Show)

-- | The total step. Guard order for S: ceiling, then phase, then price.
-- A pour credits 'bBank32' against the PRE-pour depths: evidence lands
-- where the board is measuring when the slice arrives.
step :: GameOp -> Board -> (Board, Verdict)
step op b = case op of
  GPour
    | bPours b >= pourCap -> refuse PoursExhausted
    | otherwise ->
        accept b { bSignal = bSignal b + pourDeposit
                 , bPours  = bPours b + 1
                 , bBank32 = bBank32 b + pourDeposit * countAtLeast 1 b
                 }
  GMove r mv
    | r < 0 || r >= regionCount -> refuse OffBoard
    | otherwise -> case mv of
        OpI -> accept b
        OpK
          | depthAt b r <= minDepth -> refuse AlreadyCoarsest
          | otherwise -> accept b { bDepths = setDepth r (depthAt b r - 1) b }
        OpS
          | depthAt b r >= maxDepth -> refuse AlreadyFinest
          | depthAt b r == 1 && not (phase2Unlocked b) -> refuse PhaseLocked
          | bSignal b < splitCost (depthAt b r) -> refuse NoSignal
          | otherwise ->
              accept b { bDepths = setDepth r (depthAt b r + 1) b
                       , bSignal = bSignal b - splitCost (depthAt b r)
                       , bSpent  = bSpent b + splitCost (depthAt b r)
                       }
  where
    refuse why = (b, Rejected why)
    accept b'  = (b' { bWord = bWord b' ++ [op] }, Accept)
    setDepth ri dNew bb = [ if i == ri then dNew else di
                          | (i, di) <- zip [0 ..] (bDepths bb) ]

-- | Fold a whole op list from 'initBoard' (refusals are no-ops by 'step').
playAll :: [GameOp] -> Board
playAll = foldl (\b op -> fst (step op b)) initBoard

-- ─────────────────────────────────────────────────────────────────────────────
-- The pour economy and the S-tower price
-- ─────────────────────────────────────────────────────────────────────────────

-- | Frame-units one pour deposits: 4 — one pour group, the 4-frame slice
-- (one 16-frame of color-time, "SixFour.Spec.WeaveOrder" @unitsOf W16@).
pourDeposit :: Int
pourDeposit = 4

-- | Pours per capture: 16 — the 64-frame burst in 4-frame slices.
pourCap :: Int
pourCap = 16

-- | The price of splitting FROM depth d: @2^d@ — stacking another S doubles
-- the substrate references (the S-tower price, WeaveOrder
-- @lawSTowerCostsExponential@). 16→32 costs 1, 32→64 costs 2.
splitCost :: Depth -> Int
splitCost d = 2 ^ max 0 d

-- ─────────────────────────────────────────────────────────────────────────────
-- The energy gate
-- ─────────────────────────────────────────────────────────────────────────────

-- | Banked 32-evidence that unlocks 32↔64: one full window of frame-units,
-- 'windowUnits' = 64. Not a count of regions — an energy account.
threshold32 :: Int
threshold32 = windowUnits

-- | Is the fine phase open? Monotone in the game history
-- ('lawUnlockMonotone': 'bBank32' never decreases).
phase2Unlocked :: Board -> Bool
phase2Unlocked b = bBank32 b >= threshold32

-- ─────────────────────────────────────────────────────────────────────────────
-- The SKI reading
-- ─────────────────────────────────────────────────────────────────────────────

-- | The axis-graded name a move wears in the UI and the record
-- ("SixFour.Spec.AxisSKI" vocabulary; v2 axis-swipes refine S to
-- single-axis verbs).
data SkiVerb = VerbSxy | VerbSxyt | VerbKt | VerbHold
  deriving (Eq, Show, Enum, Bounded)

-- | Name a verb played from a depth: S from 0 reveals the spatial pair
-- (@S_xy@), S from 1 the full fine cell (@S_xyt@); K pools back along the
-- ladder (@K_t@); I holds.
skiVerbOf :: MoveOp -> Depth -> SkiVerb
skiVerbOf OpS d = if d <= 0 then VerbSxy else VerbSxyt
skiVerbOf OpK _ = VerbKt
skiVerbOf OpI _ = VerbHold

-- ─────────────────────────────────────────────────────────────────────────────
-- The plane partition
-- ─────────────────────────────────────────────────────────────────────────────

-- | The region owning a plane pixel: raster blocks of 'regionSide'.
regionOfPixel :: (Int, Int) -> Region
regionOfPixel (x, y) = (y `div` regionSide) * boardSide + (x `div` regionSide)

-- | The board's depth field on the plane — constant on regions; this is the
-- per-region scale field "SixFour.Spec.RenderSelect" renders.
depthAtPixel :: Board -> (Int, Int) -> Depth
depthAtPixel b p = depthAt b (regionOfPixel p)

-- ─────────────────────────────────────────────────────────────────────────────
-- The pinned tight construction
-- ─────────────────────────────────────────────────────────────────────────────

-- | The tight full-construction run: pour once, open four regions at 32,
-- bank the threshold in four pours, open the rest, fund the fine phase in
-- seven pours, construct. 12 pours, 48 spent, ends at signal 0 — four pours
-- of slack remain for exploration ('lawCanonicalRunConstructs').
canonicalConstruction :: [GameOp]
canonicalConstruction =
     [GPour]
  ++ [ GMove r OpS | r <- [0 .. 3] ]
  ++ replicate 4 GPour
  ++ [ GMove r OpS | r <- [4 .. regionCount - 1] ]
  ++ replicate 7 GPour
  ++ [ GMove r OpS | r <- [0 .. regionCount - 1] ]

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws
-- ─────────────────────────────────────────────────────────────────────────────

-- | The opening board is the coarse whole: all regions at 'minDepth', empty
-- ledger, empty word.
lawInitIsCoarsest :: Bool
lawInitIsCoarsest =
     bDepths initBoard == replicate regionCount minDepth
  && bSignal initBoard == 0
  && bSpent initBoard == 0
  && bPours initBoard == 0
  && bBank32 initBoard == 0
  && null (bWord initBoard)

-- | The economy IS the window: the pours deliver exactly 'windowUnits'
-- (@16 × 4 = 64@), and the phase gate demands exactly one window of banked
-- 32-evidence.
lawEconomyIsTheWindow :: Bool
lawEconomyIsTheWindow =
     pourCap * pourDeposit == windowUnits
  && threshold32 == windowUnits

-- | The split price is the S-tower price: @2^d@ — 1 packet to open 32,
-- 2 to open 64.
lawSplitCostIsSTower :: Bool
lawSplitCostIsSTower = splitCost 0 == 1 && splitCost 1 == 2

-- | 'step' is total and the record is exact: along ANY op list, an accepted
-- op changes the board and appends EXACTLY itself to the word; a rejected
-- op changes NOTHING (the whole board, word included).
lawStepTotalAndRecorded :: [GameOp] -> Bool
lawStepTotalAndRecorded ops = go initBoard ops
  where
    go _ [] = True
    go b (op : rest) =
      let (b', v) = step op b
      in case v of
           Accept     -> bWord b' == bWord b ++ [op] && go b' rest
           Rejected _ -> b' == b && go b' rest

-- | The signal ledger is exact on every reachable board: signal =
-- deposits − spends, non-negative, pours capped.
lawSignalLedgerConserved :: [GameOp] -> Bool
lawSignalLedgerConserved ops =
  let b = playAll ops
  in bSignal b == pourDeposit * bPours b - bSpent b
     && bSignal b >= 0
     && bPours b <= pourCap

-- | No reachable board escapes the ladder: every depth in
-- @['minDepth' .. 'maxDepth']@ — the 64 ceiling is honest by construction.
lawDepthCeiling :: [GameOp] -> Bool
lawDepthCeiling ops =
  all (\d -> d >= minDepth && d <= maxDepth) (bDepths (playAll ops))

-- | Banked evidence never un-banks: 'bBank32' is non-decreasing along any
-- op list (K withdraws the fine CLAIM, not the measurement) — so the phase
-- unlock is monotone.
lawUnlockMonotone :: [GameOp] -> Bool
lawUnlockMonotone ops = go initBoard ops
  where
    go _ [] = True
    go b (op : rest) =
      let b' = fst (step op b)
      in bBank32 b' >= bBank32 b && go b' rest

-- | The all-coarse board banks NOTHING: n pours on 'initBoard' leave
-- 'bBank32' at 0 — the gate cannot be met without first MEASURING at 32
-- (commit S, then pour). Evidence is measured, never derived.
lawBankNeedsMeasurement :: Int -> Bool
lawBankNeedsMeasurement n =
  bBank32 (playAll (replicate (max 0 n) GPour)) == 0

-- | The 32→64 gate is exactly the energy account: on any reachable board,
-- an S from depth 1 is accepted iff the window is banked AND the price is
-- funded — and each refusal names the missing quantity.
lawPhaseGateIsEnergy :: [GameOp] -> Region -> Bool
lawPhaseGateIsEnergy ops r0 =
  let b = playAll ops
      r = abs r0 `mod` regionCount
      (b', v) = step (GMove r OpS) b
  in case (depthAt b r, phase2Unlocked b) of
       (1, False) -> v == Rejected PhaseLocked && b' == b
       (1, True)
         | bSignal b >= splitCost 1 -> v == Accept && depthAt b' r == 2
         | otherwise                -> v == Rejected NoSignal
       _ -> True

-- | K keeps and never pays: a legal K decrements ONLY the region's depth —
-- signal, spend, pours and banked evidence are all untouched.
lawKKeepsAndNeverPays :: [GameOp] -> Region -> Bool
lawKKeepsAndNeverPays ops r0 =
  let b = playAll ops
      r = abs r0 `mod` regionCount
      (b', v) = step (GMove r OpK) b
  in if depthAt b r <= minDepth
       then v == Rejected AlreadyCoarsest && b' == b
       else v == Accept
            && depthAt b' r == depthAt b r - 1
            && bSignal b' == bSignal b
            && bSpent b' == bSpent b
            && bPours b' == bPours b
            && bBank32 b' == bBank32 b

-- | The measure forgets, the record remembers: where an S;K round-trip on
-- one region is legal, the depths RETURN — but the word grew by both ops
-- and the spend kept the price. Order is real information the board
-- marginal cannot see (the WeaveOrder lesson, replayed).
lawOrderSurvivesCancellation :: [GameOp] -> Region -> Bool
lawOrderSurvivesCancellation ops r0 =
  let b = playAll ops
      r = abs r0 `mod` regionCount
      (b1, v1) = step (GMove r OpS) b
      (b2, v2) = step (GMove r OpK) b1
  in (v1 /= Accept)
     || (v2 == Accept
         && bDepths b2 == bDepths b
         && bWord b2 == bWord b ++ [GMove r OpS, GMove r OpK]
         && bSpent b2 == bSpent b + splitCost (depthAt b r))

-- | KEYSTONE — the decision word is the whole state: replaying a board's
-- own word from 'initBoard' reproduces the board exactly, every field.
-- (Refusals are total no-ops, so the accepted subsequence alone passes
-- through the same states.) This is the training-data guarantee behind the
-- @.s4cr@ v3 @dw@ key.
lawWordReplaysBoard :: [GameOp] -> Bool
lawWordReplaysBoard ops =
  let b = playAll ops
  in playAll (bWord b) == b

-- | The board partitions the plane: every pixel of the 64² falls in exactly
-- one region, regions are 'regionSide'-square raster blocks, and the block
-- count is 'regionCount' — the field 'depthAtPixel' hands
-- "SixFour.Spec.RenderSelect" is total and unambiguous.
lawBoardPartitionsPlane :: Bool
lawBoardPartitionsPlane =
     all inRange pixels
  && all agreesWithBlockMath pixels
  && length pixels == planeSide * planeSide
  && regionCount * regionSide * regionSide == planeSide * planeSide
  where
    pixels = [ (x, y) | y <- [0 .. planeSide - 1], x <- [0 .. planeSide - 1] ]
    inRange p = regionOfPixel p >= 0 && regionOfPixel p < regionCount
    agreesWithBlockMath (x, y) =
      regionOfPixel (x, y)
        == regionOfPixel (x - x `mod` regionSide, y - y `mod` regionSide)

-- | Victory has a floor price: any fully-constructed reachable board holds
-- at least 32 S-entries in its word, at least 48 packets spent
-- (16 × 1 + 16 × 2), and the banked window.
lawWinCostsTheLadder :: [GameOp] -> Bool
lawWinCostsTheLadder ops =
  let b = playAll ops
      sCount = length [ () | GMove _ OpS <- bWord b ]
  in not (fullyConstructed b)
     || (sCount >= 2 * regionCount
         && bSpent b >= regionCount * (splitCost 0 + splitCost 1)
         && bBank32 b >= threshold32)

-- | The pinned tight run: 'canonicalConstruction' fully constructs with 12
-- pours and 48 spent, ending at signal 0 — and every one of its ops was
-- accepted (its word is itself).
lawCanonicalRunConstructs :: Bool
lawCanonicalRunConstructs =
  let b = playAll canonicalConstruction
  in fullyConstructed b
     && bWord b == canonicalConstruction
     && bPours b == 12
     && bSpent b == 48
     && bSignal b == 0
