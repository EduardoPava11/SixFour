module Properties.ActDecisions (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ActDecisions

tests :: TestTree
tests = testGroup "ActDecisions (five-acts decision algebra)"
  [ testProperty "lawDecisionBudget — every act <= maxDecisionsPerAct"
      lawDecisionBudget
  , testProperty "lawEventCoversDecisions — every dEvent is a real Display.Event"
      lawEventCoversDecisions
  , testProperty "lawCompletionIsEvent — every completionFor is a real Display.Event"
      lawCompletionIsEvent
  , testProperty "lawCompletionDistinct — completionFor not among the act's decisions"
      lawCompletionDistinct
  , testProperty "lawNoButtons — every dSurface is a real cell-field surface"
      lawNoButtons
  , testProperty "lawDecisionsDistinct — no duplicate decision events per act"
      lawDecisionsDistinct
  , testProperty "lawActsExhaustive — decisionsFor total over all 5 acts"
      lawActsExhaustive
  , testProperty "lawTableMatchesGolden — live table == pinned golden"
      lawTableMatchesGolden
  ]
