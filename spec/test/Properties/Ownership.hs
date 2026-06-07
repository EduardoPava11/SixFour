module Properties.Ownership (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Ownership
import SixFour.Spec.CellFiber (neutralColor, contestedSentinel)

tests :: TestTree
tests = testGroup "Ownership (colour = owner identity — the SIMD ownership field, step 1)"
  [ testProperty "the owner alphabet is closed at exactly 7" $
      once (length allOwners == 7)

  , testProperty "badge palette is injective + in-gamut + ∉ {neutralColor, contestedSentinel}" $
      once lawOwnerColorInjective

  , testProperty "ownerColorInv round-trips every owner badge (colour decodes owner)" $
      once lawOwnerColorRoundTrips

  -- The partial inverse is HONEST: the two reserved anchors are not owners, so they
  -- decode to no owner (a contested cell is never mistaken for an owned one).
  , testProperty "neutral / contested anchors decode to no owner" $
      once (ownerColorInv (OwnerColor neutralColor) == Nothing
            && ownerColorInv (OwnerColor contestedSentinel) == Nothing)

  -- Step 2 — responsibility binding (the "Preview owns the frames, Palette owns the
  -- palette" half of the user's model, as law).
  , testProperty "responsibility is total & every owner refreshes at 20fps" $
      once lawResponsibilityTotal

  , testProperty "Preview governs the 64×64 frames (== |allPlaces| == 4096)" $
      once lawPreviewGovernsFrames

  , testProperty "Palette governs that frame's 16×16 palette (== gridCells == 256)" $
      once lawPaletteGovernsPalette

  , testProperty "Ring gauge answers to the frames (ticks == previewCells == 64)" $
      once lawRingAnswersToFrames

  -- Step 3 — foreground regions + the disjoint cover (2-owner seed).
  , testProperty "cover: foreground regions are in-bounds (100×218)" $
      once lawCoverInBounds

  , testProperty "cover: preview & palette are disjoint (no atom double-claimed)" $
      once lawCoverDisjoint

  , testProperty "cover: golden sample atoms decode to the right owner (incl. Field gaps)" $
      once lawCoverSampleMatches

  -- Step 4 — totality + completeness over all 21800 atoms.
  , testProperty "cover: TOTAL — all 21800 atoms owned; Field is the exact complement" $
      once lawCoverTotal

  , testProperty "cover: COMPLETE — every owner claims its full footprint (self-or-fused)" $
      once lawPreviewClaimsFullFootprint

  , testProperty "cover: every interactive owner clears the 44 pt touch floor" $
      once lawOwnerTouchFloor

  -- Step 5 — fusion zones (sanctioned co-occupancy vs a contention bug).
  , testProperty "fusion: a fused Shutter∩Palette overlap is NOT contention (EffectZone)" $
      once lawFusionIsEffectZoneNotBug

  , testProperty "fusion: a NON-fused overlap renders the loud sentinel, never a blend" $
      once lawContentionIsSentinelNotBlend

  , testProperty "fusion: bridge — no contested atom ⇔ no non-fused rectangle overlap" $
      once lawDisjointMatchesRectsOwner

  -- Step 7 — rendered field + decode round-trip (colour IS the quotient label).
  , testProperty "refresh: the field is one 20fps pass over the whole 100×218 lattice" $
      once lawRefreshIs20fps

  , testProperty "decode: every non-contested atom's colour decodes back to its owner" $
      once lawColorDecodesOwner

  , testProperty "decode: colour IS the quotient label (same colour ⇔ same owner)" $
      once lawColorIsQuotientLabel
  ]
