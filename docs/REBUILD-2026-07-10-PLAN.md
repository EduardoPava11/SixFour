# THE REBUILD — 64³ color-time, simpler and robust (2026-07-10)

Daniel's directive (verbatim intent): take the app apart and restructure it so it is
simpler and robust. The 64×64×64 tensor is the canonical substrate — each cell a
small tensor of information. The app keeps making the GIF with classical
algorithms; the 64³ records train a model that should eventually beat the
classical pipeline. Probe the camera hardware up the ladder
16³/32³/64³/128³/256³/… (training-data generation), always collapsing to the
64³ reality. The app must PROVE with a device log that it takes the three
resolutions; the {16,32,64} ladder must be MATHEMATICALLY PROVEN to train the
model on color time. Ladder symmetries via fold algebra (foldr/foldl); 16 and
256 are each two octaves from the 64 reality.

Ground rules inherited from the 2026-07-10 sunset (SESSION-2026-07-10-NOTES.md):
device-fit and debt-budget are gates now. One unit, landed small,
device-verified, THEN deepen. Nothing below is exempt.

---

## 1. What the research established (three agents, 2026-07-10)

### 1.1 NN literature (why this design is right, and what the model should be)

- **GIFnets** (Google, CVPR 2020, arXiv:2006.13434): PaletteNet + DitherNet +
  BandingNet beat median-cut + Floyd–Steinberg while emitting standard GIF89a.
  Existence proof for "model beats the classical pipeline". Not temporal —
  color-TIME is open ground and is our edge.
- **FSQ** (ICLR 2024, arXiv:2309.15505): a product lattice of quantization
  levels IS an implicit codebook (no learned VQ tables, no collapse). Our 64³
  bin lattice = FSQ with levels {64,64,64}. The classical pipeline and the
  learned model share one discrete space by construction.
- **Multigrid video training** (Wu et al., CVPR 2020, arXiv:1912.00998; theory
  arXiv:2501.12739): variable spacetime-resolution schedules train faster AND
  generalize across grids; coarse grids buy gradient-variance reduction
  cheaply. Our {16,32,64} ladder is the exact-integer version (their grids are
  lossy bilinear; ours are exact u64 folds).
- **V-JEPA 2 / VideoMAE** (arXiv:2506.09985 / 2203.12602): mask spacetime
  tubes, predict representations. For us the target representation is GIVEN
  and EXACT — the integer pooled cell tensors — so there is no collapse
  problem and no EMA target encoder ("Moment-JEPA").
- **Time-varying palette geometry** (SIGGRAPH 2021 skew polytopes): the most
  literal published "color time" — palette as trajectory. Cheap fallback head.

**Ranked model direction (the review Daniel asked for):**
1. **Temporal PaletteNet by distillation** — small net reads the 64³
   cell-tensor cube, emits the 256-entry palette (+ soft index logits);
   trained in MLX with the classical pipeline's own output as the initial
   target, then surpasses it with a temporal-flicker + banding loss.
   Hand-writable forward pass (convs/MLP) — inside the zero-dependency rule.
2. **FSQ framing** on the existing bin lattice + tiny masked cell-code
   predictor (MAGVIT-v2's lesson: the tokenizer is the bottleneck — ours is
   exact and free).
3. **One weight-shared fully-convolutional net trained multigrid** on
   {16,32,64} with the EXACT cross-scale constraint pool(f(64)) == f(pool(64))
   as a consistency loss; 128/256 probes are the generalization test.
4. **Moment-JEPA pretraining** (mask late t-slices, predict exact cell
   tensors) as the Mac-side MLX recipe feeding 1–3.
This replaces the never-trained full-matrix H-JEPA as the working model plan;
SIXFOUR-MODEL.md remains the north-star document for the invention-above-floor
idea, but the reachability gap (contractDescentOnRealDataUnproven) is attacked
with direction 1 on REAL .s4cr corpora — per the floored-is-data-not-architecture
lesson.

### 1.2 Model audit (what exists)

Three learned-object lineages, one live: θ_up (21 params, per-capture, plain
Metal, decorative-safe: zero-gene == floor). θ_B band head dormant. LookNet
deleted. H-JEPA full-matrix: spec-complete, no trainer, never reached the
floor on held-out loss. The color-time spec spine (ColorTime, GaussianLadder,
EventEncoding, TriScaleTraining, FidelityLadder, LadderIdentity) is tight,
mutually referencing, and ~80% of the theorem Daniel wants. The .s4cr v2
record already carries c64/c32/c16 u64 sum cubes (independent mode) or the
c16-only derived signature. No 128/256 captured tier exists anywhere (256³ is
synthesis-only, Upscale256/CubeLadder).

