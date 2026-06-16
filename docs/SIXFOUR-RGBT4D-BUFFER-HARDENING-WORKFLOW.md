> **Status: HARDENING WORKFLOW (2026-06-16).** Design/process plan, not a status ledger
> (canonical built-state: [docs/STATUS.md](STATUS.md)). Hardens the **1b + 2b** decision: a
> *universal circular RGBT feature layer* (1b) with *semantic 4D R/G/B/T axes* (2b). Builds on
> [docs/SIXFOUR-CUBE-LADDER-GAP-ANALYSIS.md](SIXFOUR-CUBE-LADDER-GAP-ANALYSIS.md).

# Hardening the RGBT‑4D buffer (1b + 2b)

## 1. What 1b + 2b commits to

- **1b — universal feature layer.** A stride‑1, width‑4 **circular** sliding window over the 64
  frames computes, per frame, a temporal feature from its 4‑frame neighbourhood (wrapping
  `[64,1,2,3]`). This temporally-coherent substrate underlies **every** tier; 16³/64³/256³ are
  spatial/palette *views* on it. SIMT = the 64 window-threads, SIMD = the 4 lanes inside each.
- **2b — semantic 4D axes.** The 4 lanes carry **fixed R/G/B/T meaning**; the window is a genuine
  4D coordinate; the pool weights lanes by the entropy-derived `RGBTWeights`
  ([Spec.Entropy](spec/src/SixFour/Spec/Entropy.hs)). The app becomes a 4D color‑time navigator.

### 1.1 Why 1b+2b is the reality, not a luxury — RGBT *is* the reversible lifting

RGBT is the **reversible 4‑channel lifting**: a 2×2 spatial block (4 scalars) ⟷ 1 cell carrying
4 channels (R,G,B,T) — the 2D‑Haar / pixel‑shuffle bijection. The *semantic distinctness* of the
four axes (one average + three details) **is** the invertibility; a symmetric/positional pool (2a)
collapses them and **destroys reversibility**. So 2b is the precondition for two things the
product needs:

- a **lossless** `(2×2) <-> 1` ladder — nothing is lost going 64³↔16³ within captured detail, and
- synthesizing **256³ from the 16³ options** — the coarse tier reversibly holds the captured
  detail; the NN predicts *only* the genuinely-unseen sub-bands *above* captured resolution.

The spec already proves this exact reversibility on the palette axis —
`SixFour.Spec.PairTreeFixed`'s integer S‑transform (`lift`/`unlift`, exact, golden). RGBT
**generalizes that proven lifting** to the spatial 2×2 (and temporal) axes. So the ladder in
Phase 3 is a *bijection within captured resolution*; loss is confined to NN super-res beyond it.

## 2. The function it serves, and the cost it accepts (state it honestly)

