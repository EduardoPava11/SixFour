{- |
Module      : SixFour.Spec.OctreeForward
Description : The capstone FSM — capture -> surface (one 16^3) + held remainder -> refine -> commit, composing the octree pillars as ONE contract.

Makes the octree scaffold act as one thing. A 'Session' carries the
successive-refinement split ("SixFour.Spec.SuccessiveRefinement"): the SURFACED
cube shown to the user plus the HELD remainder kept latent. The FSM:

  * 'surface'   : a @8^d@ capture is split at a cut depth into @(surfaced, held)@.
    The product cut is FIXED: 64^3 capture (d=6) -> 16^3 surfaced (cut=2 levels),
    held = the 2 detail levels. (Spec tests use tiny depths.)
  * 'refineOne' : show one finer level (move the finest held band into the
    surfaced cube) — losslessly, the capture is preserved.
  * 'commit'    : freeze the current surfaced look as the shipped GIF (the terminal
    that re-enters the Zig Q16 floor).

Every law DELEGATES to an already-proven one (SuccessiveRefinement / OctreeGenome),
so this module only proves that the COMPOSITION preserves them — the capture is
never lost, the surfaced is the right rung, and commit changes nothing but phase.

The search/gesture transitions (PUCT over "SixFour.Spec.OptionTree", chroma turns
via "SixFour.Spec.ChromaRotation", VoI halt via "SixFour.Spec.ScalePonder") layer
on top; the off-spec pieces (VoI thresholds, the JEPA latent remainder) are
trainer-side.

GHC-boot-only. Laws QuickCheck'd in @Properties.OctreeForward@.
-}
module SixFour.Spec.OctreeForward
  ( -- * The session FSM
    Phase(..)
  , Session(..)
  , surface
  , surfacedCube
  , heldRemainder
  , currentCut
  , refineSession
    -- * Transitions
  , refineOne
  , commit
    -- * Laws (QuickCheck'd in @Properties.OctreeForward@)
  , lawSurfaceLossless
  , lawSurfacedIsRung
  , lawRefineOneLossless
  , lawRefineOneShrinksHeld
  , lawCommitPreservesCapture
  , lawCommitIdempotent
  ) where

import SixFour.Spec.OctreeCell           (Detail)
import SixFour.Spec.SuccessiveRefinement (SurfacedSplit(..), split, refine, surfaced, held)
import SixFour.Spec.OctreeGenome         (octreeLeafCount)

-- | The capstone FSM phase.
data Phase = Surfaced | Committed deriving (Eq, Show)

-- | A session: the successive-refinement split, the full capture depth, and the phase.
data Session = Session
  { seSplit :: SurfacedSplit
  , seDepth :: Int
  , sePhase :: Phase
  } deriving (Eq, Show)

-- | Valid input: a @8^d@ capture and a cut @0 <= cut <= d@.
validInput :: Int -> Int -> [Int] -> Bool
validInput cut d cap = d >= 0 && cut >= 0 && cut <= d && length cap == octreeLeafCount d

-- | Capture -> session: split the @8^d@ capture at @cut@ levels into surfaced + held.
surface :: Int -> Int -> [Int] -> Session
surface cut d cap = Session (split cut d cap) d Surfaced

-- | The shown surfaced cube (the @16^3@ at the product cut).
surfacedCube :: Session -> [Int]
surfacedCube = surfaced . seSplit

-- | The held latent remainder (detail bands above the cut).
heldRemainder :: Session -> [[Detail]]
heldRemainder = held . seSplit

-- | How many levels are currently held (the cut depth).
currentCut :: Session -> Int
currentCut = length . held . seSplit

-- | Reconstruct the full capture from the session (surfaced + held), lossless.
refineSession :: Session -> [Int]
refineSession s = refine (seDepth s) (seSplit s)

-- | Show one finer level: move the finest held band into the surfaced cube. The
-- capture is preserved (re-split one level shallower). No-op when nothing is held.
refineOne :: Session -> Session
refineOne s =
  let k = currentCut s
  in if k <= 0 then s else surface (k - 1) (seDepth s) (refineSession s)

-- | Commit the current surfaced look as the shipped terminal (changes only phase).
commit :: Session -> Session
commit s = s { sePhase = Committed }

-- | Surface is lossless: surfaced + held reconstructs the capture
-- (delegates @SuccessiveRefinement.lawRefineRoundTrip@).
lawSurfaceLossless :: Int -> Int -> [Int] -> Bool
lawSurfaceLossless cut d cap =
  not (validInput cut d cap) || refineSession (surface cut d cap) == take (octreeLeafCount d) cap

-- | The surfaced cube is the @8^(d-cut)@ rung (the @16^3@ at the product cut)
-- (delegates @OctreeGenome.octreeLeafCount@).
lawSurfacedIsRung :: Int -> Int -> [Int] -> Bool
lawSurfacedIsRung cut d cap =
  not (validInput cut d cap) || length (surfacedCube (surface cut d cap)) == octreeLeafCount (d - cut)

-- | Refining one level preserves the capture (still lossless).
lawRefineOneLossless :: Int -> Int -> [Int] -> Bool
lawRefineOneLossless cut d cap =
  not (validInput cut d cap) || refineSession (refineOne (surface cut d cap)) == take (octreeLeafCount d) cap

-- | Refining one level shows one finer band: the held cut drops by one.
lawRefineOneShrinksHeld :: Int -> Int -> [Int] -> Bool
lawRefineOneShrinksHeld cut d cap =
  not (validInput cut d cap && cut > 0) || currentCut (refineOne (surface cut d cap)) == cut - 1

-- | Commit changes nothing but phase: the capture is preserved.
lawCommitPreservesCapture :: Int -> Int -> [Int] -> Bool
lawCommitPreservesCapture cut d cap =
  not (validInput cut d cap) || refineSession (commit (surface cut d cap)) == take (octreeLeafCount d) cap

-- | Commit is idempotent.
lawCommitIdempotent :: Int -> Int -> [Int] -> Bool
lawCommitIdempotent cut d cap =
  not (validInput cut d cap) ||
    let s = surface cut d cap in commit (commit s) == commit s
