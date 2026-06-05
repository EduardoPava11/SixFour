# Competition — a per-user Quality-Diversity population of look-cores

> **SUPERSEDED (2026-05-27) by the continuous pivot.** The `hue × variety` MAP-Elites
> grid below was keyed by the 11 Berlin–Kay categories — deleted with the rest of the
> categorical substrate (`Spec.Competition` is gone). MAP-Elites needs a discrete
> coordinate system; the fully-continuous design has no such grid. The replacement is
> **`SixFour.Spec.Preference`**: taste = a latent-utility model over a continuous palette
> embedding (Bradley–Terry / GP, Chu & Ghahramani 2005), learned from pairwise
> pin/swipe; the **gallery** = a DPP-diverse, utility-weighted subset (greedy MAP on the
> quality-weighted L-ensemble — the unstructured-archive / AURORA / Novelty-Search
> lineage, no niches). The reused scaffold (`OrganDescriptor`, `GeneStore`, ES/federation
> by seeds+rewards) still applies; only the *category niche axis* is gone. The notes
> below are kept for the ES/PBT/on-device-feasibility reasoning, which is unchanged.

Working notes (2026-05-26). How SixFour makes **each installed app unique** by
running an on-device population of the tiny look-core that **competes** under the
user's taste. Companion to `NN_SPACE_NOTES.md` and `LOOKNET_LAYERS.md`. The pure
core is mirrored by `SixFour.Spec.Competition`.

## The idea

The learnable core (LookNet L3–L5) is tiny (~10³–10⁴ params). Duplicate it into a
**population** and let copies compete. Competition needs a fitness — and we already
built one (Phase A): Birkhoff `M = unity/variety` plus the user's feedback. Because
the core is tiny and the fitness is palette-level, a whole population is cheap to
run and score.

Two decisions fix the character:
- **Quality-Diversity (MAP-Elites), not a single winner.** Keep an *archive* of
  diverse-but-beautiful palettes, one per niche. This is the gallery the user
  browses and pins — and it dodges the measured collapse (Phase A: a single fitness
  drives everyone to redblue+neutrals).
- **The reward is the user.** Pin / swipe / keep / export = the reward signal. Each
  device's archive diverges under its own user → that *is* the per-app uniqueness.

## The four questions

**1. How does competition vary?** The machinery is identical on every device; the
*archive* diverges because it is shaped by that user's feedback. Variation =
personalization. (Secondary: the choice of QD niche axes.)

**2. How many competing NNs?** Bounded by **battery/thermal, not FLOPs**. A small
archive — start a `hue × variety` grid of `11 × 6 = 66` cells (we use these in
`Spec.Competition`), each holding one tiny core — is cheap on A19 and is also the
right size for a *browsable* gallery. Not thousands. The grid size is a measurement knob.

**3. Rewards in the form of compute (PBT + Hyperband / successive-halving).**
Promising cells earn more: more generations, longer survival, and **deeper inference
ponder `N` → higher quality the user sees**. Compute is the prize; the user is the
judge. On a compute-scarce phone, *allocating* the budget to promising members is the
whole mechanism — winners literally get to think longer.

**4. How do we model and train it?** **Gradient-free QD evolution** as the outer
loop: perturb a genome, decode → palette, score by fitness, keep the best per niche
(MAP-Elites elitism). Forward-pass only — no backprop through the dither/argmax or
the non-differentiable user reward — and it federates by sharing only **seeds +
scalar rewards** (Evolution Strategies, Salimans 2017). MLX-Swift is available for
optional gradient refinement of a champion, but the outer loop is evolution.

## On-device feasibility (iPhone 17 Pro · A19 Pro · iOS 26)

- **Hardware:** 16-core ANE + per-GPU-core neural accelerators, ~13.4 TOPS INT8,
  12GB / 76.8 GB/s. Runs FLUX diffusion on-device.
- **Frameworks:** MLX runs on iPhone with a Swift API; 0.5B–4B LLMs fine-tune
  on-device in <1GB. Our core is ~1000× smaller ⇒ a *population* trains/scores
  comfortably. iOS 26 Foundation Models ships the **LoRA/adapter on-device
  personalization** pattern (privacy-first, nothing leaves the device) — the exact
  template for per-user uniqueness.
- **Verdict:** compute is not the limit. The work is the *loop design* and the
  battery/thermal budget. A population of tiny adapter-cores, evolved by user
  feedback, is well within the iPhone 17 Pro / iOS 26 envelope.

## Architecture

```
   per-device QD archive (hue × variety grid, 66 cells)
        every cell = one tiny look-core + its palette + fitness
                         ▲                         │
        user feedback ───┘  (pin/swipe/keep)       ▼  decode → palette → niche
        = reward            evolve (ES): perturb genome, score, keep best per cell
                            compute allocated to promising cells (PBT/Hyperband)
   lineage  : OrganDescriptor.generation / parentHashes  (already exists)
   storage  : GeneStore (already exists)
   federate : iroh "share" / AirDrop — exchange seeds + rewards (ES), opt-in
```

The genome is abstract. **v1 = direct encoding** (the 768 Haar palette coefficients)
so the QD machinery runs on synthetic data with no net. **v2 = indirect encoding**
(the core's weights) once MLX-Swift is wired.

## What exists vs. what's new

- **Reuse:** `OrganDescriptor` (generation/parentHashes = ready-made ancestry),
  `Composition` (phenotype), `GeneStore` (load/persist), `AirDropHandler` (move
  genes), and the Phase-A fitness oracles (`Pair.complementPairAvailability`,
  `Diversity.effectiveDim`, `PairTree`).
- **New (this pass, Haskell):** `Spec.Competition` — the pure core (niche map,
  fitness, archive elitism, ES update, lineage) + laws.
- **New (flagged phases):** a `studio` Rust QD-loop prototype on synthetic palettes
  (on the Mac mini); the iOS MLX-Swift on-device population + user-feedback capture +
  optional `iroh` federation.

## Open / to measure

- Archive grid size and niche axes (hue×variety is the start; mood/temperature are
  candidates).
- Generation cadence and compute-allocation schedule under real battery/thermal.
- Genome encoding (direct palette vs core weights) — direct first.
- When/whether to add MLX gradient refinement of champions.
