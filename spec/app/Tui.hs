{- |
spec-tui — a live, true-colour viewer for the SixFour spec's math.

It calls the **real** @SixFour.Spec.*@ functions (no port, no mock) and renders OKLab as
24-bit terminal blocks, so you can *see* the math the QuickCheck laws verify:

  * a synthetic 64×256 capture's per-frame palette,
  * the **collapse** to one palette — the Wasserstein-2 / k-means floor ('baselinePalette'),
  * the **look** = floor + bounded residual ('SixFour.Spec.LookCore.applyLookCore'),
  * the **Haar tree** refining root → 256 leaves ('SixFour.Spec.PairTree.reconstruct'),
  * the **σ reflection** @(L,a,b)↦(L,−a,−b)@ and its equivariance,

with the contract **laws shown live (PASS/FAIL)** on the real data on screen.

Run:  @cabal run spec-tui@   ·  keys: [tab] next view · [r] reseed · [q] quit
-}
module Main (main) where

import           Control.Monad        (void)
import           Control.Monad.State  (modify)
import           Data.Maybe           (fromJust)
import qualified Data.Vector          as V

import           Brick
import           Brick.Widgets.Border  (borderWithLabel, hBorder)
import           Brick.Widgets.Center  (hCenter)
import qualified Graphics.Vty          as Vty

import SixFour.Spec.Color    (OKLab(..), SRGB(..), okLabToSRGB)
import SixFour.Spec.Palette  (mkPalette, paletteToList)
import SixFour.Spec.Cyclic   (CyclicStack(..), Weights)
import SixFour.Spec.PairTree (HaarPalette(..), reconstruct, treeDepth, lawBalancedMean)
import SixFour.Spec.LookNet  (baselinePalette)
import SixFour.Spec.LookCore
  ( applyLookCore, lookCoreScale, sigmaHaar
  , lawNeutralIsFloor, lawBoundedLeaves, lawSigmaEquivariant )

-- ----------------------------------------------------------------------------
-- A tiny deterministic synth (Haskell-side) so [r] reseed gives a fresh capture
-- ----------------------------------------------------------------------------

rnd :: Int -> Double
rnd n = fromIntegral ((n * 2654435761 + 1013904223) `mod` 1000003) / 1000003

oklabOf :: Int -> OKLab
oklabOf n = OKLab (rnd n) ((rnd (n * 7 + 1) - 0.5) * 0.6) ((rnd (n * 13 + 3) - 0.5) * 0.6)

-- | A synthetic capture at the real SixFour dims: 64 frames × 256-colour palettes.
synthCapture :: Int -> CyclicStack 64 256
synthCapture seed = CyclicStack (V.fromList [ (palAt t, weights) | t <- [0 .. 63] ])
  where
    weights = V.replicate 256 1 :: Weights
    palAt t = fromJust (mkPalette @256 [ oklabOf (seed * 1000003 + t * 257 + s) | s <- [0 .. 255] ])

-- | A residual shaped like a depth-8 Haar palette (pre-tanh; any range — the core
-- bounds it). Drives the visible "look".
synthResidual :: Int -> HaarPalette
synthResidual seed =
  HaarPalette (resid seed) [ [ resid (seed + i * 131 + j) | j <- [0 .. 2 ^ i - 1] ] | i <- [0 .. 7] ]
  where resid n = OKLab ((rnd n - 0.5) * 4) ((rnd (n * 5 + 2) - 0.5) * 4) ((rnd (n * 9 + 4) - 0.5) * 4)

frameColors :: CyclicStack t k -> Int -> [OKLab]
frameColors (CyclicStack fr) t = paletteToList (fst (fr V.! t))

-- ----------------------------------------------------------------------------
-- Rendering — OKLab → 24-bit terminal blocks
-- ----------------------------------------------------------------------------

toVtyColor :: OKLab -> Vty.Color
toVtyColor lab =
  let SRGB r g b = okLabToSRGB lab
      q x = max 0 (min 255 (round (x * 255))) :: Int
  in Vty.rgbColor (q r) (q g) (q b)

-- | A palette laid out @cols@ wide, as one vty image of 2-wide colour cells.
paletteGrid :: Int -> [OKLab] -> Widget n
paletteGrid cols cs = raw (Vty.vertCat [ Vty.horizCat (map cell row) | row <- chunk cols cs ])
  where cell c = Vty.string (Vty.defAttr `Vty.withBackColor` toVtyColor c) "  "

