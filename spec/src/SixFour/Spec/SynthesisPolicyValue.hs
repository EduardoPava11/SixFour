{- |
Module      : SixFour.Spec.SynthesisPolicyValue
Description : The GIF synthesis as an AlphaGo-style POLICY + VALUE factorization — POLICY = the index map (WHERE = which of K=256 palette slots, a categorical integer argmax), VALUE = the per-frame palette (WHAT-COLOUR, a Q16 colour table). @pixels = value[policy] = palette[index]@. Binds the byte-exact reconstruction to the per-frame ≤K budget on ONE object ("SixFour.Spec.Upscale256" @UpscaleOutput@), and pins the colours "finding a home in relation to each other" (the d6-restricted entry ordering).

This is NOT new math. The factorization already exists, typed, in "SixFour.Spec.ConstructionEncoder"
(@cIndex@ = the policy, @cPalette@ = the value, @buildPixels = palette[index]@) and the per-frame
≤K=256 budget already holds green over "SixFour.Spec.Upscale256" (@upscaleWithinBudget@). This module
is the HONEST middle:

  * the BRIDGE — @ConstructionEncoder.Construction@ is flat over the @8^d@ lattice (no t-axis), so the
    per-frame budget that lives over @Upscale256@ is uncomputable on it. We bind directly to
    "SixFour.Spec.Upscale256" @UpscaleOutput = (outPalettes = VALUE, outCube = POLICY)@, which already
    carries the t-axis, so composition (@value[policy]@) and the per-frame budget hold on the SAME object.
  * the ONE genuinely-new tooth — 'lawPaletteRelationallyOrdered': the palette ENTRIES are ordered by
    'colourL1' (the @(L,a,b)@ restriction of the @d6@ metric) so adjacent indices are perceptually close
    (the owner's "find them a home in relation to each other"). A random permutation FAILS it.

This VALUE is GENERATIVE COLOUR (the palette the GIF is built from), NOT the deleted Bradley-Terry
preference value ("SixFour.Spec.ValueHead" is retired). The committed POLICY is an integer argmax (no
float commits a byte); the VALUE crosses @reenterQ16@ once. Laws QuickCheck'd in
"Properties.SynthesisPolicyValue".
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.SynthesisPolicyValue
  ( -- * Named constants
    kPaletteSlots
  , nTokens
  , committedIndexBytes
  , valueLeafReals
  , coarseIdentitySide
    -- * The policy / value views of a synthesis (Upscale256)
  , policyOf
  , valueOf
  , reconstructFrame
  , policyInRange
  , synthesisWellFormed
    -- * The relational palette ordering ("colours find a home in relation to each other")
  , colourL1
  , adjacentCost
  , relationallyOrder
  , isRelationallyOrdered
    -- * Laws (QuickCheck'd in @Properties.SynthesisPolicyValue@)
  , lawSynthesisIsPolicyValue
  , lawPolicyIsIntegerArgmax
  , lawValueIsPerFrameBudget
  , lawPaletteRelationallyOrdered
  , lawSixteenCubedIsIdentity
  ) where

import Data.List (minimumBy, delete)
import Data.Ord  (comparing)
import qualified Data.Vector as V

import SixFour.Spec.Upscale256        (UpscaleOutput(..), PxQ16)
import SixFour.Spec.SuperResPalette   (upscaleWithinBudget)
import qualified SixFour.Spec.CoarseIsPalette     as CIP
import qualified SixFour.Spec.ConstructionEncoder as CE

-- =============================================================================
-- Named constants (the scope-out numbers)
-- =============================================================================

-- | The palette budget K (the categorical width of the POLICY): 256 slots per frame.
kPaletteSlots :: Int
kPaletteSlots = 256

-- | The ViT token axis (= @octreeLeafCount 2 = 8²@), the minimum token capacity.
nTokens :: Int
nTokens = 64

-- | The committed POLICY size: one @u8@ index per voxel of the @64³@ capture (@8^6@).
committedIndexBytes :: Int
committedIndexBytes = 262144

-- | The committed VALUE degrees of freedom per frame: @256 colours × 3 Q16 channels@.
valueLeafReals :: Int
valueLeafReals = kPaletteSlots * 3

-- | The side at which a frame IS a palette (@16² = 256@): the value head's identity rung.
coarseIdentitySide :: Int
coarseIdentitySide = 16

-- =============================================================================
-- The policy / value views (over Upscale256.UpscaleOutput = the per-t (value, policy) pair)
-- =============================================================================

-- | The POLICY: per-frame index planes (which palette slot each voxel points at).
policyOf :: UpscaleOutput -> [V.Vector Int]
policyOf = outCube

-- | The VALUE: per-frame palettes (the actual Q16 colours).
valueOf :: UpscaleOutput -> [[PxQ16]]
valueOf = outPalettes

-- | The composition @value[policy]@ for one frame: look each policy index up in the value table.
reconstructFrame :: [PxQ16] -> V.Vector Int -> [PxQ16]
reconstructFrame pal idx = [ pal !! i | i <- V.toList idx ]

-- | Every policy index addresses a real value slot (so @value[policy]@ is total).
policyInRange :: UpscaleOutput -> Bool
policyInRange u =
  and [ V.all (\i -> i >= 0 && i < length pal) idx
      | (pal, idx) <- zip (outPalettes u) (outCube u) ]

-- | The synthesis is well-formed: the frames align AND the policy is in range — so
-- @value[policy]@ reconstructs every frame totally.
synthesisWellFormed :: UpscaleOutput -> Bool
synthesisWellFormed u =
     length (outPalettes u) == length (outCube u)
  && policyInRange u

-- =============================================================================
-- The relational palette ordering ("colours find a home in relation to each other")
-- =============================================================================

-- | The @(L,a,b)@ restriction of the @d6@ metric (Q16 L1): the perceptual distance between
-- two palette colours.
colourL1 :: PxQ16 -> PxQ16 -> Int
colourL1 (l1, a1, b1) (l2, a2, b2) = abs (l1 - l2) + abs (a1 - a2) + abs (b1 - b2)

-- | The total adjacent perceptual cost of a palette ordering — how "homed" the colours are.
adjacentCost :: [PxQ16] -> Int
adjacentCost pal = sum (zipWith colourL1 pal (drop 1 pal))

-- | Order a palette so each entry's neighbour is its nearest remaining colour by 'colourL1' —
-- a greedy nearest-neighbour chain from the first entry. A pure function of the colours (no
-- transmitted permutation), so the freeze adds nothing to commit.
relationallyOrder :: [PxQ16] -> [PxQ16]
relationallyOrder []         = []
relationallyOrder (c0 : cs0) = go c0 cs0
  where
    go cur rest = cur : case rest of
      [] -> []
      _  -> let nxt = minimumBy (comparing (colourL1 cur)) rest
            in go nxt (delete nxt rest)

-- | A palette is in relational order iff it is its own 'relationallyOrder'.
isRelationallyOrdered :: [PxQ16] -> Bool
isRelationallyOrdered pal = pal == relationallyOrder pal

-- =============================================================================
-- Laws
-- =============================================================================

-- | KEYSTONE (the factorization map + the bridge): on a well-formed synthesis the POLICY indexes
-- the VALUE totally (@value[policy]@ reconstructs every frame) AND every t-slice obeys the ≤K=256
-- budget — BOTH on the one @UpscaleOutput@ object (the bridge @ConstructionEncoder@ alone cannot
-- express, being t-axis-free). Teeth: a policy index pointing past its frame's palette is rejected.
lawSynthesisIsPolicyValue :: Bool
lawSynthesisIsPolicyValue =
     synthesisWellFormed witnessSynthesis
  && upscaleWithinBudget kPaletteSlots witnessSynthesis
  && not (synthesisWellFormed brokenIndexSynthesis)

-- | The committed POLICY is an INTEGER argmax in @[0, K)@ per frame — a pure integer decision, so
-- no float commits a byte (cross-device safe). Teeth: an out-of-range index fails.
lawPolicyIsIntegerArgmax :: Bool
lawPolicyIsIntegerArgmax =
     policyInRange witnessSynthesis
  && not (policyInRange brokenIndexSynthesis)

-- | The VALUE obeys the per-frame ≤K budget (delegates "SixFour.Spec.SuperResPalette"
-- @upscaleWithinBudget@ — already green). Teeth: a @K=1@ budget rejects the multi-colour witness.
lawValueIsPerFrameBudget :: Bool
lawValueIsPerFrameBudget =
     upscaleWithinBudget kPaletteSlots witnessSynthesis
  && not (upscaleWithinBudget 1 witnessSynthesis)

-- | THE NEW TOOTH — the colours "find a home in relation to each other": ordering a scrambled
-- palette by 'relationallyOrder' re-homes it (non-trivial), is idempotent (an already-homed
-- palette stays), and lowers the adjacent perceptual cost. Teeth: a random permutation is NOT
-- relationally ordered.
lawPaletteRelationallyOrdered :: Bool
lawPaletteRelationallyOrdered =
  let scrambled = [(0,0,0),(30,0,0),(10,0,0),(20,0,0)] :: [PxQ16]
      ordered   = relationallyOrder scrambled
  in  ordered /= scrambled
   && relationallyOrder ordered == ordered
   && adjacentCost ordered <= adjacentCost scrambled
   && not (isRelationallyOrdered scrambled)

-- | At the 16³ Analysis rung the POLICY degenerates to the identity (position = slot) and the
-- VALUE IS the frame: @16² = 256@ means a frame is exactly a palette (delegates
-- "SixFour.Spec.CoarseIsPalette"). So at the coarse rung the value head alone reconstructs.
lawSixteenCubedIsIdentity :: Bool
lawSixteenCubedIsIdentity =
     coarseIdentitySide * coarseIdentitySide == kPaletteSlots
  && CIP.lawCoarseFrameSizeIsPaletteSize
  && CE.identityIndex 4 == [0 .. 4095]   -- 8^4 = 4096 voxels; position v reads slot v

-- =============================================================================
-- Witnesses (closed, with teeth — the established ConstructionEncoder style)
-- =============================================================================

-- | A valid 2-frame synthesis: palettes within budget, every index addresses its frame's palette.
witnessSynthesis :: UpscaleOutput
witnessSynthesis = UpscaleOutput
  { outPalettes = [ [(0,0,0),(100,0,0)], [(0,0,0),(50,0,0),(100,0,0)] ]
  , outCube     = [ V.fromList [0,1,1,0], V.fromList [0,2,1] ]
  }

-- | The same synthesis with a POLICY index (9) pointing past its frame's palette — the
-- ill-formed case the keystone's teeth reject.
brokenIndexSynthesis :: UpscaleOutput
brokenIndexSynthesis = witnessSynthesis { outCube = [ V.fromList [0,9,1,0], V.fromList [0,2,1] ] }