### 1.3 Hardware feasibility (iPhone 17 Pro, iOS 26)

- Cost scales with CROP pixels, not bins ⇒ 128² is free at today's crop 512;
  256² needs GPU pooling and/or crop 1024 (1080p-class x420).
- 512² gated on one empirical unknown: does ANY 4K-class format deliver
  x420 through AVCaptureVideoDataOutput on this phone (the btp2 trap)?
  1024²+ is jetsam territory. Predicted ceiling: 256² sustained.
- Sensor fact for the theorem doc: all video formats are quad-binned in
  silicon (48MP→12MP) — the first 2×2 fold happens in hardware
  (isVideoBinned is the API witness; PERF-MAP §4.5 purity order).
- Existing proof-log machinery: [perf] tick lines, BurstTiming drop counts,
  per-rung [perf] rung N² lines, systemPressureState telemetry. The ONE
  missing baseline number: device-measured tick CPU at crop 512 — no real
  run was ever logged.
- EV-ladder settle latency scales ~3–4× exposure duration (Apple forums
  751112) — log realized settle, don't assume settleFrames=2 holds at the
  coarse rung's long exposures.

---

## 2. The target architecture (simpler and robust)

ONE spine, four boxes, everything else deleted or quarantined:

```
CAMERA (AVFoundation, re-authored small)
  └─ 64-frame burst @20fps, 10-bit x420, crop 512 (probe may raise to 1024)
POOL (Kernels/ + Metal twins — KEPT, golden-gated)
  └─ exact u64 sums at every ladder rung; canonical 64³ cell-tensor record
      cell tensor v1 = (ΣR,ΣG,ΣB) u64 linear flux  [moments/χ² later, additive]
GIF (classical, KEPT: DeterministicRenderer + Encoder/ + palette16 floor)
  └─ app-export GIF == encoder input; byte-exact; the model's supervision target
RECORD + TRAIN (.s4cr v2 cubes → Mac MLX corpus; θ_up stays on device)
  └─ phone generates training data; Temporal PaletteNet trains on the Mac
```

KEEP (moves into the rebuilt target unchanged): Kernels/ (all 12 files),
Metal/ twins, ColorHead.swift + MultiScaleLadder.swift + RungReads/Telemetry +
CaptureRecord.swift (all AVFoundation-free), Encoder/, Train/ (θ_up spine),
Generated/ (regenerated anyway), the whole Haskell spec, VoxelReduce.

RE-AUTHOR small: CaptureSession (87KB → target <1/3 of it), the UI (one Live
surface + one Decide surface, form-follows-function charter, device-fit gate
BEFORE any composition lands).

DELETE (Stage 2, only after Daniel approves the list + probe verdict):
Merge/ + v3 decision-word writers (spec modules stay — true math), Tube/
(TubeGenerator has 0 refs) + THE SCROLL UI, Organs/, GeneLibrary/ (quarantine:
orthogonal to color-time; S4GX genes still cross via files), RGBT4DLift (keep
VoxelReduce), all Feature-off paths (globalPaletteV2, lutExport, opticalEV,
multiScaleRender, metaInitW0), UI scenes beyond Live/Decide. Rough cut:
~15–17k LOC of the ~37k goes.

Wire contracts that SURVIVE regardless (sunset notes): .s4cr v1/v2 bytes
pinned; the capture-format contract (app-export GIF == encoder input,
replicate2D ≠ upscale256); the GIF89a delay law 64@20/32@10/16@5.

"Bigger square GIF": display-size decouples from data-size. The GIF stays
64×64×64-frames canonical; export offers an integer-replicated bigger raster
(replicate2D, palette/index untouched) so the file views larger with ZERO new
information — the 64³ record remains the truth the model trains on. True
higher-res capture beyond that is a post-probe decision (needs the 256²
verdict + a new delay-law rung, side | 320).

---

## 2b. THE ONTOLOGY (Stage 1 core — Daniel's brief 2026-07-11)

