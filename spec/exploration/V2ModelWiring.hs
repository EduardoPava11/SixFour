{- |
Module      : V2ModelWiring
Description : EXPLORATION (NOT WIRED, base-only, runghc + GHCi). The CNN model wiring with REAL 3D
              conv params over the LOCKED Latent (6 channels), plus the SKI search expressed in
              ENERGY via typeclasses. Load in GHCi and read the architecture off the output: the
              layers, kernels/strides, spatial shapes, channel flow, receptive field, param count,
              and the energy descent.

  Check:  runghc V2ModelWiring.hs
  GHCi:   ghci V2ModelWiring.hs   then:  putStr describeModel
                                         mapM_ print modelWiring
                                         totalParams
                                         encoderRF
                                         energyTrace exampleState

  THE WIRING: a U-Net over the locked Latent (V2Latent, 6 channels = L,a,b,x,y,t). The encoder POOLS
  64^3 -> 16^3 (OpK = strided 3D conv = the octree distill; each k2/s2 stencil is a 2x2x2 octant =
  1 coarse + 7 detail = A7). The decoder LIFTS 16^3 -> 256^3 (OpS = transposed 3D conv = the octree
  lift, inventing detail). OpI = same-scale process conv; Halt = the PonderNet stop. The SKI ops ARE
  the CNN layers; the search is energy descent (PonderNet adaptive depth).

  sRGB only at the boundary (decode the head's 6 channels). Lab dropped. Trainer untouched.
-}
module V2ModelWiring where

import Data.List (foldl')
import V2Latent (latentChannelCount)   -- the locked latent: 6 channels (L,a,b,x,y,t)

-- ===========================================================================
-- (1) The SKI ops as CNN layer kinds + the conv params
-- ===========================================================================

-- | OpS = lift / expand (transposed 3D conv, invents detail UP a level); OpK = pool / contract
--   (strided 3D conv, DOWN a level); OpI = same-scale process conv; Halt = PonderNet stop.
data Op = OpS | OpK | OpI | Halt
  deriving (Eq, Show)

-- | A 3D conv's real parameters.
data Conv = Conv { kernel :: !Int, stride :: !Int, pad :: !Int }
  deriving (Eq)

instance Show Conv where
  show (Conv k s p) = "k" ++ show k ++ " s" ++ show s ++ " p" ++ show p

-- | One CNN layer over the locked Latent: a name, an op, the spatial in/out side, the in/out channels,
--   and the conv params.
data Layer = Layer
  { lName :: String
  , lOp   :: Op
  , lIn   :: Int, lOut :: Int       -- spatial side (16, 32, 64, 128, 256)
  , lInCh :: Int, lOutCh :: Int     -- channels
  , lConv :: Conv
  } deriving (Eq)

-- | A GHCi-readable layer line with the real conv params and param count.
instance Show Layer where
  show l@(Layer nm op i o ic oc cv) =
    pad 6 nm ++ pad 5 (show op) ++ pad 14 (show i ++ "^3->" ++ show o ++ "^3")
      ++ "ch " ++ pad 8 (show ic ++ "->" ++ show oc) ++ pad 11 (show cv)
      ++ "  " ++ show (paramCount l) ++ " params"
    where pad n str = take n (str ++ repeat ' ')

-- ===========================================================================
-- (2) The shape + parameter algebra of a layer
-- ===========================================================================

-- | The output spatial side of an op applied to an input side: transposed conv (OpS) UPSAMPLES,
--   strided / same conv (OpK, OpI, Halt) follows the standard conv formula.
convOut :: Op -> Conv -> Int -> Int
convOut OpS (Conv k s p) inS = (inS - 1) * s - 2 * p + k          -- transposed conv (lift / upsample)
convOut _   (Conv k s p) inS = (inS + 2 * p - k) `div` s + 1      -- conv (pool / process)

-- | The number of weights in a layer: a 3D conv has kernel^3 * inCh * outCh weights + outCh biases.
--   Halt carries no parameters.
paramCount :: Layer -> Int
paramCount (Layer _ Halt _ _ _ _ _)        = 0
paramCount (Layer _ _ _ _ ic oc (Conv k _ _)) = k * k * k * ic * oc + oc

totalParams :: Int
totalParams = sum (map paramCount modelWiring)

-- | The receptive field of the ENCODER (the input context each 16^3 coarse voxel sees): fold the
--   stem + pooling convs. RF_i = RF_{i-1} + (k-1) * jump; jump *= stride.
encoderRF :: Int
encoderRF = fst (foldl' step (1, 1) (map lConv encoderLayers))
  where step (rf, jump) (Conv k s _) = (rf + (k - 1) * jump, jump * s)

-- | The encoder = the layers up to (not including) the first lift (OpS): the path to the 16^3 coarse.
encoderLayers :: [Layer]
encoderLayers = takeWhile ((/= OpS) . lOp) modelWiring

-- ===========================================================================
-- (3) THE MODEL WIRING (real conv params over the locked 6-channel Latent)
-- ===========================================================================

modelWiring :: [Layer]
modelWiring =
  [ Layer "stem"  OpI  64  64  6   16  (Conv 3 1 1)   -- project the 6 Latent axes -> 16 features @ 64^3
  , Layer "down1" OpK  64  32  16  32  (Conv 2 2 0)   -- pool to 32^3 (octant distill, 2x2x2 = A7)
  , Layer "down2" OpK  32  16  32  64  (Conv 2 2 0)   -- pool to 16^3: the COARSE bottleneck
  , Layer "up1"   OpS  16  32  64  32  (Conv 2 2 0)   -- lift to 32^3 (invent detail, transposed conv)
  , Layer "up2"   OpS  32  64  32  16  (Conv 2 2 0)   -- lift to 64^3
  , Layer "up3"   OpS  64  128 16  16  (Conv 2 2 0)   -- lift to 128^3
  , Layer "up4"   OpS  128 256 16  16  (Conv 2 2 0)   -- lift to 256^3 (the super-res output)
  , Layer "head"  OpI  256 256 16  6   (Conv 1 1 0)   -- project back to 6 Latent axes (decode -> sRGB)
  , Layer "halt"  Halt 256 256 6   6   (Conv 1 1 0)   -- PonderNet stop: stable state
  ]

-- | A GHCi-printable description (run: putStr describeModel).
describeModel :: String
describeModel = unlines $
  [ "MODEL WIRING (U-Net over the locked Latent; SKI ops = CNN layers)"
  , replicate 70 '-' ]
  ++ map show modelWiring
  ++ [ replicate 70 '-'
     , "input channels    : " ++ show latentChannelCount ++ "  (L,a,b,x,y,t, the locked Latent)"
     , "coarse bottleneck : 16^3 (the 64 -> 16 encoder; OpK pools, A7 octant 1+7)"
     , "super-res output  : 256^3 (the 16 -> 256 decoder; OpS lifts, invents detail)"
     , "encoder RF        : " ++ show encoderRF ++ "^3 input voxels per coarse voxel"
     , "total parameters  : " ++ show totalParams ++ "  (hand-written forward blob)" ]

-- ===========================================================================
-- (4) THE TYPECLASSES: energy + the SKI / PonderNet search
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

-- | The search state: per-region residual energy. reduceStep resolves the highest-energy region (one
--   ponder step / one S-invention); stable when every region is at the floor (zero residual).
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
-- (5) Laws
-- ===========================================================================

-- | THE SHAPES CHAIN: each layer's computed conv output equals its declared out side, AND each layer's
--   out side / out channels feed the next layer's in (a real, connected CNN, not loose layers).
lawShapesChain :: Bool
lawShapesChain =
     all (\l -> convOut (lOp l) (lConv l) (lIn l) == lOut l) modelWiring
  && and (zipWith (\a b -> lOut a == lIn b && lOutCh a == lInCh b) modelWiring (drop 1 modelWiring))

-- | THE BOUNDARY CHANNELS: the model takes the 6 locked Latent channels in and emits 6 out (head),
--   so decode -> sRGB closes the loop. Input/output both = latentChannelCount.
lawLatentChannelsBoundary :: Bool
lawLatentChannelsBoundary =
     lInCh (head modelWiring) == latentChannelCount
  && lOutCh (last (filter ((/= Halt) . lOp) modelWiring)) == latentChannelCount

-- | THE CONV OP SEMANTICS: OpS lifts (out > in), OpK pools (out < in), OpI processes (out == in),
--   Halt is same-scale. So the U-Net goes down to 16^3 then up to 256^3.
lawConvOpSemantics :: Bool
lawConvOpSemantics =
     all ok modelWiring
  && minimum (map lIn modelWiring) == 16          -- the coarse bottleneck is 16^3
  && maximum (map lOut modelWiring) == 256        -- the super-res output is 256^3
  where
    ok (Layer _ OpS i o _ _ _)  = o > i
    ok (Layer _ OpK i o _ _ _)  = o < i
    ok (Layer _ OpI i o _ _ _)  = o == i
    ok (Layer _ Halt i o _ _ _) = o == i

-- | THE OCTANT IS A7: each pooling / lifting conv has a 2x2x2 = 8 stencil (kernel 2), the octant =
--   1 coarse + 7 detail = the A7 root lattice band split. The stem/head are 1x1/3x3 projections.
lawOctantStencilIsA7 :: Bool
lawOctantStencilIsA7 =
     all (\l -> kernel (lConv l) == 2) (filter (\l -> lOp l `elem` [OpS, OpK]) modelWiring)
  && (2 :: Int) ^ (3 :: Int) == 8                 -- 2x2x2 = 8 = 1 coarse + 7 detail (A7)

-- | THE PARAMETER BUDGET: the model is a small hand-written forward (a few tens of K params, well under
--   the ViT-scale head), every conv layer has positive params, and Halt has none.
lawParamBudget :: Bool
lawParamBudget =
     totalParams > 0 && totalParams < 100000
  && all (\l -> lOp l == Halt || paramCount l > 0) modelWiring
  && paramCount (last modelWiring) == 0           -- Halt: no params

-- | THE RECEPTIVE FIELD is real (each 16^3 coarse voxel sees a multi-voxel input context), so the
--   encoder genuinely summarizes a neighbourhood, not a single voxel.
lawReceptiveFieldReal :: Bool
lawReceptiveFieldReal = encoderRF == 6 && encoderRF > 1

-- | THE SEARCH descends energy to a stable state, non-increasing (the SKI / PonderNet engine drives the
--   forward pass to a fixpoint).
lawSearchDescends :: Bool
lawSearchDescends =
     last (energyTrace exampleState) == 0
  && and (zipWith (>=) tr (drop 1 tr))
  && reduceStep (SearchState [0,0,0]) == SearchState [0,0,0]   -- stable is a fixpoint
  where tr = energyTrace exampleState

-- ===========================================================================
-- (6) Runner + the GHCi-defining outputs
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawShapesChain            (conv shapes chain into a connected CNN)",     lawShapesChain)
  , ("lawLatentChannelsBoundary (6 Latent channels in, 6 out: decode closes)", lawLatentChannelsBoundary)
  , ("lawConvOpSemantics        (OpS lift / OpK pool / OpI same; 16..256)",    lawConvOpSemantics)
  , ("lawOctantStencilIsA7      (k2 stencil = 2x2x2 = 8 = 1 coarse + 7 detail)", lawOctantStencilIsA7)
  , ("lawParamBudget            (small hand-written forward; Halt 0 params)",   lawParamBudget)
  , ("lawReceptiveFieldReal     (encoder RF = 6^3 input voxels per coarse)",    lawReceptiveFieldReal)
  , ("lawSearchDescends         (SKI/PonderNet energy descent to a fixpoint)",  lawSearchDescends)
  ]

main :: IO ()
main = do
  putStrLn "V2ModelWiring.hs  -- EXPLORATION (NOT WIRED): CNN wiring (real conv params) + SKI search"
  putStrLn (replicate 72 '-')
  mapM_ (\(n, ok) -> putStrLn (verdict ok ++ "  " ++ n)) laws
  putStrLn (replicate 72 '-')
  let passed = length (filter snd laws); total = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  putStr describeModel
  putStrLn ""
  putStrLn ("energy trace (SKI/PonderNet descent): " ++ show (energyTrace exampleState)
            ++ "   ponder depth " ++ show (ponderDepth exampleState))
  putStrLn ""
  putStrLn "GHCi: putStr describeModel | mapM_ print modelWiring | totalParams | encoderRF |"
  putStrLn "      energyTrace exampleState   to define / inspect the model over the locked Latent."
  where
    verdict True  = "PASS"
    verdict False = "FAIL"
