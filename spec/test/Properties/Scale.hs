module Properties.Scale (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Text.Printf (printf)

import SixFour.Spec.Scale (layerLawReport, failingLayers)

-- A handful of fixed seeds (each a distinct synthetic 64³ capture). The full pipeline at
-- the real T·H·W·K is heavy, so we check a few deterministic seeds rather than a QuickCheck
-- sweep. The 124 tiny-stub property tests cover the law space; THIS proves the same spec
-- holds for every layer at the production 64×64×64×256 — i.e. generating a real 64³ GIF
-- exercises the whole contract chain.
seeds :: [Word]
seeds = [1, 2, 7]

tests :: TestTree
tests = testGroup "Scale (the spec holds for ALL layers at the real 64³)" $
  [ testProperty (printf "all layer contracts hold at 64^3 (seed %d)" s) $
      once $
        let fails = failingLayers (fromIntegral s)
        in counterexample ("failing layers: " ++ show fails) (null fails)
  | s <- seeds
  ]
  ++
  [ -- Surface the per-layer report for seed 1 as the knowledge artifact.
    testProperty "layer-law report snapshot (seed 1)" $
      once $
        tabulate "layer @ 64^3"
          [ printf "%-42s %s" n (if ok then "PASS" else "FAIL")
          | (n, ok) <- layerLawReport 1 ]
          (all snd (layerLawReport 1))
  ]