Daniel: "GIFs are self-contained stop motion. The app needs to take the concepts
like color palette and index mapping and abstract it." The whole-app review
(2026-07-11 ontology audit) found: **that abstraction already exists exactly
once — in the spec — and the Swift app never adopted it.** Spec.ModelIO /
Spec.Palette / Spec.WeaveOrder state the GIF ontology cleanly; the app restates
color in ≥7 incompatible shapes (OKLabQ16, float OKLab, sRGB8 SIMD, 768-byte
GCT, u64 sums, Haar doubles, genome DOF), the index plane in 3 widths
(UInt8/UInt16/Int), time in 4 encodings (WeaveRung/UInt64/WeaveTick/nanos +
cs/ticks/µs delays), and runs TWO full palette pipelines (float GPU
GIFRenderer vs integer DeterministicRenderer).

**Stage 1 is therefore a PROMOTION, not an invention.** Four core types, all
existing today, lifted to the app surface; everything else becomes a view:

1. `Palette` — value type over `OKLabQ16` leaves (+ slot order + provenance);
   promoted from `CollapsedPalette`; mirrors `Spec.Palette`. sRGB8, the GCT,
   and the genome DOF are VIEWS via existing kernels
   (`s4_palette_oklab_to_srgb8`, `BranchedPalette.projectQ16`).
2. `IndexPlane` — side² `UInt8` indices into a `Palette` (kernel-native
   width); `[UInt16]`/`[Int]` shapes retire.
3. `WeaveRung` as THE time unit — side ↔ delay ↔ units ↔ cadence are theorems
   (`s4_ladder_delay_cs`, Spec.ColorTimeDisplay), so a Cel = IndexPlane +
   rung, and delay is DERIVED, never stored twice.
4. `Loop` — the in-memory GIF: [Cel] + per-frame Palettes (global optional).
   Promoted from `SixFourModelOutput` + `ModelRender` (palette[index] IS the
   render). GIF89a bytes = ONE codec of `Loop` (`s4_gif_assemble` /
   `s4_gif_decode` round-trip is the self-containment law); `.s4cr` stays the
   measurement sidecar (its bare arrays re-serialize as these types).

SELF-CONTAINED STOP MOTION, as laws: (a) `decode(encode(loop)) == loop`
(exists: Spec.Gif89aDecode round-trip); (b) everything needed to re-render is
inside `Loop`; (c) the 64³ cell-tensor record is the pre-collapse measurement,
`Loop` is the collapse — the model's job is exactly `record → Loop`, better
than the classical pipeline.

Demotions this implies (Stage 2 delete-list additions): the float
GIFRenderer/ClusterStatistics pipeline demotes to editing-only (explicitly not
the bit-exact core); dead-in-app Palette/Encoder files (BrushSet,
DivergenceSchedule, IsometryMove, QuartetDelta, NetSynth256, LadderExport)
join the delete list; `Surface.palette`/`palettesPerFrame`/`indexCube` raw
arrays are replaced by the four types.

## 3. The stages (each ends at a device gate)

**Stage 0 — PROVE (this session, additive only, no deletions).**
- S0a `Spec.LadderColorTime` — the consolidating theorem module (§4).
  Gate: cabal test green; theorem doc section in this file.
- S0b The LADDER PROBE (`Feature.ladderProbe`, default false) — per burst,
  pool the SAME crop at {16,32,64,128,256} independently, then verify the
  fold algebra on real photons and emit the proof log (§5). Includes the
  format census (log every x420 candidate incl. 4K verdict + isVideoBinned).
  Gate: BUILD SUCCEEDED (compile-only rule) → Daniel runs on the phone →
  the log IS the deliverable.
- S0c This plan doc.

**Stage 1 — REBUILD the target (after probe verdict).** New minimal app
target (project.yml second target) assembling KEEP-list sources + the small
re-authored CaptureSession + minimal Live/Decide UI. Old target stays
buildable throughout (the escape hatch). Device gate: parity capture — same
scene, old vs new target, byte-identical GIF + .s4cr.

**Stage 2 — DELETE (Daniel approves the list explicitly).** Execute the
delete list; old target removed; docs pruned to match. Gate: full suite green
+ one device capture session.

**Stage 3 — CORPUS + MODEL.** .s4cr export ergonomics (AirDrop batch), Mac
ingest, MLX Temporal PaletteNet v0 distilled from the classical pipeline;
multigrid schedule over {16,32,64}; cross-scale exact consistency loss.
Gate: v0 matches classical output (distillation floor) before any
"beat it" claim; then flicker/banding loss ablation.

**Stage 4 — CLOSE THE LOOP.** Hand-written Swift/Metal forward pass for the
trained palette head (zero-dependency rule), golden-gated against MLX,
behind a flag, decorative-safe (zero-model == classical floor), A/B on
device.

