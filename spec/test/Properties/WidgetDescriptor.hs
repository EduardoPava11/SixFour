module Properties.WidgetDescriptor (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.WidgetDescriptor

tests :: TestTree
tests = testGroup "WidgetDescriptor (one row = geometry + mechanics + render; a faithful view of its owners)"
  [ testProperty "lawDescriptorMatchesClass: every geometry field equals its ColorWidget source" $
      once lawDescriptorMatchesClass

  , testProperty "lawDescriptorMatchesMechanics: every feel field equals its mechanicsFor source" $
      once lawDescriptorMatchesMechanics

  , testProperty "lawDescriptorTotal: one row per identity, keyed by identity" $
      once lawDescriptorTotal

  , testProperty "lawScopeCoherent: GifField ⇒ ScopeNone, palette modes ⇒ a real scope" $
      once lawScopeCoherent
  ]