chunk :: Int -> [a] -> [[a]]
chunk _ [] = []
chunk n xs = take n xs : chunk n (drop n xs)

labeled :: String -> Widget n -> Widget n
labeled lbl w = borderWithLabel (str (" " <> lbl <> " ")) (hCenter w)

truncateHaar :: Int -> HaarPalette -> HaarPalette
truncateHaar d (HaarPalette r lvls) = HaarPalette r (take d lvls)

-- ----------------------------------------------------------------------------
-- App
-- ----------------------------------------------------------------------------

data Scene = Collapse | Tree | Symmetry deriving (Eq, Enum, Bounded)

sceneName :: Scene -> String
sceneName Collapse = "collapse"
sceneName Tree     = "haar tree"
sceneName Symmetry = "σ symmetry"

nextScene :: Scene -> Scene
nextScene s = if s == maxBound then minBound else succ s

data St = St { stSeed :: !Int, stScene :: !Scene }

draw :: St -> [Widget ()]
draw st = [ vBox [ header, hBorder, body, hBorder, lawsPanel, footer ] ]
  where
    cap    = synthCapture (stSeed st)
    floor' = baselinePalette cap
    res    = synthResidual (stSeed st)
    looked = applyLookCore lookCoreScale floor' res

    header = hCenter (str "SixFour spec — live math viewer  (the QuickCheck laws, made visible)")

    body = case stScene st of
      Collapse -> vBox
        [ labeled "one frame of the capture (256-colour palette)" (paletteGrid 32 (frameColors cap 0))
        , labeled "COLLAPSE → floor  (Wasserstein-2 / k-means barycenter)" (paletteGrid 32 (reconstruct floor'))
        , labeled ("+ LOOK  (floor + s·tanh residual, s=" <> show lookCoreScale <> ")") (paletteGrid 32 (reconstruct looked))
        ]
      Tree -> vBox $
        str "Haar tree: root → 256 leaves, σ-balanced pairs at every level (showing levels 0–5)"
        : [ hCenter (paletteGrid (2 ^ d) (reconstruct (truncateHaar d floor'))) | d <- [0 .. min 5 (treeDepth floor')] ]
        ++ [ str ("balance  mean(leaves) = root :  " <> pass (lawBalancedMean 1e-9 floor')) ]
      Symmetry -> vBox
        [ labeled "floor" (paletteGrid 32 (reconstruct floor'))
        , labeled "σ(floor)  =  (L, a, b) ↦ (L, −a, −b)   [exact OKLab complement]" (paletteGrid 32 (reconstruct (sigmaHaar floor')))
        ]

    lawsPanel = borderWithLabel (str " LookCore contract — verified live on what's on screen ")
      (vBox
        [ str ("neutral residual = floor (reset works) :  " <> pass (lawNeutralIsFloor floor'))
        , str ("bounded: every leaf ≤ (depth+1)·s off floor :  " <> pass (lawBoundedLeaves 1e-9 floor' res))
        , str ("σ-equivariant: apply ∘ σ = σ ∘ apply :  " <> pass (lawSigmaEquivariant 1e-9 floor' res))
        ])

    footer = hCenter (str ("[tab] next view   [r] reseed   [q] quit      view: "
                            <> sceneName (stScene st) <> "   seed: " <> show (stSeed st)))

    pass b = if b then "PASS ✓" else "FAIL ✗"

handle :: BrickEvent () e -> EventM () St ()
handle (VtyEvent (Vty.EvKey (Vty.KChar 'q')  [])) = halt
handle (VtyEvent (Vty.EvKey (Vty.KChar 'r')  [])) = modify (\s -> s { stSeed = stSeed s + 1 })
handle (VtyEvent (Vty.EvKey (Vty.KChar '\t') [])) = modify (\s -> s { stScene = nextScene (stScene s) })
handle (VtyEvent (Vty.EvKey Vty.KEsc         [])) = halt
handle _                                          = return ()

app :: App St e ()
app = App
  { appDraw         = draw
  , appChooseCursor = neverShowCursor
  , appHandleEvent  = handle
  , appStartEvent   = return ()
  , appAttrMap      = const (attrMap Vty.defAttr [])
  }

main :: IO ()
main = void (defaultMain app (St 1 Collapse))