---

## 4. The mathematical proof (S0a: Spec.LadderColorTime)

THEOREM (color-time ladder). Training on the {16³,32³,64³} ladder is training
on color time, because:

1. **Pooling is a commutative-monoid fold.** A cell's tensor is the u64
   coordinatewise sum of its children — the fold of (ℕ³,+,0) over the block.
   Commutativity + associativity ⇒ foldl = foldr = any traversal order
   (Daniel's symmetry). Law: `lawFoldOrderInvariant`.
2. **The ladder is transitive (associativity, spatially).**
   pool64→16 = pool32→16 ∘ pool64→32 exactly (already teeth-tested in
   palette16; restated at cube level). Law: `lawPoolTransitive`.
3. **64 is a retract of every finer rung.** expand64→128 (replication) then
   pool128→64 is the identity; dually pooling is a projection. The chain
   16 ⇇ 32 ⇇ 64 ⇄ 128 ⇄ 256 makes 64³ the fixed point every rung maps onto;
   |log₂(side/64)| = 2,1,0,1,2 — 16 and 256 equidistant from the 64 reality.
   Laws: `lawPoolExpandIdentity`, `lawLadderSymmetricAboutSixtyFour`.
4. **The fold index IS color-time.** One integer k simultaneously = spatial
   coarsening, temporal pool depth, optical stops (ColorTime:
   lawColorTimeQuartic, τ_c = 4^k·Δ₀) and the ℤ[i] ideal norm
   (GaussianLadder: lawNormIsColorTime). Coarser rung ⇔ MORE color-time ⇔
   √τ_c better chroma SNR (lawSnrSqrtPowerLaw). So a model shown the three
   rungs is shown the SAME scene at three color-time exposures — the ladder
   axis is literally the color-time axis. Restated: `lawRungIsColorTimeStop`.
5. **The rungs carry disjoint training signal at invariant density.**
   Transitions 16→32 and 32→64 train DISJOINT bits; info-per-compute is
   rung-invariant; all three rungs cost 9/8 of the finest alone
   (TriScaleTraining). Refinement is monotone to zero error over ℚ
   (FidelityLadder: lawDeeperIsCloser). Temporal dither decode has zero
   irreducible loss given (signal, phase) (EventEncoding: lawHermiteDither).

1–3 are the fold-algebra half (new laws, this module). 4–5 are the
color-time half (proved in existing modules; this module re-states the
composite and pins the numeric identities across k ∈ {-2,…,2} rungs).
The DEVICE half of the proof is §5's transitivity check on real photons.

---

## 5. The proof log (S0b: what Daniel reads on the phone)

Once per probe burst, subsystem com.sixfour.SixFour, search `[proof]`:

```
[proof] format: 1920×1080 x420 20fps binned=true (4K x420: ACCEPTED|btp2-EXCLUDED)
[proof] rung 256²: 64/64 frames, pool crop512→2×2px bins, tick mean/max A/B ms
[proof] rung 128²: 64/64 frames, …
[proof] rung  64²: 64/64 frames, …            ← the canonical cube
[proof] rung  32²: 64/64 frames, …
[proof] rung  16²: 64/64 frames, …
[proof] fold: pool(256→64) == direct64  BYTE-IDENTICAL (lawPoolTransitive on-device)
[proof] fold: pool(128→64) == direct64  BYTE-IDENTICAL
[proof] fold: pool(64→32→16) == pool(64→16)  BYTE-IDENTICAL
[proof] foldl==foldr: forward/reverse accumulation identical (commutative monoid)
[proof] collapse: canonical 64³ cell-tensor record N MiB, 64 slices × 64·64·3 u64
[proof] budget: dropped=0, worstΔ=… ms, pressure=nominal, 5-burst drift=…
```

The three-resolutions proof Daniel asked for = rung 16/32/64 lines with
64/64 frames + the two BYTE-IDENTICAL fold lines: the phone itself verifies
the theorem's laws 1–3 on real photons every probe burst. 128/256 lines are
the training-data capability census; their pass criteria: dropped=0, tick max
under budget, stable across 5 bursts, pressure logged.

---

## 5b. DEVICE BASELINE RUN (2026-07-10, iPhone 17 Pro / A19 Pro — parsed from Daniel's log)

Baseline burst (ladderProbe OFF — no [proof] lines; this is the pre-probe run):

- **THE MISSING NUMBER, CAPTURED — and the tick budget is BLOWN**:
  `[perf] yin-yang tick CPU: 64 ticks, mean 65.39 ms, max 213.83 ms (50 ms budget)`.
  Mean tick cost > the 50 ms frame interval ⇒ the 1-deep delegate queue saturates ⇒
  20 dropped frames, intervals mean 65.88 ms (σ 31.91, worst Δ 200 ms), burst took
  4150 ms not 3200. Every `[tick] LATE +100.01 ms` is the mechanical signature of
  tick-cost > interval (each late tick drops exactly one frame) — not thermal.
  SUSPECT #1: a DEBUG build ("Reading from public effective user settings" =
  Xcode-launched; the design note's "~ms in release" is plausible at 20–60×
  under -Onone with bounds checks in the per-pixel loop). ACTION: rerun RELEASE
  before concluding anything about hardware. If Release still busts 50 ms,
  PERF-MAP H1 (pooling into the existing GPU pass) is Stage-0-blocking.
