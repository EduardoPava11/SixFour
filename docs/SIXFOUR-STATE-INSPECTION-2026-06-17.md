# SixFour — State-of-the-App Gap Report

_Synthesis lead inspection, 2026-06-17. Verdicts override original claim statuses where they conflict. Ground truth from source probes; STATUS.md treated as a claim, not authority._

---

## 1. Verdict

SixFour ships **one of its three pillars in full and the other two only as proven-but-unwired substrate.** Pillar 1 (Capture → 64³ voxel mass) is **real and shipped**: a hardware-pinned 20fps 64×64 burst is assembled into a single flat 64³ index cube, type-gated complete, and collapsed to one global palette through the byte-exact Zig core. Pillar 2 (on-device NN with SIMT-Zig+Metal-agreement tensors) is **bifurcated and unshipped**: an MPSGraph value net genuinely trains on-device but is fp32 telemetry that touches zero `s4_*` kernels and never selects a palette, while the look-NN that _would_ produce a learned genome is Haskell-forward-proven + Mac-trained (grayscale-L only) with its byte-exact Zig loader (`s4_load_look_net`) sitting at zero production callers — so the "NN tensors honor the integer agreement" target is currently unmet by anything running. Pillar 3 (reversible 16³+16³→256³) is **the furthest from vision**: the implemented model is a single-substrate reversible Haar pyramid (one coarse tier + carried detail planes), not two 16³ GIFs reconstructing a 256³; it is bit-exact reversible within captured detail but **dormant** (zero callers, flag OFF), and no 256³ artifact is producible end-to-end — the shipped "256" is spatial-only 4×4 index replication over the same 64 frames. Net: the deterministic spine is excellent and verification-gated; the *learned* and *super-resolution* halves of the vision are spec-complete and partially ported but not wired into any user-reachable output.

---

## 2. Per-Pillar TARGET vs AS-BUILT

### Pillar 1 — Capture → 64³ voxel mass

| Sub-capability | TARGET | AS-BUILT | Status |
|---|---|---|---|
| 64-frame burst @ hardware-pinned 20fps | True hardware cadence, exactly 64 frames | `clampFrameRate` locks `activeVideoMin/MaxFrameDuration=1/20`; `precondition(collected.count==64)` | **SHIPPED** |
| 64×64 OKLab tile per frame | 4096-pixel OKLab tile | `OKLabTile(side=64)`, GPU crop+downscale→OKLab | **SHIPPED** |
| Single flat 64³ index cube (one source of truth) | 262144-entry (t,y,x) cube | `SurfaceView.commit` flattens into `surface.indexCube`, read by all projections via `cellGlobal` | **SHIPPED** |
| End-to-end `frameIndices`/CaptureOutput populated | All render paths fill voxels | Set at CaptureViewModel :583/:664/:762; old "frames dropped" note refuted | **SHIPPED** |
| Completeness gate (T=64, 4096, surjective→256) before GIF | Short/dropped cube unrepresentable | `CompleteVoxelVolume.init?` brand, no public init; gates all 3 write paths | **SHIPPED** |
| Deterministic Zig global collapse → 256 palette | Pooled-maximin, byte-exact to spec | `s4_global_collapse` (lloyd=0 maximin), golden-gated `collapse_golden.json` | **SHIPPED** |
| True Q16 centroids through CaptureOutput | Editable integer-truth leaves on the boundary | Only sRGB8 `palettesForDisplay` carried; `globalLeavesQ16` computed then dropped; Atlas re-derives lossily | **MISSING (disclosed stub)** |
| RGBT-4D literal 4-channel cube | 4D RGBT voxel mass | `RGBT4DLift` exists, 0 callers, flag OFF; cube is (t,y,x) indices + per-frame palette factor | **WIRED-BUT-DORMANT** |
| 256³ voxel mass | True 256-frame deep cube | Output is 256×256 spatial via 1→4×4 index replication, same 64 frames | **DESIGNED-ONLY** |

_All 12 capture claims (C1–C12) were verdict-**confirmed**. The single non-"built" claim (C9, Q16 centroids) was confirmed-stubbed._

### Pillar 2 — On-device NN (SIMT Zig + Metal tensors)

