{- |
Module      : SixFour.Spec.PlaybackClock
Description : The single playback clock that drives the unified 2D/3D player
              and the frame-synced palette analyzers (docs/SIXFOUR-UNIFIED-PLAYER.md).

The Review screen historically ran /four/ uncoordinated frame clocks (the 2D
GIF @Timer@, the status-line @TimelineView@, and the cloud/voxel 60 Hz
publishers). They drift and never agree on "the current frame". This module is
the /reference oracle/ for the one clock that replaces them: a cyclic cursor on
@Z_N@ (frame @N-1@ wraps to @0@), reusing the @(t+1) `mod` nt@ idiom of
"SixFour.Spec.Cyclic".

Everything here is pure, total integer arithmetic — Layers 0–2 of
@docs/SIXFOUR-SPEC-METHODOLOGY.md@, the same altitude as the lattice/coverage
oracles. The golden tables ('goldenAdvanceTable', 'goldenFreezeVector') are the
cross-language gate: the Swift @PlaybackClock@ and the analyzers' frame
selection are pinned bit-for-bit against them via @Generated/PlaybackClockContract.swift@.

Three guarantees the player UX rests on:

  * /Two views agree/ — the 2D GIF image at cursor @i@ and the flat-pose 3D cube
    front face (depth slice @z = N-1@) index the /same/ frame. The Metal kernel's
    depth→frame map @f(z) = (cursor - (N-1) + z) `mod` N@ (Shaders.metal:658)
    reduces at @z = N-1@ to @cursor@, so 'threeDFrontFace' ≡ 'twoDFrame'.
  * /Palette-at-frame is deterministic/ — every analyzer reads
    @palettesForDisplay !! clampFrame N i@, a pure total function of the palette
    stack and the cursor, with no clock/time dependence. Same @i@ ⇒ same colours
    in every view.
  * /Reduce-motion freezes auto-advance/ — under reduce-motion the cursor never
    auto-advances ('frozenStream' is constantly @0@); only discrete scrub may
    move it. One check in the clock propagates to every consumer.
-}
module SixFour.Spec.PlaybackClock
  ( -- * Frame count
    FrameCount
    -- * Cursor motion
  , frameAfter
  , frameBefore
  , clampFrame
    -- * Reduce-motion
  , frozenStream
    -- * Two-view agreement (2D image ≡ 3D flat front face)
  , twoDFrame
  , frontFaceFrame
  , threeDFrontFace
    -- * Palette selection (the analyzer sync contract)
  , paletteAt
    -- * Golden vectors (the cross-language gate; N = 64)
  , goldenAdvanceTable
  , goldenReverseTable
  , goldenFreezeVector
  ) where

-- | The number of frames in the loop. For SixFour this is always
-- @64 = SixFourShape.T@, but the oracle is parametric so the laws hold for any
-- @N@ (and degrade gracefully at @N = 0@).
type FrameCount = Int

-- | Advance the cursor exactly one frame, wrapping @N-1 → 0@ — the cyclic step
-- of a looping GIF. Mirrors "SixFour.Spec.Cyclic"'s @(t+1) `mod` nt@. Total:
-- @N ≤ 0@ yields @0@ (an empty loop has no other frame to show), guarding the
-- Swift @currentImage@ / @PixelGrid@ @count == 0@ paths.
frameAfter :: FrameCount -> Int -> Int
frameAfter n f
  | n <= 0    = 0
  | otherwise = (f + 1) `mod` n

-- | Step the cursor exactly one frame BACKWARDS, wrapping @0 → N-1@ — the exact
-- inverse of 'frameAfter'. Drives the Act-II reverse playback: the preview does NOT
-- freeze on capture, it sweeps the assembling GIFA backwards. Total: @N ≤ 0@ yields @0@.
frameBefore :: FrameCount -> Int -> Int
frameBefore n f
  | n <= 0    = 0
  | otherwise = (f - 1 + n) `mod` n

-- | Clamp an arbitrary (e.g. scrub-drag) index into the valid cursor range
-- @[0, N)@. Scrub never leaves the loop.
clampFrame :: FrameCount -> Int -> Int
clampFrame n i
  | n <= 0    = 0
  | otherwise = max 0 (min (n - 1) i)

-- | The sequence of cursor values shown under reduce-motion: auto-advance is
-- suppressed, so every element is frame @0@. (Discrete scrub is modelled
-- separately via 'clampFrame' — reduce-motion constrains motion, not input.)
frozenStream :: FrameCount -> [Int]
frozenStream _ = repeat 0

-- | The frame the 2D GIF surface displays for cursor @i@ — just the clamped
-- cursor. Named for symmetry with 'threeDFrontFace'.
twoDFrame :: FrameCount -> Int -> Int
twoDFrame = clampFrame

-- | The Metal kernel's depth→frame map @f(z) = (cursor - (N-1) + z) `mod` N@
-- (Shaders.metal:658), exposed so the agreement law is checkable against the
-- real shader for /every/ depth slice, not just the front face.
frontFaceFrame :: FrameCount -> Int -> Int -> Int
frontFaceFrame n cursor z
  | n <= 0    = 0
  | otherwise = (clampFrame n cursor - (n - 1) + z) `mod` n

-- | The frame at the cube's /front/ face (depth slice @z = N-1@) for cursor @i@.
-- By the kernel map this reduces to the clamped cursor, so the flat-pose cube's
-- visible face is byte-identical to the 2D GIF at the same cursor.
threeDFrontFace :: FrameCount -> Int -> Int
threeDFrontFace n i = frontFaceFrame n i (n - 1)

-- | The palette an analyzer renders for cursor @i@: index the per-frame palette
-- stack at the clamped cursor. Total — an empty stack yields 'Nothing'. This is
-- the whole "analyzer synced to the frame it is on" contract: replace the old
-- @palettesForDisplay.first@ with @paletteAt palettes i@.
paletteAt :: [p] -> Int -> Maybe p
paletteAt [] _ = Nothing
paletteAt ps i = Just (ps !! clampFrame (length ps) i)

-- | One full cycle of advances from frame @0@: @[1,2,…,N-1,0]@. Pinned for
-- @N = 64@ as the Swift parity gate for @PlaybackClock.advance@.
goldenAdvanceTable :: FrameCount -> [Int]
goldenAdvanceTable n = map (frameAfter n) [0 .. max 0 (n - 1)]

-- | The reverse-step table: @map frameBefore [0..N-1]@ = @[N-1, 0, 1, …, N-2]@. Pinned
-- for @N = 64@ as the Swift parity gate for the reverse cursor (Act II no-freeze).
goldenReverseTable :: FrameCount -> [Int]
goldenReverseTable n = map (frameBefore n) [0 .. max 0 (n - 1)]

-- | The first @k@ frames shown under reduce-motion: all @0@. Pins the Swift
-- freeze-on-frame-0 behaviour.
goldenFreezeVector :: Int -> [Int]
goldenFreezeVector k = take (max 0 k) (frozenStream 64)
