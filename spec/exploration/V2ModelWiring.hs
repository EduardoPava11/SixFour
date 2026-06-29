{- |
Module      : V2ModelWiring
Description : EXPLORATION (NOT WIRED, base-only, runghc + GHCi). The CNN model wiring with channels
              DERIVED FROM ENERGY (V2EnergyArchitecture), real 3D conv params, and the activation per
              layer (the energy halt-gate / lattice snap), over the locked Latent (V2Latent, 6 ch).
              Load in GHCi and read the whole architecture off the output.

  Check:  runghc V2ModelWiring.hs
  GHCi:   ghci V2ModelWiring.hs   then:  putStr describeModel
                                         mapM_ print modelWiring
                                         stageChannels
                                         totalParams ; encoderRF
                                         energyTrace exampleState

  THE WIRING (now energy-derived, not hand-picked): a U-Net over the locked Latent. The HIDDEN
  CHANNELS per stage = channelsFromEnergy of the per-stage energy (the bottleneck carries the most
  energy so it is widest). The encoder POOLS 64^3 -> 16^3 (OpK = strided conv = octree distill, k2 =
  2x2x2 octant = A7 1+7); the decoder LIFTS 16^3 -> 256^3 (OpS = transposed conv, invents detail);
  OpI = stem/head projection; Halt = PonderNet stop. The ACTIVATION is the energy halt-gate on the
  refining layers and the byte-exact lattice snap on the head. sRGB only at the boundary. Trainer
  untouched.
-}
module V2ModelWiring where