| Sub-capability | TARGET | AS-BUILT | Status |
|---|---|---|---|
| On-device training (MPSGraph autodiff + SGD) | NN trains on iPhone GPU | `AtlasTrainer` real `gradients(of:with:)`+SGD+assign; test asserts loss halves | **SHIPPED** (Atlas value net) |
| Trained net = the genome that produces a look | Genome net trains/runs on device | On-device net is the **value** (Bradley-Terry) scorer, NOT the look-NN genome | **SHIPPED (wrong net)** |
| NN tensors honor Zig byte-exact Q16 agreement | Integer-exact, shares `s4_*` | AtlasTrainer is pure fp32, **zero `s4_*` calls**, lossy Q16→Float genome bridge | **MISSING** |
| Look-NN forward path proven | Verified forward pass | Proven in **Haskell only** (LookNetE/R/D, SigmaPairHead, σ-equivariance laws) | **SPEC-ONLY** |
| Look-NN byte-exact Zig loader (golden fixture) | Loadable on device | `s4_load_look_net` fixture-verified against the regenerable GOLDEN `look_net.s4ln`; **0 callers**. Supervised `look_net_trained.s4ln` ABANDONED/DELETED (2026-06-17 AlphaZero reframe) | **LOADER CODE KEPT; trained blob ABANDONED** |
| Look-NN inference in render path | Learned genome chooses palette | None. Render = `s4_global_collapse` deterministic maximin | **MISSING** |
| Atlas value-net output selects emitted palette | V-scores choose palette | V-scores are read-only Review telemetry; palette = user PICK + deterministic FarthestPoint+perturb | **MISSING (decorative)** |
| MPSGraph value net golden-gated vs Haskell | Spec-pinned weights/loss | No golden; `Spec.Preference` (Bradley-Terry) orphaned, no codegen/consumer | **MISSING** |
| Full-colour trained net + training data | Real data, full L*a*b* | Grayscale-L only; `trainer/data` empty; "beats baseline" is synthetic | **MISSING** |
| Mac trainer = spec-emitted | `atlas_net_mlx` from codegen | Hand-written PROTOTYPE; no `trainer/generated/atlas_net_mlx.py`; codegen emits look-NN only | **SPEC-ONLY / stubbed** |

_C1–C10, C12 confirmed. **C11 (loss bit-identical Mac↔iPhone) verdict = OVERSTATED** — the on-device run is real but no test asserts the headline numbers, no parity harness exists, and the Swift "spike" and Mac MLX architectures differ enough that a bit-identical trajectory is implausible. Treat as: on-device training real; cross-language bit-identity unproven._

### Pillar 3 — Reversible 16³+16³ → 256³

| Sub-capability | TARGET | AS-BUILT | Status |
|---|---|---|---|
| Reversible integer 2-D Haar lift (2×2→RGBT cell) | R⟂P pyramid construction | `liftQuad/unliftQuad` (S-transform), `liftLevel/distill`, tier16/64/256 | **SHIPPED (math) / DORMANT (app)** |
| Bit-exact round-trip within captured detail | `synthesize∘distill=id`, golden+Swift | `lawLadderBijective`; `RGBT4DGoldenTests` round-trip incl. negatives | **SHIPPED (math) / DORMANT (app)** |
| Loss confined to synth-beyond | Zeroed-detail = nearest-neighbour floor | `synthBeyond` = block replication, proven NN-equivalent | **SHIPPED (math) / DORMANT (app)** |
| App consumer / flag wired | User-reachable 4D mode | `rgbt4dEnabled` OFF, **0 callers**, no UI toggle | **WIRED-BUT-DORMANT** |
| 256³ end-to-end artifact | Producible 256-frame GIF | None. 256 export = spatial 1→4×4 replication, 64 frames | **MISSING (partial: spatial only)** |
| Two-cube temporal+spatial fuse (A=global, B=per-frame) | Reversible fusion to 256 frames | `Spec.Upscale256` exists (blend+prior re-quantize, **lossy, not reversible**); **no Swift/Zig port** | **SPEC-ONLY** |
| 256³ ladder rungs in export backend | Ship 256³ rungs | `LadderExport` Rung = {working16, global64}; "256³ rungs deferred tiled decode" | **DESIGNED-ONLY** |
| Construction (2) base+motion W₂-geodesic fuse | — | Not implemented; only linear Q16 temporal blend exists | **MISSING** |
| Construction (3) tensor product of two independent factors | — | Not implemented; reconstruction is Haar inverse (1 coarse + detail planes) | **MISSING** |

_All 10 claims (C1–C10) verdict-**confirmed**, including the three negative claims (no W₂ fuse, no tensor product, 256³ deferred)._

---

## 3. THE REVERSIBLE-256 ANSWER

