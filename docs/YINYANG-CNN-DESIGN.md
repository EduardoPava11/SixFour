# YINYANG-CNN-DESIGN — the inference-learning CNN, derived not designed

*Every box below cites the law that forces it. Structural invariants gated in
`Spec.YinYangCNN`; companions: the whole 2026-07-03/04 spec stack. 2026-07-04.*

## The diagram

```
INPUT  three bin streams (ColorHead), root-chart color (L, α₁, α₂) + mass channel
       16²@5Hz          32²@10Hz          64²@20Hz     [OpponentDerivation: root
          │                │                 │          chart keeps S₃ integral]
══ YIN (inference, K-direction — FROZEN EXACT, zero parameters) ═══════════════
          │                │                 │
          └── all-ones stride-2 convs = the sums carrier ──┘
              [YinYangCNN lawEncoderIsAllOnesConv; K is a theorem (MixSKI)]
              per-axis K_x, K_y, K_t available (AxisSKI) — anisotropic taps
══ YANG (learning, S-direction — ALL the parameters) ══════════════════════════
   per rung transition (16→32, 32→64), per axis stage:
   ┌─────────────────────────────────────────────────────────────────┐
   │ S_t head: width 1/block, CAUSAL, un-tied (reversal-ODD targets —│
   │           AxisSKI lawZeroSectionIsArrowBlind; t-reversal aug    │
   │           NEGATES t-band targets — OctantViews flip law)        │
   │ S_y head: width 2/block ─┐ tied by INTEGER symmetrization       │
   │ S_x head: width 4/block ─┘ H' = H + π∘H∘σ (lawSwapTying…)       │
   │           widths {1,2,4} forced: lawStagedExpansionCounts…      │
   │           (sum = 7 = rank A₇ — RootLatticeDetail)               │
   └─────────────────────────────────────────────────────────────────┘
   targets: the graded bands = mixed discrete derivatives (KinematicLadder)
   conditioning: position (the I-JEPA redirect, CLAUDE.md) + coarse context
══ GATES (what is NOT learned decides what is) ════════════════════════════════
   certified order per slot  → halting-prior FLOOR (KinematicHaltPrior;
                               kinematic.zig on device, exact integers)
   W = 1 concentrated blocks → skipped, zero conditional bits (TriScaleTraining)
   mass (photons, x420 path) → inverse-variance loss weights (shot noise note)
══ HEADS ABOVE THE HEADS ══════════════════════════════════════════════════════
   MIX head: proposes the per-region depth VECTOR (d_x,d_y,d_t) — the section,
             the gene (MixSKI; AxisSKI: the gene decomposes by axis; time-taste
             and space-taste are different inheritable objects)
   trained by: user picks (ChoiceTraining, Bradley–Terry — AtlasTrainer proof)
             + cube strokes as full WHERE+DEPTH labels (CubeBrush)
   safety:   no mix can move the coarse marginals (lawMixesShareCoarseViews)
══ OUTPUT ═════════════════════════════════════════════════════════════════════
   the custom 64³ GIF: real bins at chosen depths (v1), θ_up invention inside
   grants (upgrade path); GCT from the 16-rung; delays 5/10/20 cs (time law)
```

## Why "yin-yang" is the architecture and not a slogan

- The DOWN path produces the UP path's labels (coarse = pool(fine), free, exact) —
  wake-sleep's mutual generation with one side a theorem (the training-occurs proof:
  arm 1 free, arm 2 learns, arm 3 floors).
- The UP path's residuals train the halting that allocates the DOWN path's compute
  (certified order = cheapest zero-loss halt, derived from the objective).
- The user's inference-time choices train the mix head whose proposals the user next
  corrects (ChoiceTraining) — the outermost loop, with the user as the gate.
- Budget: all three scales for 9/8 the finest (TriScaleTraining); question load and
  S-packets both scale with genuine ambiguity, per axis.

## Parameter accounting (the θ_up lineage)

Per transition: S_first(1) + S_second(2) + S_third(4) outputs per block, x/y tied →
two independent spatial stages + one causal temporal stage. Two transitions + one mix
head. Base nets in the 21p–6K range (V3.0 lineage); trained MLX-side, per-capture TTT
via RungDispatch (12.4 ms/step proven); hand-written forward on device (Tier-2, zero
deps); floats re-enter the Zig Q16 floor before touching bytes (the contract).

## Open (Daniel)

- Axis order for the staged expansion (t-first = temporal detail conditioned on
  spatial coarse, or t-last = spatial first)? Counts are order-invariant ({1,2,4});
  the CONDITIONING structure is not. Recommend t-last: spatial context helps motion.
- Does the mix head share a trunk with the band heads or stand alone? (Shared trunk =
  taste informed by content; standalone = simpler gene carriage in S4GX.)