import Data.List (foldl')
import V2Latent (latentChannelCount)                       -- the locked latent: 6 channels (L,a,b,x,y,t)
import V2EnergyArchitecture (channelsFromEnergy, gate, floorEnergy)   -- channels/activation FROM energy

-- ===========================================================================
-- (1) Channels DERIVED from energy (not hand-picked)
-- ===========================================================================

-- | The per-STAGE energy (how much each hidden stage must represent): the encoder builds up to the
--   16^3 COARSE bottleneck (the widest, most energy), the decoder spends it back down inventing detail.
--   7 stages: stem, down1, down2(bottleneck), up1, up2, up3, up4.
stageEnergy :: [Int]
stageEnergy = [8, 14, 30, 18, 9, 5, 3]

channelBudget :: Int
channelBudget = 128

-- | The hidden channel counts, DERIVED from the per-stage energy (proportional, V2EnergyArchitecture).
--   This replaces the hand-picked 6->16->32->64. = [11,20,44,26,13,7,4] for the default profile.
stageChannels :: [Int]
stageChannels = channelsFromEnergy channelBudget stageEnergy

sc :: Int -> Int
sc i = stageChannels !! i

-- ===========================================================================
-- (2) The ops, the activation, and the layer
-- ===========================================================================

-- | OpS = lift (transposed conv, invents detail UP); OpK = pool (strided conv DOWN); OpI = same-scale
--   process conv; Halt = PonderNet stop.
data Op = OpS | OpK | OpI | Halt deriving (Eq, Show)

-- | THE ACTIVATION FUNCTION per layer, mapped from the energy: HaltGate = the PonderNet energy halt
--   (refine a region above the floor, halt below; V2EnergyArchitecture.gate); LatticeSnap = the
--   byte-exact projection onto the index-6 lattice (the head, before decode); Stop = the ponder halt.
data Activation = HaltGate | LatticeSnap | Stop deriving (Eq, Show)

-- | A 3D conv's real parameters.
data Conv = Conv { kernel :: !Int, stride :: !Int, pad :: !Int } deriving (Eq)
instance Show Conv where
  show (Conv k s p) = "k" ++ show k ++ " s" ++ show s ++ " p" ++ show p

-- | One CNN layer over the locked Latent.
data Layer = Layer
  { lName :: String
  , lOp   :: Op
  , lIn   :: Int, lOut :: Int
  , lInCh :: Int, lOutCh :: Int
  , lConv :: Conv
  , lAct  :: Activation
  } deriving (Eq)

instance Show Layer where
  show l@(Layer nm op i o ic oc cv act) =
    pad 6 nm ++ pad 5 (show op) ++ pad 14 (show i ++ "^3->" ++ show o ++ "^3")
      ++ "ch " ++ pad 9 (show ic ++ "->" ++ show oc) ++ pad 11 (show cv)
      ++ pad 12 (show act) ++ show (paramCount l) ++ " params"
    where pad n str = take n (str ++ repeat ' ')

-- ===========================================================================
-- (3) The shape + parameter algebra
-- ===========================================================================

convOut :: Op -> Conv -> Int -> Int
convOut OpS (Conv k s p) inS = (inS - 1) * s - 2 * p + k          -- transposed conv (lift / upsample)
convOut _   (Conv k s p) inS = (inS + 2 * p - k) `div` s + 1      -- conv (pool / process)

paramCount :: Layer -> Int
paramCount (Layer _ Halt _ _ _ _ _ _)          = 0
paramCount (Layer _ _ _ _ ic oc (Conv k _ _) _) = k * k * k * ic * oc + oc

totalParams :: Int
totalParams = sum (map paramCount modelWiring)

encoderRF :: Int
encoderRF = fst (foldl' step (1, 1) (map lConv encoderLayers))
  where step (rf, jump) (Conv k s _) = (rf + (k - 1) * jump, jump * s)

encoderLayers :: [Layer]
encoderLayers = takeWhile ((/= OpS) . lOp) modelWiring

-- ===========================================================================
-- (4) THE MODEL WIRING (channels from energy, fixed octree scales/ops)
-- ===========================================================================

modelWiring :: [Layer]
modelWiring =
  [ Layer "stem"  OpI  64  64  latentChannelCount (sc 0) (Conv 3 1 1) HaltGate
  , Layer "down1" OpK  64  32  (sc 0) (sc 1) (Conv 2 2 0) HaltGate
  , Layer "down2" OpK  32  16  (sc 1) (sc 2) (Conv 2 2 0) HaltGate   -- 16^3 coarse bottleneck (widest)
  , Layer "up1"   OpS  16  32  (sc 2) (sc 3) (Conv 2 2 0) HaltGate
  , Layer "up2"   OpS  32  64  (sc 3) (sc 4) (Conv 2 2 0) HaltGate
  , Layer "up3"   OpS  64  128 (sc 4) (sc 5) (Conv 2 2 0) HaltGate
  , Layer "up4"   OpS  128 256 (sc 5) (sc 6) (Conv 2 2 0) HaltGate
  , Layer "head"  OpI  256 256 (sc 6) latentChannelCount (Conv 1 1 0) LatticeSnap  -- -> 6 axes -> decode
  , Layer "halt"  Halt 256 256 latentChannelCount latentChannelCount (Conv 1 1 0) Stop
  ]

describeModel :: String
describeModel = unlines $
  [ "MODEL WIRING (U-Net; channels DERIVED FROM ENERGY; SKI ops = CNN layers)"
  , replicate 78 '-' ]
  ++ map show modelWiring
  ++ [ replicate 78 '-'
     , "stage energy     : " ++ show stageEnergy
     , "  -> channels    : " ++ show stageChannels ++ "  (derived, bottleneck widest)"
     , "input channels   : " ++ show latentChannelCount ++ "  (the locked Latent L,a,b,x,y,t)"
     , "coarse bottleneck: 16^3, " ++ show (sc 2) ++ " channels (the most energy)"
     , "super-res output : 256^3 -> 6 axes (decode -> sRGB)"
     , "activations      : HaltGate (refine/halt by energy) on convs; LatticeSnap on the head"
     , "encoder RF       : " ++ show encoderRF ++ "^3 input voxels per coarse voxel"
     , "total parameters : " ++ show totalParams ++ "  (hand-written forward blob)" ]

-- ===========================================================================
-- (5) The energy / search typeclasses (the activation engine)
-- ===========================================================================

class Energy a where
  energy :: a -> Int

class Energy a => Descent a where
  reduceStep :: a -> a
  stable     :: a -> Bool

descend :: Descent a => a -> [a]
descend a | stable a  = [a]
          | otherwise = a : descend (reduceStep a)

energyTrace :: Descent a => a -> [Int]
energyTrace = map energy . descend

ponderDepth :: Descent a => a -> Int
ponderDepth = subtract 1 . length . descend

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
exampleState = SearchState [3, 0, 7, 2, 0, 5, 1]

-- ===========================================================================
-- (6) Laws
-- ===========================================================================

-- | THE CHANNELS ARE ENERGY-DERIVED (not hand-picked): the hidden channels ARE channelsFromEnergy of
--   the per-stage energy; the highest-energy stage (the bottleneck) is the widest, the lowest the
--   narrowest, and the channel order tracks the energy order. This is the wired energy->architecture.
lawChannelsAreEnergyDerived :: Bool
lawChannelsAreEnergyDerived =
     stageChannels == channelsFromEnergy channelBudget stageEnergy
  && sc 2 == maximum stageChannels                 -- bottleneck (max energy) -> most channels
  && sc 6 == minimum stageChannels                 -- least energy -> fewest channels
  && and [ (stageEnergy !! i <= stageEnergy !! j) == (stageChannels !! i <= stageChannels !! j)
         | i <- [0 .. 6], j <- [0 .. 6] ]           -- channel order tracks energy order

-- | THE ACTIVATIONS ARE MAPPED: refining convs use the energy HaltGate; the head uses the byte-exact
--   LatticeSnap (project to the lattice before decode); Halt uses Stop. Each activation is justified.
lawActivationsMapped :: Bool
lawActivationsMapped =
     all (\l -> lAct l == HaltGate) (filter (\l -> lOp l `elem` [OpS, OpK]) modelWiring)
  && lAct (layerNamed "head") == LatticeSnap
  && lAct (layerNamed "halt") == Stop
  && gate floorEnergy 0 == floorEnergy && gate floorEnergy 9 == 9   -- the HaltGate halts low, passes high
  where layerNamed nm = head (filter ((== nm) . lName) modelWiring)

-- | THE SHAPES CHAIN: each layer's conv output equals its declared out side, and channels/scales chain
--   into a connected CNN. (Channels now energy-derived, so this also confirms the derivation wires up.)
lawShapesChain :: Bool
lawShapesChain =
     all (\l -> convOut (lOp l) (lConv l) (lIn l) == lOut l) modelWiring
  && and (zipWith (\a b -> lOut a == lIn b && lOutCh a == lInCh b) modelWiring (drop 1 modelWiring))

-- | THE BOUNDARY CHANNELS: 6 locked Latent channels in (stem), 6 out (head) -> decode -> sRGB closes.
lawLatentChannelsBoundary :: Bool
lawLatentChannelsBoundary =
     lInCh (head modelWiring) == latentChannelCount
  && lOutCh (last (filter ((/= Halt) . lOp) modelWiring)) == latentChannelCount

-- | THE CONV OP SEMANTICS + OCTANT: OpS lifts, OpK pools, OpI same, bottleneck 16^3, output 256^3, and
--   every lift/pool conv has a 2x2x2 = 8 = A7 (1 coarse + 7 detail) stencil.
lawConvOpSemanticsAndA7 :: Bool
lawConvOpSemanticsAndA7 =
     all ok modelWiring
  && minimum (map lIn modelWiring) == 16 && maximum (map lOut modelWiring) == 256
  && all (\l -> kernel (lConv l) == 2) (filter (\l -> lOp l `elem` [OpS, OpK]) modelWiring)
  && (2 :: Int) ^ (3 :: Int) == 8
  where
    ok (Layer _ OpS i o _ _ _ _)  = o > i
    ok (Layer _ OpK i o _ _ _ _)  = o < i
    ok (Layer _ OpI i o _ _ _ _)  = o == i
    ok (Layer _ Halt i o _ _ _ _) = o == i

-- | THE PARAMETER BUDGET: a small hand-written forward (tens of K, well under the ViT head); every conv
--   layer has positive params; Halt has none. The total is energy-derived (from the channel counts).
lawParamBudget :: Bool
lawParamBudget =
     totalParams > 0 && totalParams < 100000
  && all (\l -> lOp l == Halt || paramCount l > 0) modelWiring
  && paramCount (last modelWiring) == 0

-- | THE SEARCH descends energy to a stable fixpoint (the activation engine: HaltGate drives the
--   PonderNet descent to a stable state).
lawSearchDescends :: Bool
lawSearchDescends =
     last (energyTrace exampleState) == 0
  && and (zipWith (>=) tr (drop 1 tr))
  && reduceStep (SearchState [0,0,0]) == SearchState [0,0,0]
  where tr = energyTrace exampleState

-- ===========================================================================
-- (7) Runner + GHCi outputs
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawChannelsAreEnergyDerived(channels = channelsFromEnergy, bottleneck widest)", lawChannelsAreEnergyDerived)
  , ("lawActivationsMapped       (HaltGate on convs, LatticeSnap head, Stop halt)",   lawActivationsMapped)
  , ("lawShapesChain             (conv shapes + channels chain into a CNN)",          lawShapesChain)
  , ("lawLatentChannelsBoundary  (6 Latent in, 6 out: decode closes)",                lawLatentChannelsBoundary)
  , ("lawConvOpSemanticsAndA7    (OpS/OpK/OpI; 16..256; k2 = A7 octant)",             lawConvOpSemanticsAndA7)
  , ("lawParamBudget             (small hand-written forward; Halt 0 params)",        lawParamBudget)
  , ("lawSearchDescends          (HaltGate drives the PonderNet descent to fixpoint)", lawSearchDescends)
  ]

main :: IO ()
main = do
  putStrLn "V2ModelWiring.hs  -- EXPLORATION (NOT WIRED): CNN wiring, channels DERIVED FROM ENERGY"
  putStrLn (replicate 72 '-')
  mapM_ (\(n, ok) -> putStrLn (verdict ok ++ "  " ++ n)) laws
  putStrLn (replicate 72 '-')
  let passed = length (filter snd laws); total = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  putStr describeModel
  putStrLn ""
  putStrLn ("energy trace (PonderNet descent): " ++ show (energyTrace exampleState)
            ++ "   ponder depth " ++ show (ponderDepth exampleState))
  putStrLn ""
  putStrLn "GHCi: putStr describeModel | mapM_ print modelWiring | stageChannels | totalParams |"
  putStrLn "      encoderRF | energyTrace exampleState   to define / inspect the energy-derived model."
  where
    verdict True  = "PASS"
    verdict False = "FAIL"
