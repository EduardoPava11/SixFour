module Properties.HaarRibbon (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.HaarRibbon

-- The HaarRibbon laws are nullary predicates over the module's fixed internal fixture
-- (Act III's 2⁸ Haar abstraction ribbon), so each is a single deterministic check.
tests :: TestTree
tests = testGroup "HaarRibbon (Act III — 2⁸ Haar abstraction ribbon)"
  [ testProperty "ribbon group count is monotone down the scroll" $ once lawRibbonMonotone
  , testProperty "top of the ribbon is the full 256-leaf palette"  $ once lawRibbonTopIsFull
  , testProperty "bottom of the ribbon is the global core"          $ once lawRibbonBottomIsCore
  , testProperty "a protected leaf is never merged"                 $ once lawProtectedNeverMerge
  , testProperty "ribbon groups partition all slots (total cover)"  $ once lawRibbonPartitionTotal
  , testProperty "protecting refines (never coarsens) the ribbon"   $ once lawProtectRefines
  ]
