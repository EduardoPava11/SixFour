{- |
Module      : V2ModelWiring
Description : EXPLORATION (NOT WIRED, base-only, runghc + GHCi). The SKI search expressed in ENERGY,
              via TYPECLASSES, AND the CNN model wiring it defines. Load in GHCi and read the model
              off the output: the layers, the channels, the scale spine, and the energy descent.

  Check:  runghc V2ModelWiring.hs
  GHCi:   ghci V2ModelWiring.hs   then:  putStr describeModel
                                         mapM_ print modelWiring
                                         energyTrace exampleState
                                         descend exampleState

  THE IDEA (owner directive 2026-06-29): the SKI ops ARE the CNN layers, and the search is energy
  descent (PonderNet). Two typeclasses abstract it:
    * class Energy a       -- a state has an integer ENERGY (the entropy-weighted residual; V2EnergyWeave).
    * class Energy a => Descent a  -- the SKI / PonderNet SEARCH: reduceStep lowers energy, stable halts.
  The CNN WIRING is the SKI word made concrete: OpS = lift / up-rung (a transposed conv that invents
  detail, x4 = one twiceness rung), OpK = pool / down-rung (strided conv), OpI = same-scale process
  conv, Halt = the PonderNet stop. The model searches by descending its energy to a stable state.

  This file is meant to be RUN in GHCi to help define the model: the Show instances print the wiring
  and the energy trace. Opponent latent + position (L,a,b,x,y,t) = 6 input channels. Trainer untouched.
-}
module V2ModelWiring where

import Data.List (intercalate)

-- ===========================================================================
-- (1) The scale spine and the SKI ops as CNN layer kinds
-- ===========================================================================