Function: maximal expressiveness — a navigable R³ × S¹ (color³ × circular‑time) field, one
coherent substrate feeding all three GIF89a products. **Cost:** 2b assigns fixed lane semantics,
which **breaks the C₆₄ rotational gauge** the loop hands you for free (1a+2a kept it). A semantic
"R" implies a privileged phase. **Hardening = paying that cost rigorously, not pretending it isn't
there.** Phase 0 exists solely to tame it; if Phase 0 can't be made deterministic and
device-stable, fall back to a *fixed* phase (capture-start = phase 0): trivially deterministic, still fully reversible — you lose content-adaptivity, NOT the lifting. (2a is no longer an option: §1.1 — it can't be reversible.)

## 3. The hardening spine (every phase obeys it)

`ghcid` (live) → `cabal test` (laws + golden gate) → `cabal run spec-codegen` (regen contracts,
zero drift) → `spec/scripts/spec-docs.sh` (Haddock + Hoogle). New `Spec.*` module ⇒ `Map` entry +
`{- | … -}` header + 100% Haddock. Float reference + Q16 twin; golden vectors pin every numeric
surface; the Swift/Metal port is verified **bit-for-bit** against them. No law without a predicate.

## 4. Phases

> **Progress (2026-06-16):** keystone **RGBTLift** ✅ — the `(2×2)↔1` bijection, `lawLiftUnliftExact`,
> exact in Q16. **Phase 0 `CanonicalPhase`** ✅ — necklace gauge-fix, rotation-invariant
> (`lawCanonicalGaugeFixed`); proving it caught the naïve argmax+lowest-index rule failing under
> ties. **Phase 1 circular buffer** ✅ — `GroupRGBT.circularWindows` (stride-1 width-4, the SIMT
> buffer) with role-orbit, wrap, and rotation-equivariance laws. All golden-gated; 820 spec tests
> green. **Phase 2 `RGBTFeature`** ✅ — the 1b feature layer: entropy-weighted temporal coherence over
> the buffer (per-frame-count, completeness/in-gamut, R-weight-identity, gauge-equivariance laws);
> 824 spec tests green. **Phase 3 `CubeLadder`** ✅ — the 16³/64³/256³ tiers as reversible 2-D-Haar views (LADDER BIJECTIVE
> within capture, synthBeyond = nearest-neighbour floor, gamut-closed distill); 830 spec tests green.
> **Phase 4 golden vectors** ✅ — FNV-1a-64 Q16 pins for the cube-ladder distill/synthBeyond and the
> necklace canonical form (byte-exact targets a Swift/Metal port must reproduce); 834 spec tests
> green. Next: Phase 5 — the hand-written Swift/Metal simdgroup port (the shipped-app step)
> Q16+port → Phase 6 validation.

### Phase 0 — Gauge-fixing contract (THE keystone; tames the 2b symmetry break)
Because 2b needs a privileged phase, define a **canonical-phase rule**: a deterministic rotation
of the 64‑cycle that fixes which frame is "phase 0", so the R/G/B/T assignment is reproducible
Mac↔device. Candidate rule: rotate so a deterministic scalar is maximal (e.g. the
significance/energy peak frame), ties broken to the lowest index.
- New `Spec.CanonicalPhase` (or extend `Spec.Cyclic`). Laws (EXACT): `lawCanonicalPhaseTotal`
  (always defined), `lawCanonicalPhaseDeterministic` (same cube → same phase),
  `lawPhaseTieBreakLowest`, `lawPhaseStableUnderQ16` (float and Q16 agree — device-safe).
- **Done = gauge-fixing is total, deterministic, Q16-stable.** If a *content-adaptive* phase won't stabilize → fix phase 0 = capture-start (still reversible; loses only adaptivity, never the lifting).

### Phase 1 — The circular buffer (content-independent combinatorics)
Stride‑1, width‑4 circular sliding window. Index structure only — exact, no floats.
- Extend `Spec.GroupRGBT` (today: consecutive disjoint) with `circularWindows`. Laws (EXACT):
  `lawWindowCount` (64 windows), `lawEachFrameInFourWindows`, `lawRoleOrbitComplete` (each frame
  visits R,G,B,T exactly once across its windows), `lawCircularWrap`, `lawWindowsCoverCycle`.
- **Done = the buffer index structure is golden-pinned and integer-exact.**

### Phase 2 — Semantic 4D feature map (1b + 2b core)
The window → 4D coordinate; the per-frame temporal feature, lanes weighted by `RGBTWeights`. The
substrate every tier reads.
- New `Spec.RGBTLift` (the reversible 4‑channel lifting; reuse `PairTreeFixed`'s integer S‑transform). Laws: **`lawLiftUnliftExact`** (`unlift∘lift = id` AND `lift∘unlift = id`, integer-exact — the `(2×2)<->1` bijection that makes the ladder lossless), **`lawFeaturePreservesCompleteness`** (CompleteVoxelVolume / the
  "every pixel filled" invariant survives — non-negotiable), `lawFeaturePerFrameCountUnchanged`
  (64→64; 1b keeps per-frame), `lawFeatureDeterministic`, `lawFeatureUsesEntropyWeights`,
  `lawFeatureUniformWeightsReducesToMean` (sanity floor), gauge-consistency with Phase 0.
- **Done = the feature layer is proven to preserve completeness and consume the entropy weights.**

### Phase 3 — Tiers as views on the feature layer (1b)
16³/64³/256³ as spatial/palette views over the one feature substrate. Reuse
`Export.downsample2D`/`replicate2D` (spatial) + `Upscale256`/synth (temporal up) + the stride
ladder; palette scope (`Spec.Entropy.scopeVerdict`) stays orthogonal.
- Laws: reuse `lawCubeLadder`, `lawDownsampleGamutClosed`; add `lawAllTiersShareFeatureLayer` (the
  1b property), and the **reversibility** laws: the captured ladder is a bijection (à la `PairTreeFixed`) — `Distill∘Synthesize = id` AND `Synthesize∘Distill = id` *within captured resolution* (`lawLadderBijective`). The ONLY non-invertible step is NN super-res *beyond* capture (`lawSynthBeyondCaptureIsPredictive`); loss is isolated there, never in the ladder.
- **Done = all three tiers read one substrate; the captured ladder is a proven bijection; loss is confined to NN-predicted detail above capture.**

### Phase 4 — Golden + Q16 numeric hardening
Index structure exact-integer; weighted feature in Q16; FNV golden checksums per surface;
cross-language pinned (Mac spec ↔ device). **Done = byte-exact fixtures emitted; codegen no drift.**

### Phase 5 — Port: hand-written Swift/Metal simdgroup forward pass (the payoff)
The SIMD/SIMT mapping is now literal: the width‑4 circular window is a `simd_shuffle` stencil
(SIMD over the R/G/B/T lanes); the 64 windows tile a simdgroup/grid (SIMT over frames). Zero-dep
(Metal only). **Done = the kernel is bit-identical to the Phase‑4 golden vectors on device.**

### Phase 6 — Statistical validation against the problem space
Run the entropy‑grid × stride experiments
([CubeLadderEntropyExperiments](spec/experiments/CubeLadderEntropyExperiments.hs), scaled) on the
1b+2b structure: confirm the feature layer + semantic weights behave across the swept envelope,
with pre-registered accept criteria and CIs. **Done = the design holds across the modeled space,
not just point cases.**

## 5. Risk register — what hardening must confront

- **R1 (keystone) — broken C₆₄ symmetry.** Mitigated by Phase 0's canonical-phase rule. *Residual:*
  a content-defined phase can be unstable near ties; `lawPhaseStableUnderQ16` + lowest-index
  tie-break are the guard. If unstable in practice → 2a is the fallback.
- **R2 — completeness must survive.** The feature layer must not drop the per-frame "every pixel
  filled" guarantee. `lawFeaturePreservesCompleteness` is a hard gate, not a nicety.
- **R3 — content-adaptive determinism.** The 2b weights are content-dependent, so the feature is
  content-adaptive; golden vectors must fix a specific capture, and weights must be Q16 so
  Mac↔device agree bit-for-bit. (This is why Phase 0/2 carry Q16-stability laws.)
- **R4 — complexity vs "powerful *simple*".** 1b+2b is the power path. See §6.

## 6. Keep the product simple: gate the power mode

Form-follows-function still applies to the *shipped* surface. Harden 1b+2b behind a **versioned
feature flag** (the repo's `colorAtlas`-flag pattern): the default product stays the simple
gauge-symmetric path; the 4D‑navigator power mode is opt-in. This keeps "powerful **simple** GIF
maker" true while the hardened 4D substrate exists underneath for the users who want it.

## 7. Sequencing

Phase 0 gates everything (it decides whether 2b is even viable). Then 1 → 2 → 3 are the spec
build; 4 → 5 are golden+port; 6 validates. Each lands behind the flag (§6) until Phase 6 passes.