**Which construction the code implements:** Construction **(1) Haar / radix pyramid R⟂P**. The reversible integer 2-D Haar lift maps a 2×2 spatial block to one RGBT cell (R=LL coarse, G=LH, B=HL, T=HH detail) via `sLift/sUnlift` (`spec/src/SixFour/Spec/RGBTLift.hs:74-100`) and recurses through `distill/synthesize/liftLevel` with tier16/tier64/tier256 (`spec/src/SixFour/Spec/CubeLadder.hs:57-108`). The Swift port is `SixFour/RGBT4D/RGBT4DLift.swift:43-123`; the Zig mirror is `Native/src/kernels.zig:656` (`s4_rgbt_lift_quad`) and `:684` (`s4_cube_lift_level`). Constructions (2) base+motion-residual W₂-geodesic and (3) tensor-product-of-two-factors are **not** implemented (verdicts C9/C10 confirmed).

**Is the lift round-trip bit-exact?** Yes, **within captured detail** — `synthesize∘distill=id` is proven in Haskell (`lawLadderBijective`, `CubeLadder.hs:122-127`), golden-pinned (`spec/test/Properties/CubeLadder.hs:57-58`, FNV-1a pins → `Generated/RGBT4DGolden.swift`), and Swift-tested (`SixFourTests/RGBT4DGoldenTests.swift:35-43`, including negatives). Loss is isolated to `synthBeyond` (zeroed-detail upsample = nearest-neighbour block replication) **strictly above** captured resolution — not invertible there, by construction.

**Is a 256³ artifact producible end-to-end?** **No.** The closest two-cube fusion, `Spec.Upscale256` (`upscale256/blendPalettesQ16/quantizePrior`, `spec/src/SixFour/Spec/Upscale256.hs:92-265`), is the temporal+spatial recompute fusing cube A (global indices) + cube B (per-frame palettes) — but it is (a) **lossy** (prior-weighted re-quantization, linear Q16 blend, not reversible) and (b) **entirely unported**: grep for `blendPalettesQ16/alignSlots/quantizePrior` across `SixFour/` and `Native/` returns nothing. The shipped 256 export (`DeterministicRenderer` → `SixFourExport.replicate`, `ExportContract.swift`: sourceSide 64, outputSide 256, factor 4) is **spatial-only nearest-neighbour index replication over the same 64 frames** — no temporal ×4, no Haar lift, no two-cube drive. **Bottom line:** the user's literal target — two 16³ GIFs reversibly reconstructing a 256³ GIF — is **not built**. What exists is one 16³ coarse tier + carried detail ↔ 64³ (lossless) and a 64³→256³ that invents detail (non-invertible floor), all dormant.

---

## 4. Cross-Language Agreement

The byte-exact contract is **real and golden-pinned, but it is Haskell(spec) ≡ Swift ≡ Zig on the deterministic integer kernels — Metal is OUTSIDE the verified surface.** Haskell is source-of-truth; `Fixtures.hs` emits `*_golden.json` from the same spec modules that drive `Generated/*.swift`; Zig `*_fixture_test.zig` load the JSON and assert byte-exactly; Swift tests assert against the same data.

**~16 three-way golden-pinned `s4_*` kernels** back the contract:
- `s4_global_collapse` ← `collapse_golden.json` (`Spec.Collapse`) + `collapse_fixture_test.zig:35` (bit-exact, no tolerance) + Swift `CollapseGoldenTests`/`ZigCollapseGoldenTests`
- `s4_haar_analyze/reconstruct/level_nodes` ← `haar_golden.json` (`Spec.PairTreeFixed`)
- `s4_linear_to_oklab_q16` + `s4_palette_oklab_to_srgb8` ← `color_golden.json` (`Spec.ColorFixed`)
- `s4_rgbt_lift/unlift_quad` + `s4_cube_lift/unlift_level` ← `rgbt4d_golden.json` (skip-if-absent — golden not regenerated, see §5)
- `s4_quantize_frame`, `s4_dither_frame`, `s4_significance_fill`, `s4_gif_assemble`, `s4_gif_encode_burst`(+bound/scratch), 3× LUT (`zone_profile/look_transfer/build_cube`)