- **GPU HANG**: `IOGPUCommandBufferCallbackErrorHang` during the post-burst
  flurry (v21 flow encode + preview quantize storm + both trainers contending).
  Stop-the-line item for Stage 1; reinforces v21Capture=false for probe runs
  (the 384 MiB hist buffer + double-walk GPU pass are prime suspects).
- **Format reality**: 72 formats scanned, 9 x420@20fps (all HLG, none P3);
  selected 1280×720 → min-dim 720 → crop 512 lives, crop 1024 does NOT on this
  format. The full dims-of-all-x420 census (incl. any 4K x420 verdict) needs the
  probe's one-shot `[proof] format:` lines — still pending.
- **Exposure reality (SF-probe)**: custom exposure supported; shutter
  1/71429s…1s, ISO 54…5184, bias ±8 EV. CAUTION: the printed bracket
  (64²=1/30 | 32²=1/15 | 16²=1/8, "2.00 stops") is SENSOR-capable, not
  cadence-capable — 1/15 and 1/8 exceed the 50 ms frame duration; at 20 fps from
  a 1/30 base the TIME headroom is ~0.58 stops and the rest must be GAIN,
  exactly as the weave plan already assumes.
- **Learners behaved**: θ_up trained in 22 ms and FLOORED (−0%, 513.465 vs
  floor 513.922) — the corpus lesson again (static test scene, nothing to
  invent); YinYang S_t 512 pairs MSE 0→0, halt budget 4, 256/256 certifiable
  (a static scene certifies everywhere; the kinematic floor ships it).
- Benign: 3× Fig -12710 during format scanning, texture-pool miss #1 warmup,
  first tick +250 ms warmup, AE/AWB lock settled 0 ms.

**RUN 2 (same day, ~03:00Z)** — the signature REPRODUCES, it is not a fluke or a
thermal ramp: tick CPU mean 64.50 ms (was 65.39), max 149.41 (was 213.83 — run-1
max was warmup), 19 dropped (was 20), intervals 65.09 ms. GPU hang reproduced at
the SAME seam (during the async V2.1 flow-encode window while the preview
quantize storm runs) — deterministic, therefore debuggable. NEW: the pipeline
completed end-to-end this time — deterministic GIF 64f side=256, 1,263,097 B,
sha ef13a2d4…, 4425 ms [quant 2255 · dither 1239 · signif 227 · palette 7 ·
encode 697], plus `[perf] s4cr: 65 KiB (v2)` saved = the derived c16-only
provenance signature, exactly the Phase-A expected shape. CAVEAT for training
data: at ~65 ms real intervals the burst's time axis is ~30% slower than the
5 cs the woven GIF claims — drops corrupt the cadence contract, so no corpus
generation until the tick is fixed. Identical numbers across runs also mean:
if run 2 was already a RELEASE build, the Debug hypothesis dies and GPU pooling
(H1) is promoted to mandatory Stage-0 work.

**PHASE P sequencing verdict**: do NOT flip `ladderProbe` on this config yet —
the probe adds ~4 more crop walks to an already-saturated tick. Order:
(1) rerun this exact baseline in RELEASE; (2) if tick mean lands single-digit
ms, flip `ladderProbe=true` + `v21Capture=false` and run PHASE P; (3) chase the
GPU hang regardless.

## 5c. PHASE P RUN (2026-07-11 03:10Z, RELEASE build f45d6c3 — THE PROOF LOG)