-- | The octree scale spine (the CNN's spatial resolution at each stage): 16/32/64/128/256.
data Scale = S16 | S32 | S64 | S128 | S256
  deriving (Eq, Ord, Enum, Bounded, Show)

side :: Scale -> Int
side s = 16 * 2 ^ fromEnum s     -- 16, 32, 64, 128, 256

-- | The SKI ops as CNN layer kinds. OpS = lift / expand (transposed conv, invents detail UP a rung);
--   OpK = pool / contract (strided conv DOWN a rung); OpI = same-scale process conv; Halt = ponder stop.
data Op = OpS | OpK | OpI | Halt
  deriving (Eq, Show)

-- | One line of the model wiring: a CNN layer.
data Layer = Layer
  { lOp    :: Op
  , lIn    :: Scale
  , lOut   :: Scale
  , lInCh  :: Int
  , lOutCh :: Int
  } deriving (Eq)

-- | A GHCi-readable layer line.
instance Show Layer where
  show (Layer op i o ic oc) =
    pad 5 (show op) ++ "  " ++ pad 6 (show (side i) ++ "^3") ++ " -> " ++ pad 6 (show (side o) ++ "^3")
      ++ "   ch " ++ pad 3 (show ic) ++ " -> " ++ show oc
    where pad n str = take n (str ++ repeat ' ')

-- ===========================================================================
-- (2) THE TYPECLASSES: energy + the SKI / PonderNet search
-- ===========================================================================

-- | A state carries an integer ENERGY (the entropy-weighted residual the search lowers).
class Energy a where
  energy :: a -> Int

-- | The SKI / PonderNet SEARCH over the energy: one reduction step lowers the energy; 'stable' is the
--   halt (a fixpoint, the stable state). Laws (checked below): reduceStep is non-increasing in energy,
--   and stable states are fixpoints, so the search terminates.
class Energy a => Descent a where
  reduceStep :: a -> a
  stable     :: a -> Bool

-- | Run the search: the chain of states from a to the stable state (GHCi: descend exampleState).
descend :: Descent a => a -> [a]
descend a
  | stable a  = [a]
  | otherwise = a : descend (reduceStep a)

-- | The energy at each search step (GHCi: energyTrace exampleState -> [E0, E1, ..., 0]). PonderNet
--   reads its depth off this: the length is the adaptive number of steps to a stable state.
energyTrace :: Descent a => a -> [Int]
energyTrace = map energy . descend

ponderDepth :: Descent a => a -> Int
ponderDepth = subtract 1 . length . descend

-- ===========================================================================
-- (3) The CNN model wiring (the thing the search defines)
-- ===========================================================================

-- | The opponent latent + position is the model input: L, a, b, x, y, t.
inputChannels :: Int
inputChannels = 6

-- | THE MODEL WIRING: the 16 -> 64 -> 256 CNN as an SKI word. OpS lifts a twiceness rung (x4), OpI
--   processes, the head projects back to the 6 opponent axes, Halt is the PonderNet stop. Run in GHCi
--   with  mapM_ print modelWiring  to read the architecture.
modelWiring :: [Layer]
modelWiring =
  [ Layer OpI  S16  S16  6   64    -- stem: 6 opponent axes -> 64 feature channels at 16^3
  , Layer OpS  S16  S64  64  64    -- rung 1 (S): invent detail UP to 64^3
  , Layer OpI  S64  S64  64  64    -- process at 64^3
  , Layer OpS  S64  S256 64  32    -- rung 2 (S): invent detail UP to 256^3
  , Layer OpI  S256 S256 32  6     -- head: project back to the 6 opponent axes (decode -> sRGB)
  , Layer Halt S256 S256 6   6     -- PonderNet halt: stable state
  ]

-- | A GHCi-printable description of the model (run: putStr describeModel).
describeModel :: String
describeModel = unlines $
  [ "MODEL WIRING (SKI ops as CNN layers; opponent latent L,a,b,x,y,t)"
  , replicate 56 '-' ]
  ++ map show modelWiring
  ++ [ replicate 56 '-'
     , "input channels   : " ++ show inputChannels ++ "  (L,a,b,x,y,t)"
     , "scale rungs       : " ++ intercalate " -> " (map (\s -> show (side s) ++ "^3") rungScales)
     , "S layers (lift)   : " ++ show (count OpS) ++ "   (each x4 = one twiceness rung)"
     , "I layers (process): " ++ show (count OpI)
     , "Halt (ponder stop): " ++ show (count Halt) ]
  where
    count op = length (filter ((== op) . lOp) modelWiring)
    rungScales = [S16, S64, S256]

-- ===========================================================================
-- (4) A concrete search state: per-region residual energy (the EBM descent)
-- ===========================================================================

-- | The search state: the per-region residual magnitudes the model must reduce (the entropy-weighted
--   energy field). reduceStep resolves the HIGHEST-energy region (one S-invention / one ponder step);
--   stable when every region is at the floor (zero residual = the byte-exact stable state).
newtype SearchState = SearchState [Int] deriving (Eq, Show)

instance Energy SearchState where
  energy (SearchState rs) = sum (map abs rs)

instance Descent SearchState where
  reduceStep (SearchState rs) = SearchState (zeroLargest rs)
  stable     (SearchState rs) = all (== 0) rs

zeroLargest :: [Int] -> [Int]
zeroLargest [] = []
zeroLargest rs = [ if j == i then 0 else x | (j, x) <- zip [0 :: Int ..] rs ]
  where i = snd (maximum [ (abs x, j) | (j, x) <- zip [0 :: Int ..] rs ])

exampleState :: SearchState
exampleState = SearchState [3, 0, 7, 2, 0, 5, 1]    -- 5 regions hold energy; ponder depth = 5

-- ===========================================================================
-- (5) Laws
-- ===========================================================================

-- | DESCENT LOWERS ENERGY: one search step never raises the energy, and strictly lowers it until stable.
lawDescentMonotone :: Bool
lawDescentMonotone =
     all (\s -> energy (reduceStep s) <= energy s) states
  && all (\s -> stable s || energy (reduceStep s) < energy s) states
  where states = map SearchState [[3,0,7,2,0,5,1], [9], [0,0,0], [-4,4,-4], [1,2,3,4,5]]

-- | STABLE IS A FIXPOINT: a stable state reduces to itself (the PonderNet halt is genuine).
lawStableIsFixpoint :: Bool
lawStableIsFixpoint =
     stable z && reduceStep z == z
  && not (stable exampleState)
  where z = SearchState [0,0,0]

-- | THE SEARCH TERMINATES at the stable (zero-energy) state, and the energy trace is NON-INCREASING.
lawSearchTerminatesMonotone :: Bool
lawSearchTerminatesMonotone =
     last (energyTrace exampleState) == 0
  && and (zipWith (>=) tr (drop 1 tr))
  where tr = energyTrace exampleState

-- | PONDER DEPTH = the number of energy-bearing regions (the adaptive search depth PonderNet reads off).
lawPonderDepthIsResidualCount :: Bool
lawPonderDepthIsResidualCount =
     ponderDepth exampleState == length (filter (/= 0) rs)
  && ponderDepth (SearchState [0,0,0]) == 0          -- already stable: zero depth
  where SearchState rs = exampleState

-- | THE SKI OPS ARE CNN LAYERS at the right scales: OpS lifts a twiceness rung (out side = 4 * in),
--   OpI keeps the scale, Halt keeps the scale. So the wiring is a well-formed scale spine.
lawSKIOpsAreCNNLayers :: Bool
lawSKIOpsAreCNNLayers =
     all check modelWiring
  && any ((== OpS) . lOp) modelWiring                -- the model actually lifts (it is not flat)
  where
    check (Layer OpS i o _ _) = side o == 4 * side i  -- S = one twiceness rung (x4)
    check (Layer OpK i o _ _) = side i == 4 * side o  -- K = pool down a rung
    check (Layer OpI i o _ _) = side i == side o      -- I = same scale
    check (Layer Halt i o _ _) = side i == side o     -- Halt = same scale

-- | THE WIRING IS A CONNECTED PIPELINE: each layer's input scale/channels match the previous layer's
--   output (a real CNN, not disconnected layers), and it starts at 6 input channels (the opponent axes).
lawWiringIsConnected :: Bool
lawWiringIsConnected =
     lInCh (head modelWiring) == inputChannels
  && and (zipWith ok modelWiring (drop 1 modelWiring))
  where ok prev next = lOut prev == lIn next && lOutCh prev == lInCh next

-- ===========================================================================
-- (6) Runner (mirrors GifSki.hs) + the GHCi-defining outputs
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawDescentMonotone           (search lowers energy, strict until stable)", lawDescentMonotone)
  , ("lawStableIsFixpoint          (PonderNet halt is a genuine fixpoint)",      lawStableIsFixpoint)
  , ("lawSearchTerminatesMonotone  (descends to 0 energy, non-increasing)",      lawSearchTerminatesMonotone)
  , ("lawPonderDepthIsResidualCount(ponder depth = energy-bearing regions)",     lawPonderDepthIsResidualCount)
  , ("lawSKIOpsAreCNNLayers        (OpS=x4 rung, OpK=pool, OpI=same scale)",      lawSKIOpsAreCNNLayers)
  , ("lawWiringIsConnected         (channels/scales chain: a real CNN)",         lawWiringIsConnected)
  ]

main :: IO ()
main = do
  putStrLn "V2ModelWiring.hs  -- EXPLORATION (NOT WIRED): SKI search in energy + the CNN wiring"
  putStrLn (replicate 72 '-')
  mapM_ (\(n, ok) -> putStrLn (verdict ok ++ "  " ++ n)) laws
  putStrLn (replicate 72 '-')
  let passed = length (filter snd laws); total = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  putStr describeModel
  putStrLn ""
  putStrLn ("energy trace (the SKI/PonderNet descent): " ++ show (energyTrace exampleState))
  putStrLn ("ponder depth (adaptive): " ++ show (ponderDepth exampleState) ++ " steps to the stable state")
  putStrLn ""
  putStrLn "GHCi: load this file, then  putStr describeModel  |  mapM_ print modelWiring  |"
  putStrLn "      energyTrace exampleState  |  descend exampleState   to define / inspect the model."
  where
    verdict True  = "PASS"
    verdict False = "FAIL"