**Metal in the golden surface: 0 parity tests.** The only Metal artifact emitted is `FieldTuning.metal.h` (a tuning-constant header from `Codegen.Swift`). No fixture asserts GPU output against the Haskell golden. So the SIMT-Zig + Metal "agreement" the vision implies is **half-real**: Zig≡Swift≡Haskell is rigorously gated; **Metal/GPU paths are unverified against spec.** Zig-only/no-golden kernels: `s4_probe`, `s4_set_log_callback`, `s4_widen_half_to_q16`, `s4_srgb8_to_oklab_q16`, `s4_gif_decode`(+scratch), `s4_load_look_net` (byte-exact vs the Python producer, not a Haskell golden), `s4_synth_burst`.

---

## 5. Build / Gate Ground Truth

| Gate | Result | Detail |
|---|---|---|
| `verify` (Haskell `cabal test`) | **GREEN** | **834 tests passed** (36.6s, exit 0); 832 `testProperty` across 97 files |
| gen-tests (separate Haskell suite) | **GREEN** | **10 tests passed** (not run by plain `cabal test`) |
| `native` (Zig `zig build test`) | **GREEN** | **28 pass, 1 skip, 29 total** (exit 0). Skip = `rgbt4d_fixture_test` (golden absent) |
| `lint` (`lint-grid.sh`) | **GREEN** | UI conformant, single-pitch, no glass on HUD, goldens present |
| `doc` (`verify-doc-claims.sh`) | **RED** | 1 load-bearing fact failed (`:96` header==exports) |
| `build` (xcodebuild sim) | **NOT RUN** | Policy: compile-check only; sim has no camera |
| Swift tests | **NOT RUN** | **229 `@Test` cases across 47 files**; need sim/device |

**The RED doc gate is a header/export drift, not a code defect:** `Native/include/sixfour_native.h` declares **24** `s4_*` symbols; `Native/src/*.zig` exports **28**. The 4 undeclared = `s4_cube_lift_level`, `s4_cube_unlift_level`, `s4_rgbt_lift_quad`, `s4_rgbt_unlift_quad` (the RGBT-4D cube-ladder kernels that "LANDED but DORMANT"). **Fix:** add the 4 declarations to the header (or reconcile the set). The Zig skip is fixable by regenerating `trainer/out/rgbt4d_golden.json` via `cabal run spec-fixtures`.

**STATUS.md is stale:** self-inconsistent test counts (595 @ line 130 vs 750 @ line 114), predates two 2026-06-16 NOTES sessions (RGBT-4D + Genome-A/B), and cites stale line numbers (`renderDeterministicGlobal` :478/:480/:555 → actual :602/:680). Its "24 == set-equality drift-proof" claim is now false.

---

## 6. Ranked Next Units of Work (highest leverage first)

1. **[Build/all pillars · S]** Reconcile header↔exports (add 4 `s4_cube/rgbt_*` decls to `sixfour_native.h`) and regenerate `rgbt4d_golden.json`. **Turns the doc gate GREEN and lights up the only skipped Zig test.** One-line-ish; unblocks every other gated change.
2. **[Build · S]** Reconcile STATUS.md to the 834-test reality + two 2026-06-16 NOTES sessions; fix stale line cites. Cheap, restores the canonical ledger's authority.
3. **[Pillar 1 · M]** Thread true Q16 centroids (`globalLeavesQ16`) through `CaptureOutput` instead of the lossy sRGB8→OKLab re-derivation in `AtlasState`. Unblocks the Color Atlas curation seam with integer truth; the only disclosed stub in the otherwise-shipped capture pillar.
4. **[Pillar 3 · L]** Port `Spec.Upscale256` to Swift/Zig and add the two 256³ `LadderExport` rungs. **First step toward a producible 256³ artifact** — but decide reversibility first (see §7). Largest single move toward the most-distant pillar.
5. **[Pillar 2 · M]** Golden-gate the MPSGraph value net: port `Spec.Preference` (Bradley-Terry) through codegen, emit a weight/loss golden, and assert a Swift↔spec trajectory. Converts the unverified on-device trainer into a gated one and resolves the overstated C11.
6. **[Pillar 2 · L]** Wire a Swift look-NN forward pass over `LookNetWeights` from `s4_load_look_net` (currently 0 callers) and a render-path seam, even behind a flag. **First real on-device learned-genome inference**; the blob is already trained + fixture-verified.
7. **[Pillar 2 · L]** Make the Atlas value-net output actually select/rank candidates (replace deterministic FarthestPoint+perturb with V-ranked argmax over a real gallery). Closes the "trained net never chooses the palette" gap.
8. **[Pillar 1/UX · M]** Expose `paletteScope` in Settings (or auto-route), so the global-collapse + Atlas curated-leaves render seam is reachable as the committed hero — today it ships only via the Ship/Group export ladder.
9. **[Pillar 3 · M]** Wire an `rgbt4dEnabled` consumer + Settings toggle so the reversible Haar lift stops being pure dead-but-verified code.
10. **[Pillar 2 · L]** Move the look-NN trainer beyond grayscale-L: capture real training data (`trainer/data` empty) and train full L*a*b*. Prerequisite for any honest "learned look."