**The theorem held on real photons.** All five rungs 64/64 frames at crop 512;
`pool(256→64) == direct64` and `pool(128→64) == direct64` and
`pool(64→32→16) == direct16` all **BYTE-IDENTICAL 64/64 ticks**
(lawPoolTransitive on device); temporal foldl==foldr order-invariant; canonical
64³ record 6.0 MiB × 64 slices; probe held 127.9 MiB at pressure=0.

**Debug hypothesis CONFIRMED**: tick CPU mean 65.39 → **3.66 ms** in Release
(≈18×; base ≈2.2 ms + ≈1.5 ms probe overhead — the "~ms in release" note was
right). Encoder 4425 → **350 ms** (12.6×). Intervals mean 50.80 ms σ 6.25,
burst 3200.4 ms — ON the 20 fps contract.

**Format census (the 512² question, format-side): 4K x420 EXISTS** —
3840×2160 x420 at 30/60/120 max fps, plus 1920×1080 (30/60/120) and 1920×1440
(60); all `binned=false`. Crop 1024 and crop 2048 are format-side possible; the
btp2 output-delivery question remains (the selector only output-probes the
smallest format today).

**Residuals**:
- dropped=2, tick max 95.03 ms — BOTH at burst start: the probe's five
  `reserveCapacity` calls (~128 MiB) ran lazily inside the FIRST tick, plus
  texture-pool miss #2. FIXED same-day: cubes now reserve at `LadderProbe`
  init (burst setup, before frame 0). The checklist bar is dropped=0 —
  re-verify on the next run.
- **GPU hang REPRODUCES WITH v21 OFF** — v21 is EXONERATED. In all three runs
  the hang lands in the same window: after the θ_up commit, immediately before
  the `YinYang S_t` result line ⇒ prime suspect is now the **BandHeadTrainer
  command buffer** (fused descent kernel; a long-running loop can trip the GPU
  watchdog). Corroboration: S_t reports MSE exactly 0.000000 in all three runs
  — plausibly the ABORTED buffer's zeroed outputs being read as results, not a
  real fit. Next unit: check the command-buffer error status in
  BandHeadTrainer, REFUSE the result on abort, and time the kernel.
- 5-burst sustain round still pending (single burst so far).

## 6. Open questions (parked, not blocking Stage 0)

- 512² verdict awaits the 4K-x420 census line.
- Cell tensor v2 (add Σv², χ², class — the .bvox v3 idea) after corpus v0.
- True >64 GIF rungs (128@40fps impossible at 20fps hardware; a 128-side
  GIF would need delay 2.5cs — violates s4_ladder_delay_cs integrality;
  export replication sidesteps this, canon unchanged).
- GeneLibrary quarantine vs delete: Daniel's call at Stage 2.

## 7. Reconciliation — 2026-07-13 cleanup pass (ledger catch-up, facts from git)

- **Stage 0 — DONE & DEVICE-PASSED.** `Spec.LadderColorTime` + probe committed
  (`fda48a2`); PHASE P Release run 2026-07-11 (§5b/§5c): all 5 rungs 64/64, all
  folds byte-identical, tick 65.4 → 3.66 ms.
- **Stage 1 is the §2b reading (promotion, not invention).** Units 1–3 landed
  (`d7e97ef`, `6933d5f`, `63e1738`). §3's original second-`project.yml`-target
  parity gate is superseded by §2b and has no artifact — the §2b promotion path
  within the existing target is the Stage 1 of record.
- **Stage 3 bullet 1 shipped EARLY:** `.s4cr` corpus export + AirDrop batch =
  `87d6ab4` ("THE CORPUS EXPORT") + `docs/TRAINING-CORPUS.md` (LIVE,
  `Feature.trainingCorpus = true`). Legitimate: §5c's "no corpus generation
  until the tick is fixed" caveat was cleared by the Release-tick result. The
  MLX Temporal PaletteNet (Stage 3 bullet 2+) does not exist yet.
- **§5c residual closed:** BandHeadTrainer refuses results on GPU dispatch
  failure (honest-nil, `a7eea21`).
- **§5c still open:** dropped=0 re-verify; the 5-burst sustain round.
- **Stage 2 (DELETE) untouched** — `Merge/`, `Tube/`, `Organs/`, `GeneLibrary/`
  all on disk, pending Daniel's explicit approval, as specified.
- **Flag debt:** the PHASE P probe pair (`ladderProbe = true`,
  `v21Capture = false`) is still the committed default; `Feature.swift` says to
  revert it after the probe log — left in place pending the open §5c rounds,
  but it must not outlive them.
