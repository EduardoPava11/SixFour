{- |
Module      : V2EnergyArchitecture
Description : EXPLORATION (NOT WIRED, base-only, runghc + GHCi). The MISSING MAPPING: the CNN
              architecture (channels, depth, activation) DERIVED FROM the GHCi energy levels, not
              hand-picked. channels proportional to entropy; depth = the ponder depth; the activation
              IS the PonderNet energy halt-gate (plus the byte-exact lattice snap).

  Check:  runghc V2EnergyArchitecture.hs
  GHCi:   ghci V2EnergyArchitecture.hs  then:  putStr (describeDerivation axisEnergy scaleEnergy)
                                               channelsFromEnergy 128 axisEnergy
                                               depthFromEnergy scaleEnergy
                                               map (gate floorEnergy) scaleEnergy

  THE GAP THIS CLOSES (owner: "HOW are you designing the CNN without the GHCi energy levels? how do
  we know how each layer and depth and activation function map?"). The earlier V2ModelWiring picked
  channels (6->16->32->64) by hand. That is backwards. The energy levels DEFINE the architecture:
    * CHANNELS  per feature/scale = PROPORTIONAL to its ENERGY (entropy). A high-entropy axis (x) gets
      many channels; a zero-entropy axis (t) gets the floor. (channelsFromEnergy)
    * DEPTH     = the PONDER DEPTH = the number of energy-bearing regions to reduce to a stable state.
      Adaptive, not a fixed layer count. (depthFromEnergy)
    * ACTIVATION = the energy HALT-GATE: refine a region if its energy exceeds the floor, else halt it
      to the floor (a threshold nonlinearity = the PonderNet halt). Plus the byte-exact lattice snap
      (snapToLattice) as the nonlinearity that keeps the latent on the index-6 lattice. (gate, snap1)

  The energy levels come from V2EnergyWeave (per-axis entropy) and frame_energy/frame_stats (per-scale
  residual energy). Here we take them as the design INPUT. Base-only, runghc. Trainer untouched.
-}
module V2EnergyArchitecture where

-- ===========================================================================
-- (1) The energy levels = the design INPUT (the GHCi outputs)
-- ===========================================================================

-- | Per-axis ENERGY (the Shannon entropy of each latent axis, x100 to stay integer): the V2EnergyWeave
--   values [L,a,b,x,y,t] = [1.46,1.0,0.92,2.58,1.58,0.0]. This drives the per-axis CHANNEL allocation.
axisEnergy :: [Int]
axisEnergy = [146, 100, 92, 258, 158, 0]     -- [L, a, b, x, y, t]

axisNames :: [String]
axisNames = ["L", "a", "b", "x", "y", "t"]

-- | Per-SCALE residual energy (how much invention each octree rung must do): the up-rungs carry the
--   most energy (the super-res). Drives the per-LAYER channel allocation and the depth.
scaleEnergy :: [Int]
scaleEnergy = [12, 7, 18, 2, 9, 5, 1]         -- a residual-energy field over 7 regions

-- ===========================================================================
-- (2) CHANNELS from energy (proportional to entropy)
-- ===========================================================================

floorCh :: Int
floorCh = 1

-- | Allocate a CHANNEL BUDGET proportional to per-feature ENERGY (entropy). A feature with more energy
--   gets more channels; zero energy gets the floor. THIS is how a layer's channel count is decided.
channelsFromEnergy :: Int -> [Int] -> [Int]
channelsFromEnergy budget es
  | total == 0 = map (const floorCh) es
  | otherwise  = [ max floorCh (budget * e `div` total) | e <- es ]
  where total = sum es

-- ===========================================================================
-- (3) DEPTH from energy (the ponder depth)
-- ===========================================================================

floorEnergy :: Int
floorEnergy = 0

-- | The DEPTH = the PONDER DEPTH = the number of energy-bearing regions that must be reduced to reach
--   a stable state. Adaptive: a high-energy clip needs more layers, a flat one needs almost none.
depthFromEnergy :: [Int] -> Int
depthFromEnergy = length . filter (> floorEnergy) . map abs

-- ===========================================================================
-- (4) ACTIVATION from energy (the PonderNet halt-gate + the lattice snap)
-- ===========================================================================

-- | THE ACTIVATION FUNCTION = the energy HALT-GATE. Refine (pass) a region if its energy exceeds the
--   floor; else HALT it to the floor. A threshold nonlinearity, monotone, that IS the PonderNet halt.
--   (This is the activation; it maps directly from the local energy.)
gate :: Int -> Int -> Int
gate fl e = if e > fl then e else fl

-- | THE BYTE-EXACT NONLINEARITY: snap an integer to the nearest value satisfying a mod-m congruence
--   (the index-6 lattice guard). Keeps the latent on the lattice after a conv (V2Latent.snapColour).
snap1 :: Int -> Int -> Int     -- snap1 m v = the nearest v' with v' == 0 (mod m)
snap1 m v = let r = v `mod` m in if 2 * r <= m then v - r else v + (m - r)

-- ===========================================================================
-- (5) The derived wiring + a GHCi description
-- ===========================================================================

-- | Given a channel budget and the per-scale energy, DERIVE the per-layer channel counts (proportional
--   to that scale's energy) and the depth (the ponder depth). The architecture is a FUNCTION of energy.
deriveChannels :: Int -> [Int]
deriveChannels budget = channelsFromEnergy budget scaleEnergy

-- | A GHCi-printable derivation: shows energy -> channels -> depth -> activation, so the mapping is
--   visible (run: putStr (describeDerivation axisEnergy scaleEnergy)).
describeDerivation :: [Int] -> [Int] -> String
describeDerivation aE sE = unlines $
  [ "ARCHITECTURE DERIVED FROM ENERGY (channels prop entropy; depth = ponder; activation = halt-gate)"
  , replicate 70 '-'
  , "per-AXIS energy [L,a,b,x,y,t] = " ++ show aE
  , "  -> channels (budget 128)    = " ++ show (zip axisNames (channelsFromEnergy 128 aE))
  , "     (x has most energy -> most channels; t = 0 -> floor " ++ show floorCh ++ ")"
  , replicate 70 '-'
  , "per-SCALE residual energy     = " ++ show sE
  , "  -> channels (budget 64)     = " ++ show (channelsFromEnergy 64 sE)
  , "  -> DEPTH (ponder)           = " ++ show (depthFromEnergy sE) ++ " layers (energy-bearing regions)"
  , "  -> ACTIVATION (halt-gate)   = " ++ show (map (gate floorEnergy) sE) ++ "  (floor " ++ show floorEnergy ++ ")"
  , replicate 70 '-'
  , "the architecture is a FUNCTION of the energy: change the energy, the wiring changes." ]

-- ===========================================================================
-- (6) Laws
-- ===========================================================================

-- | CHANNELS TRACK ENERGY: the channel allocation is MONOTONE in energy (more energy -> at least as
--   many channels), and a zero-energy feature gets the floor. So channels are JUSTIFIED, not picked.
lawChannelsTrackEnergy :: Bool
lawChannelsTrackEnergy =
     monotone (zip axisEnergy (channelsFromEnergy 128 axisEnergy))
  && channelsFromEnergy 128 axisEnergy !! 5 == floorCh        -- t (energy 0) -> floor channels
  && channelsFromEnergy 128 axisEnergy !! 3 == maximum (channelsFromEnergy 128 axisEnergy)  -- x -> most
  where
    monotone xs = and [ if e1 <= e2 then c1 <= c2 else c1 >= c2 | (e1,c1) <- xs, (e2,c2) <- xs ]

-- | DEPTH IS THE PONDER DEPTH: the derived depth equals the number of energy-bearing regions (the
--   adaptive search depth), so a flat (low-energy) clip is shallow, a busy one is deep. TEETH: zero
--   energy -> zero depth; one extra energy-bearing region -> one more layer.
lawDepthIsPonderDepth :: Bool
lawDepthIsPonderDepth =
     depthFromEnergy scaleEnergy == length (filter (> 0) scaleEnergy)
  && depthFromEnergy [0,0,0] == 0
  && depthFromEnergy [5,0,5] == 2

-- | ACTIVATION IS THE ENERGY HALT-GATE: it halts low-energy regions to the floor and passes high-energy
--   ones, monotonically. This IS the PonderNet halt as the activation function. TEETH: at-or-below the
--   floor halts, above passes.
lawActivationIsEnergyGate :: Bool
lawActivationIsEnergyGate =
     gate floorEnergy 0 == floorEnergy                 -- at floor: halted
  && gate floorEnergy 7 == 7                           -- above floor: passes
  && and [ gate floorEnergy a <= gate floorEnergy b | a <- sample, b <- sample, a <= b ]  -- monotone
  && all (\e -> gate floorEnergy e >= floorEnergy) sample
  where sample = [-3 .. 10]

-- | THE BYTE-EXACT ACTIVATION (snap) lands on the lattice: snap1 m v is divisible by m and within m/2
--   of v (a real projection nonlinearity). TEETH: an off-lattice value is moved, an on-lattice one is not.
lawSnapIsByteExact :: Bool
lawSnapIsByteExact =
     all (\v -> snap1 3 v `mod` 3 == 0) sample
  && all (\v -> abs (snap1 3 v - v) <= 2) sample        -- moves by at most m-1
  && snap1 3 6 == 6                                      -- on-lattice: unchanged
  && snap1 3 7 /= 7                                      -- off-lattice: moved
  where sample = [-9 .. 9]

-- | THE ARCHITECTURE IS A FUNCTION OF ENERGY: different energy profiles give different channel
--   allocations and depths. So the wiring is DERIVED, not fixed. TEETH: a flat profile and a peaked one
--   produce different channels and different depth.
lawArchitectureFromEnergy :: Bool
lawArchitectureFromEnergy =
     channelsFromEnergy 64 [1,1,1,1] /= channelsFromEnergy 64 [10,1,1,1]     -- different energy -> different channels
  && depthFromEnergy [9,0,0,0] /= depthFromEnergy [9,9,9,9]                  -- different energy -> different depth
  && channelsFromEnergy 64 [1,1,1,1] == [16,16,16,16]                        -- flat energy -> equal channels

-- ===========================================================================
-- (7) Runner
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawChannelsTrackEnergy     (channels prop energy; t=0 floor, x=most)",   lawChannelsTrackEnergy)
  , ("lawDepthIsPonderDepth      (depth = energy-bearing regions, adaptive)",  lawDepthIsPonderDepth)
  , ("lawActivationIsEnergyGate  (activation = the PonderNet halt-gate)",      lawActivationIsEnergyGate)
  , ("lawSnapIsByteExact         (the lattice-snap nonlinearity lands on m)",  lawSnapIsByteExact)
  , ("lawArchitectureFromEnergy  (the wiring is a FUNCTION of the energy)",    lawArchitectureFromEnergy)
  ]

main :: IO ()
main = do
  putStrLn "V2EnergyArchitecture.hs  -- EXPLORATION (NOT WIRED): the CNN derived FROM the energy levels"
  putStrLn (replicate 72 '-')
  mapM_ (\(n, ok) -> putStrLn (verdict ok ++ "  " ++ n)) laws
  putStrLn (replicate 72 '-')
  let passed = length (filter snd laws); total = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  putStr (describeDerivation axisEnergy scaleEnergy)
  putStrLn ""
  putStrLn "GHCi: putStr (describeDerivation axisEnergy scaleEnergy) | channelsFromEnergy 128 axisEnergy"
  putStrLn "      | depthFromEnergy scaleEnergy | map (gate floorEnergy) scaleEnergy   to map energy->arch."
  where
    verdict True  = "PASS"
    verdict False = "FAIL"
