# V1 Deprecation Candidates (READ-ONLY CROSSWALK)

> BANNER: This file proposes RETIREMENT CANDIDATES ONLY. It is pure analysis. No V1
> element named here should be deleted, moved, or gated off without a separate,
> fully gated change (cabal test + Map/compartment wiring + hermetic codegen +
> cross-tier golden, per CLAUDE.md's byte-exact contract). Nothing below has been
> verified against the live source this pass; every row is a hypothesis to confirm.

## How to read the categories

- REPLACED-BY-V2: a V2 module exists (exploration or planned) that subsumes this
  element's role; V1 element becomes redundant ONCE V2 lands gated.
- SHARED-SUBSTRATE: colour-ring-agnostic or boundary machinery V2 explicitly KEEPS;
  do not touch.
- ORPHANED-ALREADY: already deleted or already gated unreachable in V1; retirement
  is bookkeeping, not a behavioural change.
- KEEP-AS-IS: live shipped surface with no V2 successor; retiring would remove
  function with nothing to replace it.

GATE RISK is rated by what golden / test / codegen / Zig fixture would go red if the
element were removed today, before its V2 successor is gated green cross-tier.

---

## Crosswalk

| V1 element | category | V2 module that replaces / subsumes | GATE RISK of retiring now | confidence |
|---|---|---|---|---|
| Per-frame palette path (`StageA`, `Palette`, `QuantFixed`, `GMM`, `Bures`, `Diversity`, `Coverage`, `Significance`, `SignificanceFixed`) | SHARED-SUBSTRATE | none (V2 keeps per-frame palette as NN input; `CoarseIsPalette.coarseEqPalette :: PaletteCells :~: 256` proves a 16-cube coarse frame IS a 256-palette) | CATASTROPHIC. This is the shipped MVP1 input. Removing it breaks the whole per-frame golden chain and the type-level `Refl`. Not a candidate. | high |
| Global GIFB palette path (`Collapse`, `GlobalCollapseQ16`, `GlobalVolume`, `Cyclic`, `Barycenter`, `Entropy`) | ORPHANED-ALREADY (gated off) | partial: V2 RGB-native collapse would be a future M-stage, not yet written | MEDIUM. Implemented + golden-gated but unreachable behind `Feature.globalPaletteV2 = false`. `GlobalCollapseQ16`/`s4_global_collapse` carries a Zig byte-exact golden + PaletteScope HARD-MUST-1 gate that would go red if pulled. The golden is what makes deletion non-trivial despite being unreachable. | med |
| sigma-pair genome math (`SigmaPairFixed`, `SigmaPairHead`, `SigmaDecomp`, `ThetaToDelta`) feeding `LeafOverride`/`s4_leaf_override` | ORPHANED-ALREADY (look-net consumer deleted) | none in V2 (no successor; the look-NN that consumed it is gone) | MEDIUM. The look-NET is retired, but the sigma-pair GENERATOR survives in category 4 with `s4_leaf_override` Zig kernel + leaf golden (the same kernel that hid a confirmed silent-overflow ship bug). The form is pinned `Net.hs slotLookDims -> NetContract.swift + net_shape.py`. Removing it touches a cross-tier contract with no V2 replacement. | med |
| MLX look-NN global-palette net (`Net`, `LookNet*`, `LookNetD`, `LookNetR`, `Loss`, `PaletteOracle`, `PaletteSearch`, `LookCore`) + deploy blob (`s4_load_look_net`/`loadLookNet`) | ORPHANED-ALREADY (deleted 2026-06-23) | `PerScaleWeights` (one weight-tied block) + `ScalePonder` (scalar halt) supersede `LookNetR`; `V2ModelWiring` energy-derived U-Net supersedes hand-picked widths | LOW. Deploy blob already deleted "one truth" 2026-06-23. Residual risk = stale references in build phase / Codegen if any Map link still points at the deleted modules. | high |
| A/B preference Atlas learned core (`AtlasBoard`, `AtlasGame`, `AtlasNetEval`, `BoardQ16`, `GLRM`, `GumbelSearch`, `Proposer`, `ValueHead`, `PersonalGenome`) | ORPHANED-ALREADY (deleted 2026-06-23) | `LatentNavigation` ("A/B is the degenerate 1-step case") + `NudgeStep`/`SteeringSpine` | LOW. Already deleted. CLAUDE.md still names MPSGraph on-device train mechanism in `SixFour/Atlas/`; confirm no live Swift target references the deleted learned core. | high |
| A/B genome codec + move math (`ABSurface`, `GenomePair`, `GenomeBlend`, `GenomeCarrier` S4GN, `IsometryMove`, `DivergenceSchedule`, `MoveRadiusSchedule`, `PaletteGesture`, `GroupRGBT`, `Quad4`/`Quad4Fixed`, `Bottleneck16`) | REPLACED-BY-V2 (surface), but math still listed | `LatentNavigation`/`NudgeStep`/`SteeringSpine`/`TwoMoveOctave` (the steering replacement); `IsometryMove` is OKLab-Q16, replaced by V2 opponent-latent moves | MEDIUM-HIGH. `IsometryMove` is an exact delta-preserving Q16 OKLab move and `GenomeCarrier` is a GIF byte codec, both likely golden-pinned. The app has NO post-capture UX after A/B retirement, so the FSM is dead UX but the codec/move math may still be referenced by goldens. Needs grep before any pull. | med |
| OKLab substrate (`Color`, `ColorFixed`, `CubeTensor` Q16 OKLab, `SynthesisPolicyValue`, OKLab arm of `CaptureFormat`) | REPLACED-BY-V2 (target) | V2-PLAN/RGB-FIRST-CLASS: `RGBProjection` (sRGB8 = model encoding), Eisenstein `ℤ[ω]` chroma; `contractSRGB8IsModelEncoding` replaces `contractQ16NotRecoverableAcrossGif` | HIGH. OKLab deprecation is explicitly DEFERRED to follow-on M1b in RGB-FIRST-CLASS, AFTER M1+M2+M3 are green cross-tier. `linearToOklabQ16`/`oklabToSrgb8Q16`/`srgbToOKLab` feed `CubeTensor` and every floor/collapse/upscale256 golden. Pulling before M1b regenerates the entire golden corpus. This is the substrate swap, not a leaf prune. | high |
| Q16 floor + `zero-genome == floor` short-circuit | SHARED-SUBSTRATE | none (V2 drops OKLab but keeps the Q16/sRGB8 boundary discipline; "integer floor stays the only bit-exact substrate") | CATASTROPHIC. The byte-exact spine. V2 explicitly retains boundary discipline. Not a candidate. | high |
| theta_B / `MaskedBandForward` (`MaskedBandPrediction` 63-param, `MaskedBandForward` Swift, `MaskedBandTrainer`, `MaskedBandGolden`) | SHARED-SUBSTRATE / LIVE | none (V2's SKI/PonderNet residual search RIDES ON this asymmetric I-JEPA predictor; `lawDepth1ReducesToFeaturesBPos` collapses `LargeJepaHead` to it) | CATASTROPHIC. The only shipped learned object, hand-written byte-exact Swift forward, `MaskedBandGolden` fixture. V2 builds on top of it. Not a candidate. | high |
| JEPA / EBM spine (`JepaTarget`, `JepaData`, `JepaMemory`, `EncoderFrozen`, `DualEncoderJepa`, `LargeJepaHead`, `HJepaLevels`) | SHARED-SUBSTRATE / CURRENT | none (V2 = opponent-literal-latent refinement of this same H-JEPA spine) | HIGH. `EncoderFrozen.encoderParamCount == 0` and `JepaData.lawDataEngineRoundTrips` are load-bearing. V2 extends, does not replace. Not a candidate. | high |
| `RGBTLift` / `OctreeCell.liftOct` reversible integer S-transform | SHARED-SUBSTRATE | none (V2 "one rung = 2 octree levels" = `reconstruct256` = `liftOct`/`octantLift` twice; proven colour-ring-invariant by `V2Hylo` and `V2RgbEisenstein`) | CATASTROPHIC. The colour-agnostic carrier V2 ports byte-for-byte. `SubstrateDomain` bound, ZIG-floor shipped. Not a candidate. | high |
| `LookNetR` / Mixture-of-Recursions | REPLACED-BY-V2 | `PerScaleWeights` (replaces the weight-tied block), `ScalePonder` (replaces scalar PonderNet halt) | LOW-MED. Map already records the replacement. Risk only if a build-phase or Codegen path still emits `LookNetR`. The replacements are in-spec V1.5 organs, not yet V2-gated, so confirm they are independently green first. | med |
| Gaussian-chroma `ℤ[i]` knob (`GaussianChroma`, `ChromaUnitGauge`, `ChromaUnitMinimizer`, `DualCube`, `ChannelProduct`) | REPLACED-BY-V2 (target, contested) | Eisenstein `ℤ[ω]` (`V2RgbEisenstein`, `V2EisensteinPrime`, `V2TrainingLattice`); RGB-FIRST-CLASS M2 adds `ℤ[ω]` ALONGSIDE not replacing | HIGH. V2-FITS-THE-MODEL flags that Eisenstein C6-mod-(1-ω) CONTRADICTS the live Gaussian C4 determinism floor (`ChromaUnitGauge.lawUnitGroupIsoQuarterTurn`). Seven `ℤ[i]` consumers untouched. RGB-FIRST-CLASS Q2 explicitly leaves "two rings coexist vs full rewire" as an OPEN owner fork. Retiring now would break the C4 determinism floor with no gated C6 substitute. | high |
| `CarrierL` / `RelationalMemory` {L,t}-anchor | ORPHANED-ALREADY (retired in-spec) | `DualCube.lawNoPrivilegedCarrier` already retires the {L,t}-carrier story | LOW. Map records `lawNoPrivilegedCarrier` already supersedes it. Confirm no remaining consumer of the L-anchor carrier path. | med |
| `RelationalResidual` P6 `(L,a,b,x,y,t)` (OKLab-based) + `safeNudge` | REPLACED-BY-V2 | `V2Latent` opponent-literal `[L=R+G+B, a=R-G, b=R+G-2B, x,y,t]`; `V2ProjectionScope` opponent algebra | HIGH. This P6 is the DIRECT ancestor of the V2 latent but is OKLab-typed; field names still say Lab (V2-HARDENED flags "P6 relabel unhardened"). Retiring is coupled to the OKLab swap (M1b) and to wiring V2Latent into spec, neither gated yet. | med |
| `RelationalMemory` `d6` (flat L1) + `phi6` (a<->x, b<->y, L<->t) + 14-int residual | REPLACED-BY-V2 (phi6 demoted, d6 to be energy-weighted) | `V2DualityTest` (phi6 SURVIVES-WEAKENED to label-only set-involution, loses search-plane lattice iso); `V2EnergyWeave` (energy-weighted d6 forces phi6) | MEDIUM. phi6 is V1-only and provably breaks under Eisenstein (ℤ[i] D4 order-8 vs A2 D6 order-12). But the energy-weighted d6 that would replace flat-L1 d6 is PROSE-ONLY (`V2EnergyWeave` has no PASS line). No gated successor yet; retiring d6 leaves the metric undefined. | med |
| `Dim6` (phi6 involution / register split) | REPLACED-BY-V2 (partial) | V2 keeps register split, drops marquee phi6 gesture (phi6 = bookkeeping set-involution only) | LOW-MED. Partial-adopt per memory. Low behavioural risk but confirm no render path depends on phi6 as an automorphism. | med |
| Steering chain (`NudgeStep`, `LatentNavigation`, `SteeringSpine`, `TwoMoveOctave`, `DisplayDecoder`, `ContinuousLoop`) | KEEP-AS-IS (0% Swift, unbuilt) | V2 nudge: `V2SkiResidualOrder` word + RGB-FIRST-CLASS M5 NudgeWord (BLOCKED on the 3.3 carrier typecheck fix) | LOW to retire / HIGH to rely on. Entirely 0% Swift, Core AI socket `CoreAILInference` ORPHANED. RGB-FIRST-CLASS Q6 explicitly asks whether `NudgeStep` stays demoted in-spec or is retired. M5 carrier (`[[Detail]]` vs `LatentTail`) is unresolved (Q5). Safe to demote, NOT safe to assume V2 replaces it yet (V2 successor does not typecheck). | med |
| `PonderBudget` | REPLACED-BY-V2 | `CellNudge` (rank-3, 9-channel) SUPERSEDES `PonderBudget` per DIGEST | MEDIUM. DIGEST open blessing #6 = "retire PonderBudget for CellNudge". But CellNudge rank-3 honesty is itself flagged as needing re-verification under OKLab->RGB/Eisenstein re-basis (DIGEST open Q). Successor not re-validated. | med |
| Grayscale-L look-net / Core AI L-inference (`SixFour/CoreAI/`, `trainer/coreai_export/`) | ORPHANED-ALREADY (deleted 2026-06-26) | none needed (encoder needs no learned L; `EncoderFrozen` param-free tokenizer) | LOW. Already deleted in the L-anchor pivot cleanup. Residual: `coreai_export -> L.aimodel` path noted ORPHANED; confirm the stub is fully unreferenced. | high |
| `ParadigmSoundness` master theorem + `Model`/`ModelIO`/`ModelForward` boundary | SHARED-SUBSTRATE / CURRENT | none (current "Held-Out Full-Matrix H-JEPA"; V2 rides this) | HIGH. `lawParadigmIsStructurallySound` (TRUE at w_value=1) + honesty markers `contractDescentOnRealDataUnproven`/`contractEmpiricalSoundnessUnproven`. Not a candidate. | high |
| `CaptureFormat` (sRGB8+index canonical, Q16 internal-only) | SHARED-SUBSTRATE | V2 RGB-FIRST-CLASS reuses + reframes (`contractSRGB8IsModelEncoding`); Q16-vs-sRGB8 tension VANISHES under V2 | MEDIUM. The sRGB8+index canonical half is exactly what V2 keeps; only the Q16-internal OKLab arm is targeted. Splitting it is part of M1b, not a clean delete. | med |
| `globalPaletteV2 = false` feature gate | KEEP-AS-IS (the gate itself) | n/a (this gate IS the V1/V2 boundary marker) | LOW. The gate is the mechanism that keeps the global path unreachable; it should FLIP not be deleted when V2 global path lands. Removing the gate prematurely exposes untested V1 global path. | high |

---

## SAFE TO RETIRE NOW vs NEEDS-A-PLAN

### Tentatively SAFE TO RETIRE NOW (already dead / already gated; bookkeeping only)
These are ORPHANED-ALREADY: the behaviour is gone, retirement is cleanup. Each still
needs a grep to confirm zero live references and a check that no Map link or build
phase points at it, because a dangling reference would red the build.

- MLX look-NN deploy blob (`s4_load_look_net`/`loadLookNet`) and the deleted look-net learned core (`Net`/`LookNet*`/`LookCore`/`PaletteOracle`/`PaletteSearch`).
- A/B preference Atlas learned core (`AtlasGame`/`ValueHead`/`PersonalGenome`/`GumbelSearch`/`Proposer`/`GLRM`/`AtlasNetEval`/`BoardQ16`).
- Core AI L-inference (`SixFour/CoreAI/`, `trainer/coreai_export/`, `CoreAILInference` socket) and the `L.aimodel` stub.
- `CarrierL` / `RelationalMemory` {L,t}-anchor carrier story (already superseded by `DualCube.lawNoPrivilegedCarrier`).

### NEEDS-A-PLAN (gated successor must be green cross-tier FIRST)
Order follows RGB-FIRST-CLASS's gate-wall: nothing retires until its replacement
passes cabal + Map + codegen + cross-tier golden.

- OKLab substrate (`Color`/`ColorFixed`/`CubeTensor` Q16 OKLab arm). BLOCKED on M1b, which is BLOCKED on M1 RGBProjection green cross-tier. Pulling early regenerates every floor/collapse/upscale256 golden. THE substrate swap.
- Gaussian `ℤ[i]` (`GaussianChroma`/`ChromaUnitGauge`/`DualCube`/`ChannelProduct`). BLOCKED on the unresolved Q2 owner fork (coexist vs rewire) AND on Eisenstein C6 being proven not to break the C4 determinism floor. Eisenstein must land ALONGSIDE first (M2), never as a same-change replacement.
- `RelationalResidual` P6 and `RelationalMemory` d6/phi6. Coupled to the OKLab swap and to wiring `V2Latent`/energy-weighted-d6 into spec; the energy-weighted-d6 successor is prose-only today.
- Global GIFB palette path (`GlobalCollapseQ16` + Zig golden). Behaviourally dead but golden-pinned; its retirement should ride the same change that flips `globalPaletteV2`, with the Zig fixture handled deliberately.
- sigma-pair genome math (`SigmaPairHead`/`SigmaDecomp`/`ThetaToDelta` + `s4_leaf_override`). No V2 successor at all; the leaf-override kernel has a known overflow-bug history. Do not retire without a decision on whether V2 needs any leaf-override path.
- A/B genome codec/move math (`GenomeCarrier`/`IsometryMove`). Dead UX but possibly golden-referenced; needs grep before pull.
- `NudgeStep`/steering chain. Successor (M5 NudgeWord) does NOT typecheck yet (the 3.3 carrier blocker). Demote, do not retire.

### NEVER (SHARED-SUBSTRATE / KEEP-AS-IS, not candidates)
Per-frame palette input, Q16 integer floor + `zero-genome==floor`, theta_B/`MaskedBandForward`,
the JEPA/EBM spine, `RGBTLift`/`liftOct`, `ParadigmSoundness`/`Model*`, and the
`globalPaletteV2` gate mechanism itself.

---

## UNSURE: must verify before ANY deletion

This crosswalk is built from the digest, not from the live tree. Before a single
retirement, verify:

1. **Live golden coverage per element.** Which of these (`GlobalCollapseQ16`, `IsometryMove`, `GenomeCarrier`, `s4_leaf_override`, `MaskedBandGolden`) still emit a checked-in golden fixture that `gate.sh` exercises today. The digest infers golden-pinning; confirm by grepping `spec/test/` and the Zig `-Drequire_fixtures` set.
2. **Dangling Map / Codegen / build-phase references** to the already-deleted look-net and Atlas modules. A deletion is only safe if nothing links them; the digest cannot see link-level dead references.
3. **The seven `ℤ[i]` consumers** named but not enumerated. Identify them before deciding coexist-vs-rewire, and confirm the C4 determinism-floor claim (`ChromaUnitGauge.lawUnitGroupIsoQuarterTurn`) is the only thing standing between `ℤ[i]` and `ℤ[ω]`.
4. **Whether `s4_leaf_override` / sigma-pair has ANY V2 role.** It has no V2 successor in the digest. If V2 never needs leaf-override, it can join the retire list; if it does, it is KEEP. Owner decision required.
5. **The OKLab "display-only decode" disposition** (RGB-FIRST-CLASS Q7): retire OKLab goldens entirely vs persist a display-only decode. This changes whether `Color`/`ColorFixed` fully retire or partially survive.
6. **`NudgeStep` carrier (`[[Detail]]` vs `LatentTail`)** and whether the M5 NudgeWord successor will ever typecheck (the 3.3 blocker). Until resolved, the "REPLACED-BY-V2" label on the steering chain is aspirational.
7. **`PonderBudget` -> `CellNudge` re-validation.** CellNudge's rank-3 honesty has not been re-checked under the OKLab->RGB/Eisenstein re-basis with phi6 now label-only (DIGEST open Q). Confirm CellNudge still holds before retiring `PonderBudget`.
8. **`globalPaletteV2` flip vs the global path golden.** Confirm whether flipping the gate true exposes any V1 global-path code that is implemented-but-never-run, which would need its own validation pass.
