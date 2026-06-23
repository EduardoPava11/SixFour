{- |
Module      : SixFour.Spec.CarrierL
Description : L carries the signal — the coarse/DC band is the backbone; the A/B search bands are the perturbation L re-balances. Frontier 1b, made sharp.

Frontier step 5. "SixFour.Spec.XYTLabDuality" / "SixFour.Spec.LBalanceOperator"
established that @L@ is the universal/balance axis (the octant coarse). This module
states the SHARPER relationship the user fixed (1b): __L carries the signal, and the
A/B search bands are a perturbation that L re-balances__. All four laws destructure
the real octant edge ("SixFour.Spec.OctreeCell" 'liftOct'/'unliftOct') and reuse
'SixFour.Spec.LBalanceOperator.lBalance', so they are theorems about the operator, not
prose:

  * 'lawCarrierIsDC' — @L@ IS the coarse/DC carrier: 'lBalance' equals the octant
    coarse band 'ocCoarse'.
  * 'lawZeroSearchIsCarrierFloor' — zeroing the seven search\/detail bands
    reconstructs the PURE-L floor (the constant octant, DC replicated): A/B = 0 ⇒
    nothing but the carrier. (The octant mirror of @OctreeGenome.lawZeroGenomeIsFloor@.)
  * 'lawCarrierInvariantToSearch' — L RE-BALANCES: the recovered carrier is INVARIANT
    to the search detail; destabilising A/B never moves L (delegates the octant
    reversibility @lawOctReversible'@).
  * 'lawSearchIsZeroOnConstant' — a flat carrier (constant octant, pure L, no signal
    variation) has ZERO search detail: the search bands carry only what L does not.

Additive law module, no new substrate, GHC-boot.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.CarrierL
  ( zeroDetail
    -- * Laws (QuickCheck'd in @Properties.CarrierL@)
  , lawCarrierIsDC
  , lawZeroSearchIsCarrierFloor
  , lawCarrierInvariantToSearch
  , lawSearchIsZeroOnConstant
  ) where

import SixFour.Spec.OctreeCell      (V8(..), OctBand(..), Detail, liftOct, unliftOct)
import SixFour.Spec.LBalanceOperator (lBalance)

-- | The all-zero search\/detail band (the seven sub-bands of an octant set to 0).
zeroDetail :: Detail
zeroDetail = (0, 0, 0, 0, 0, 0, 0)

-- | L IS the coarse/DC carrier: 'SixFour.Spec.LBalanceOperator.lBalance' is exactly
-- the octant coarse band — the in-range backbone the signal rides.
lawCarrierIsDC :: V8 Int -> Bool
lawCarrierIsDC v = lBalance v == ocCoarse (liftOct v)

-- | A/B = 0 ⇒ pure carrier: zeroing the seven search bands reconstructs the constant
-- octant (the carrier replicated) — the L-only floor.
lawZeroSearchIsCarrierFloor :: Int -> Bool
lawZeroSearchIsCarrierFloor c =
  unliftOct (OctBand c zeroDetail) == V8 c c c c c c c c

-- | L RE-BALANCES: the recovered carrier (coarse) is INVARIANT to the search detail —
-- two different A/B perturbations of the same carrier recover the SAME L
-- (= @c@). Delegates the octant reversibility (@liftOct . unliftOct == id@).
lawCarrierInvariantToSearch :: Int -> Detail -> Detail -> Bool
lawCarrierInvariantToSearch c d1 d2 =
  let coarseOf d = ocCoarse (liftOct (unliftOct (OctBand c d)))
  in coarseOf d1 == c && coarseOf d2 == c && coarseOf d1 == coarseOf d2

-- | A flat carrier (a constant octant — pure L, no variation) has ZERO search detail:
-- the search bands carry ONLY what L does not.
lawSearchIsZeroOnConstant :: Int -> Bool
lawSearchIsZeroOnConstant c =
  ocDetail (liftOct (V8 c c c c c c c c)) == zeroDetail