---

## 7. Open Questions for the User

1. **256³ reversibility intent.** The vision says "reversible 16³+16³→256³," but the only fusion spec (`Upscale256`) is **lossy** (prior re-quantize). Do you want (a) a genuinely reversible two-cube construction (requires a new spec — current Haar pyramid is single-substrate, not two complementary 16³ GIFs), or (b) accept the lossy temporal-blend fusion as the 256³ rung? This determines whether #4 above is a port or a redesign.
2. **Which net is "the" NN?** On-device training works — but for the **value** net (telemetry), not the **look-NN genome** (which would actually colour output). Is the pillar satisfied by on-device value learning, or must the genome run on device (requiring #6)?
3. **Metal in the agreement contract.** "SIMT Zig + Metal agreement" currently has Zig≡Swift≡Haskell golden-pinned but **zero Metal parity tests**. Do you want Metal/GPU outputs golden-gated against the Haskell spec, or is GPU explicitly outside the byte-exact contract (display-only)?
4. **Act III picks.** The 4 browsing picks are decorative w.r.t. render bytes (they feed only the Review motion outline; render fires autonomously). Should "browse → pick 4 → render those" be wired, or are picks intentionally outline-only?
5. **Genome-A/B pivot vs RGBT-4D.** Two 2026-06-16 pivots landed unabsorbed in STATUS.md (RGBT-4D cube ladder, Genome-A/B "taste camera"). The Genome-A/B keystones are **not cabal-test-gated**. Which pivot is the active north star, and should Genome-A/B specs be gated?

---

_Report written to `/Users/daniel/SixFour/docs/SIXFOUR-STATE-INSPECTION-2026-06-17.md`._

---

## 8. Completeness-critic correction (folded in post-synthesis)

The synthesis above has **one material miss**, surfaced by the completeness critic and confirmed
against source:

**A shipped, three-language, golden-gated, user-reachable *heuristic* look-grading subsystem was
omitted from Pillar 2 and from the §4 kernel inventory.** It is non-neural but proprietary,
Q16-integer, and verified across Zig ≡ Swift ≡ Haskell:

- **Zig:** `s4_zone_profile_q16`, `s4_look_transfer_q16` (`Native/src/kernels.zig:2201`) — both
  exported *and* header-declared; plus `s4_synth_burst`, `s4_build_cube_q16`,
  `s4_widen_half_to_q16` were also dropped from §4's "~16 kernels" tally.
- **Swift:** `SixFourNative.swift:461 lookZoneProfile / :487 lookTransfer / :513 extractLUT`;
  `Palette/LookVariant.swift` (`.graded`, enum `off/soft/medium/strong/inverted` + Q16 strength);
  `AppSettings.captureLook`; `Encoder/LUTFile.swift`.
- **User-reachable UI:** `UI/Surface/ReviewPhaseField.swift:402-406` — an **Export-LUT share
  button** emitting a `.cube` file, active whenever `captureLook != .off`.
- **Haskell + tests:** `Spec/{ZoneProfile,LookTransfer,CubeLut}.hs` + matching `Properties/*`,
  all registered in `spec/test/Spec.hs`, golden via `lut_golden.json`.

**Correction to §1/§2:** the headline "the look's learned half is not wired into any
user-reachable output" is accurate **only for the *neural* genome**. A deterministic `s4_*`
look-grading pillar IS shipped and reaches Review's Export-LUT button. Pillar 2's verdict should
read: *neural genome unshipped; deterministic look-grading shipped + golden-gated.*

**Caveat on the 3-pillar taxonomy itself:** this report graded against the user's stated
three-pillar vision, which is **not identical** to STATUS.md / CLAUDE.md's declared north-star
(*on-device per-user delta-head look learning*; the MPSGraph **value** net is the *sanctioned*
Tier-2 on-device trainer by that contract, not a "wrong net"). Read the Pillar-2 "wrong net"
framing as "wrong net *for the genome target*," not a defect against the project's own contract.
