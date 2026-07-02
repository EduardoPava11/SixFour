# LAUNCH build workflow — the 256³ curation loop, the gene swap, and the atlas

> Status: LIVING · Created: 2026-07-02 · Owner: SixFour
> Companions: `docs/V3-BUILD-WORKFLOW.md` (cascade + gene registry),
> `docs/SWAP-ECONOMY-CARRIER.md` (the S4GX wire contract, landed green).
> Every anchor below was VERIFIED by reading the file (7-agent map, 2026-07-02).
> Spec wins on any disagreement.

Launch scope, hardest first: **L1** the 16³/64³/256³ ladder + the user-curates-256³
loop → **L2** the gene swap (S4GX ports + seams) → **L3** Apple services + App
Store checklist → **L4** train-on-adopted-genes → **L5** the GeneAtlas
(retrieval visualization). **L0 gate repairs come before everything** — the
local gate is RED today.

---

## L0 — gate repairs (the plan is unbuildable until these)

> L0.1 **DONE 2026-07-02** (header declarations added, parity green, zig 80/80).
> L0.2 **DONE 2026-07-02** (`test` verb added to s4.sh + gate-order; DecideMachineTests
> run green on the iPhone 17 Pro sim). L0.3/L0.4/L0.5 are standing discipline, not one-offs.

| # | What | Anchor |
|---|---|---|
| L0.1 | **The gate is RED**: `s4_v21_accumulate_hist_soft`, `s4_v21_palette_delta`, `s4_v21_wdist1d` are exported from Zig but undeclared in the C header, so header/export parity fails and `scripts/s4.sh all` aborts at step 2. Declare them. | `scripts/verify-doc-claims.sh:85`, `Native/include/sixfour_native.h:18` |
| L0.2 | **No gate runs SixFourTests**: `gate-order.txt` ends at `build`; every Swift golden below (SwapCarrierTests, DecideMachineTests, RungDispatch bitwise) runs only by hand. Add a `test` verb (`xcodebuild -scheme SixFour test`, arm64 sim) to `s4.sh` + gate-order. | `scripts/gate-order.txt:19`, `scripts/s4.sh:48` |
| L0.3 | **Codegen drift gates are blind to UNTRACKED files** (`git diff` only). Commit checklist: `git add` every NEW `Generated/` file (SwapCarrierGolden.swift etc.) or a fresh checkout breaks while gates stay green. | `spec/scripts/gate.sh:33` |
| L0.4 | **Project regen is `scripts/regenerate.sh`, never bare `xcodegen generate`** — it patches pbxproj filetypes so `.bin` resources survive codesign. All "then xcodegen" steps below mean regenerate.sh. | `scripts/regenerate.sh:18` |
| L0.5 | `lint-grid.sh` runs on EVERY build: new screens (CurateSurface, GeneAtlasView) must place widgets only via `.place()`; a new Metal/canvas renderer must join the `is_primitive` allowlist; new scenes join the LINT-GOLDEN list. | `scripts/lint-grid.sh:42`, `:161` |

---

## L1 — the 256³ curation loop (hardest)

**What exists / what's fake today.** The ladder's geometry is real, its content is
not: the shipped "256" is the 64³ GIF spatially replicated ×4
(`SixFour/Encoder/DeterministicRenderer.swift:251` — Stage 5 calls
`SixFourExport.replicate` then `gifAssemble`). The accepted decide result is
stashed and consumed by NOTHING (`SixFour/UI/Surface/Surface.swift:38`
`acceptedInput`/`acceptedUseGene` — "the 256³ build's future input", verbatim).
That stash is where the loop attaches.

**The FSM shape (preserves `lawExportGatedOnPick` with ZERO edits to it):**
Curating is a **Picked self-excursion**: `Picked —BeginCurate→ Curating
—CurateDone→ Picked`. Exporting stays entered only from Picked; both existing
laws quantify over `allABPhases` (Enum/Bounded), so the new phase is
auto-covered and `cabal test` proves non-breakage.

### L1.1 spec (land first, as always) — **LANDED 2026-07-02, all four tiers**

> Spec: `Curating` phase + `BeginCurate`/`CurateDone`, edges as the Picked
> self-excursion, `lawCurateEntryGated`/`lawCurateResolves`/`lawCurateGoldenTrace`,
> third golden — 1414 green; `lawExportGatedOnPick` passed UNTOUCHED (auto-quantified).
> Codegen: contract regenerated (curate golden + selfCheck "curating").
> Swift: `ABSurfaceMachine` ported + third golden fold in `assertSpecParity()`;
> `.curating` routes to the review bench as a documented INTERIM (unreachable — no
> UI fires `.beginCurate` until L1.3). Tests: 6/6 `DecideMachineTests` on the sim.
> The `curateScene` GridLayout row below remains (it is L1.3's prerequisite).

| Change | Anchor |
|---|---|
| `ABPhase` gains `Curating` (token "curating"); `ABEvent` gains `BeginCurate`/`CurateDone` | `spec/src/SixFour/Spec/ABSurface.hs:78` (events :83) |
| `abStep` gains the two edges; add Curating to the Retake bail list | `ABSurface.hs:99` (bail :111–112) |
| Clone `lawDecideEntryGated` → `lawCurateEntryGated` + `lawCurateResolves`; export both | `ABSurface.hs:250` |
| Add a THIRD golden `goldenCurateHappyPath`/`goldenCuratePhaseTrace` (…DecideAccept, BeginCurate, CurateDone, ExportFamily…) — never mutate the existing two | `ABSurface.hs:183` |
| Once-tests for the new laws + golden | `spec/test/Properties/ABSurface.hs:9` |
| **The consumption law** (closes "recorded but not consumed"): a Tier-0 law tying `acceptedInput`/`acceptedUseGene` to the exported bytes; zero-paint/zero-gene curate must equal `upscale256` byte-exact | new law beside `spec/src/SixFour/Spec/Upscale256.hs:232`; keystone (gene-conditioned reconstruct == shipped bytes) in `spec/src/SixFour/Spec/SelfSimilarReconstruct.hs:140` |
| Codegen: emit curate golden + selfCheck "curating" assertion | `spec/src/SixFour/Codegen/Swift.hs:812` → regen `SixFour/Generated/ABSurfaceContract.swift` (never hand-edit) |
| `curateScene` in GridLayout (256³ hero, iterate/re-paint/re-gene, accept cells) proven under the 8 layout laws, codegen'd | `spec/src/SixFour/Spec/GridLayout.hs:124` (laws :178–262) |

### L1.2 the 256³ builder (GPU, not CPU)
256³ Q16 interleaved Int32 ≈ **201 MB** (64³ is 3 MB) — `OctantCube.expandProposal`
(CPU) does not scale past its 64³ preview job.

> L1.2 rows 1–2 **DONE 2026-07-02**: `Spec.SelfSimilarReconstruct.expandRungVolume`
> (the DEVICE row-major layout pin, floor + committed-detail arms; 3 laws:
> singleton==unliftOct lane order, block-locality, floor-of-constant==constant;
> spec 1417 green) → Zig `s4_cube_expand_rung` (pure integer stage per the sandwich
> ruling — the float θ layer stays outside; header declared per L0.1) →
> `cube_expand_golden.json` emitted from the spec (`emitCubeExpandGolden`) →
> `cube_expand_fixture_test.zig` BIT-EXACT on both arms, 81/81 with
> `-Drequire_fixtures=true`.
> Row 4 (quantizer) **DONE 2026-07-02, spec tier**: `Spec.CurateRealize` — the
> volume→frames layout pin (exact, position-coded), realization via the SAME
> verified `quantizeFrameQ16` the shipped renderer runs (no new quantization
> machinery), `lawRealizeIsFrameLocal` (t-slab streaming licensed),
> palettizable-lossless, and ladder-floor-of-flatness→one-colour (floor survives
> to GIF bytes). **Fork resolved**: `upscale256` consumes the V2-deferred
> global-palette cube (unreachable in MVP1), so the LIVE curate floor =
> ladder-expand + CurateRealize; upscale256 stays the V2 endgame. The L1.1
> consumption-law row's "must equal upscale256 byte-exact" is amended
> accordingly. BONUS: QuickCheck falsified the original SwapCarrier CRC law
> (flip-then-rewrap re-signs; a minor-byte flip legitimately decodes to the same
> payload) — law rewritten to flip post-signing stream bytes; suite 1421 green.
> Swift wiring (Encoder/ curated render path) lands with L1.3.
> Row 3 **DONE 2026-07-02**: `cubeExpandRungKernel` (pure integer — the θ float
> layer stays outside per the sandwich; composes the existing s_unlift/unlift_quad
> helpers) + `RungDispatch.expandRung(volume:side:details:)` +
> `SixFourNative.cubeExpandRung` oracle wrapper; RungDispatchTests 12/12 on the
> sim — floor arm and gene arm byte-exact vs the Zig oracle, and the two-rung
> 16³→64³ ladder with θ-committed details EQUALS the shipped decide-preview CPU
> path (`OctantCube.upRung` twice). Remaining rows: the 256³→indexed-GIF
> quantizer (spec-first), the memory interlock (details buffer at the 128³ rung
> is ~59 MB — plan: θ-detail LUT keyed by distinct coarse value, or t-slab
> chunking, which the block-locality law licenses).

| Change | Anchor |
|---|---|
| New Zig CPU oracle: volume-level expand (octant unlift + θ_up predictDetail per rung), declared in the header (L0.1 discipline) | beside `Native/src/kernels.zig:857` (`s4_octant_lift`, `s4_cube_lift_level` :917) |
| Fixtures for the new oracle emitted from the spec — without this the Zig test is vacuously green | `spec/app/Fixtures.hs:59`, consumed by `zig build test -Drequire_fixtures=true` (`Native/build.zig:31`) |
| Metal expand dispatch composing the existing byte-exact unlift twin + θ_up; gate = post-commit bytes vs the Zig oracle | `SixFour/Metal/DeviceTrainShaders.metal:99` (`octantUnliftKernel`), dispatch beside `SixFour/Train/RungDispatch.swift:158` |
| 256³→indexed-GIF realization: quantize the Q16 volume to per-frame palettes+indices (today's palettes come only from the 64³ StageA path) — spec'd first, lands in Encoder/ | beside `SixFour/Encoder/DeterministicRenderer.swift:251`; `gifAssemble` is already side-parametric |
| Memory interlock: the ~800 MB flow-encode buffer (~19 s) can coexist with a curate build — clone the `flowJobActive` jetsam-guard pattern; build the 256³ on demand, preview by slices | `SixFour/Capture/CaptureSession.swift:60` |

### L1.3 the loop UI

> Step 1 **DONE 2026-07-02**: `curateScene` LANDED in `GridLayout.hs` under all 8
> laws (hero 64×128 the largest widget in any scene — inspection is the job;
> slabs rail 64×12 makes the t-slab streaming visible; source/repaint/rebuild
> reuse the proven 20×12 toggle idiom; accept 32×16), codegen'd into
> `GridLayoutContract.curateScene` + selfCheck spans three scenes. The PICO-8
> studio tooling upgraded: `render_grid.py` is now SCENE-AWARE (parses every
> `*Scene` from the spec, renders `cellgrid_{capture,decision,curate}.png`,
> parity harness checks corner clearance over ALL scenes); `verify.sh` green.
> Steps 2–4 **DONE 2026-07-02 (form follows function — every widget fronts a gated call)**:
> `Train/CurateBuilder.swift` (GPU ladder + Spec.CurateRealize in Swift; θ committed
> outside the kernels) gated by `CurateBuilderTests` 4/4 — GPU build == OctantCube
> decide preview BIT-EQUAL both arms; ladder == Zig oracle iterated; frame slicing ==
> the spec layout pin; constant floor realizes losslessly through the REAL Zig
> quantizer (the whole int→int sandwich). Then the form: `CurateSurface` (six placed
> regions, GRID-lint green; hero scrubs the REAL build at the 64³ tier — labeled
> on-face; slabs rail jumps; source floor/gene; repaint PRESENT-BUT-GATED, no
> Curating→Deciding edge exists yet; rebuild re-runs the ladder; accept records
> σ.curatedUseGene + fires .curateDone), `Curating256PhaseField` (consumes
> σ.acceptedInput/acceptedUseGene AT LAST), CURATE button on the picked bench,
> `.curating` route replaces the interim. Cross-tier sweep green: zig 81/81
> fixtures-required, spec 1429, Swift 30/30 (4 suites).
> **NEW ROW — quantizer scaling**: `s4_quantize_frame` maximin is O(k·n) per seed —
> fine at 64² frames, infeasible at 256²×256 frames on CPU. The 256³ export realize
> needs maximin seeding on a subsample OR a Metal quantizer twin (spec-first) before
> the export tier ships; until then the curate hero honestly shows the 64³ tier.
> Also open: Curating→Deciding re-paint edge (FSM design), σ.curatedUseGene consumed
> at export.
| Change | Anchor |
|---|---|
| CURATE button on the picked review surface fires `.beginCurate`; `PhaseField.field(for:)` gains `.curating` → new `Curating256PhaseField` | `SixFour/UI/Surface/CapturedReviewPhaseField.swift:116` (DECIDE precedent :89), `PhaseField.swift:23` |
| `Curating256PhaseField.swift` (new, mirrors `DecidingPhaseField.swift:20`): reads `σ.acceptedInput`/`acceptedUseGene`, drives the build, iterate/accept | `SixFour/UI/Surface/` |
| `CurateSurface.swift` + model (new, mirrors `DecideSurface.swift:38` `DecideModel` — off-main arm builds, rebuild on re-paint/re-gene); re-paint reuses `NudgePaintModel` as-is | `SixFour/UI/Screens/Curate/`, `SixFour/Editing/NudgePaintView.swift:41` |
| σ gains `curatedCube` (cleared on `.live` like `coarseSubstrate` — the curate phase must NOT bounce through `.live`; `acceptedInput` is cleared at every commit) | `Surface.swift:114` (clear :116), `SurfaceView.swift:251` |
| Export consumes the curated artifact: `DonePhaseField.exportItems()` ships the curated 256³ GIF when present (and moves off the MainActor) | `SixFour/UI/Surface/PhaseField.swift:159` |
| Swift FSM twin + parity: `.curating` case, edges, third golden fold in `assertSpecParity()`; DecideMachineTests gains the curate fold + "no direct curating→exporting" pin | `SixFour/UI/Surface/ABSurfaceMachine.swift:77` (:118), `SixFourTests/DecideMachineTests.swift:19` |

**Honest limit carried into L1**: paint→pixels conditioning still awaits the D1
field encoder — the curate preview reflects gene/floor arms truthfully but not
paint; keep the honest-fallback rule (documented in the surface header) until D1.

---

## L2 — the swap (S4GX into the shipped app)

Port order per `SWAP-ECONOMY-CARRIER.md §5`, with the map's corrections:
**neither S4GN nor S4GX has a Swift codec** — port both in one round (shared
framing); `AirDropHandler`'s directory bundle has ZERO live callers, so
superseding it is free.

> L2.1 **DONE 2026-07-02**: `Codegen.SwapCarrier` emits `Generated/SwapCarrierGolden.swift`
> (showcase + grant bytes of a canonical theta-up remix payload, corrupt + future-major
> negatives), wired into spec-codegen main.
> L2.2 **DONE 2026-07-02**: hand-written `GeneLibrary/CarrierWire.swift` (shared framing:
> CRC32, sub-blocks, marker scan, LE helpers) + `GenomeCarrier.swift` (S4GN) +
> `SwapCarrier.swift` (S4GX), all Foundation-only; `SixFourTests/SwapCarrierTests.swift`
> 8/8 green on the sim — encode byte-exact vs both goldens, round-trips, showcase-inert
> wire fact, negatives refuse, blocks coexist. Both codecs now golden-GATED (closes the
> "GenomeCarrierGolden consumed by nothing" gap). Remember L0.3: `git add` the new
> Generated/SwapCarrierGolden.swift at commit time.

| Step | Change | Anchor |
|---|---|---|
| L2.1 | `Codegen.SwapCarrier` (new) mirroring the S4GN emitter: canonical Showcase AND Grant bytes + corrupt/version negatives → `Generated/SwapCarrierGolden.swift`; wire into spec-codegen main + spec.cabal + Map; **git add the new Generated file (L0.3)** | `spec/src/SixFour/Codegen/GenomeCarrier.hs:10`, `spec/app/Spec.hs:95` |
| L2.2 | Hand-written `GeneLibrary/SwapCarrier.swift` + `GenomeCarrier.swift` codecs, golden-gated by new `SixFourTests/SwapCarrierTests.swift` (byte-exact, round-trip, negatives) | precedent gap: `Generated/GenomeCarrierGolden.swift:7` is emitted but consumed by nothing |
| L2.3 | **Export/mint seam — at SHARE time, per-recipient**: the GIF Data is produced once (`SixFourNative.gifAssemble`) but written at capture and only COPIED at share; inject S4GX at the share copy (`mintFor` decides profile), S4GN beside it | `SixFour/Native/SixFourNative.swift:545` (:556), `SixFour/UI/Screens/V21/V21CaptureField.swift:384` (`V21Export.shareItems`), `PhaseField.swift:159` |
| L2.4 | **The 16³ showcase front**: `LadderExport.working16` (16³ GIF, currently ORPHANED — no caller) becomes the Showcase-profile carrier body; `Trade.hs` already says tOffer is "shown as its 16³ GIF" | `SixFour/Encoder/LadderExport.swift:67` |
| L2.5 | **Import seam (nothing exists)**: `public.gif` CFBundleDocumentTypes + `LSSupportsOpeningDocumentsInPlace` via project.yml info.properties (L3.2); `.onOpenURL` on the WindowGroup probes `extractSwapBlock` → adopt flow → `GeneStore.addOrgan` keyed by content hash | `SixFour/App/SixFourApp.swift:17`, `SixFour/GeneLibrary/GeneStore.swift:85` |
| L2.6 | `OrganSlot` gains `case thetaUp` — legal NOW under the no-stubs rule (CaptureGene.train IS the trainer, RungDispatch tests exist) | `SixFour/Organs/Organ.swift:10` |
| L2.7 | θ_up JSON → wire: `BurstResult.thetaUp` 21 Floats become Q16 Int32 grant words (pin Float↔Q16 at `reenterQ16` round-half-to-even); `GeneCloudSchema` record gains SwapProfile + GeneTag fields (it already persists parentHashes) | `SixFour/Capture/CaptureSession.swift:125`, `SixFour/GeneLibrary/GeneCloudSchema.swift:54` |
| L2.8 | Ledger on device: `GeneLibrary/Trade.swift` port of Spec.Trade (mintFor must consult it at the share seam) + minimal trade UI (propose/accept on a lattice scene); `CreatorID` String→Int32 hash pinned (blocks record-id dedup until decided) | `GeneExchange.swift:63`/`:78`, `CreatorIdentity.swift:16` |
| L2.9 | Third arm on decide: `DecideModel.useGene: Bool` → three-case source (floor / mine / adopted) + picker; adopted θ routes through the same `expandProposal` | `SixFour/UI/Screens/Decide/DecideSurface.swift:63`, `Train/OctantCube.swift:92` |

Retire `AirDropHandler.swift` (directory bundle) after L2.5 lands.

---

## L3 — Apple developer services + launch checklist

Entitlements and Info.plist are xcodegen OUTPUTS — the ONLY edit site is
`project.yml`, then `scripts/regenerate.sh` (L0.4).

**Already real in the repo** (better than expected): Game Center + CloudKit
entitlements exist (`project.yml:152` — container `iCloud.com.sixfour.SixFour`);
`GameCenterIdentity` uses REAL GameKit (`GKLocalPlayer.authenticateHandler`,
`CreatorIdentity.swift:35`) but has zero app call sites; `CloudKitGeneDatabase`
targets the right container but is never instantiated outside tests.

| Step | Change | Anchor |
|---|---|---|
| L3.1 | Wire `GameCenterIdentity.authenticate(present:)` at app launch; resolved CreatorID feeds publish/mintFor | `SixFour/App/SixFourApp.swift:17` |
| L3.2 | project.yml info.properties: CFBundleDocumentTypes (`com.compuserve.gif`), UTImportedTypeDeclarations (GIF), `LSSupportsOpeningDocumentsInPlace`; drop the code-only `com.sixfour.genes` UTType or declare it | `project.yml:164`, `AirDropHandler.swift:19` |
| L3.3 | Instantiate `CloudKitGeneDatabase` + the browse/publish/adopt loop in the app UI (schema must be provisioned in the console first — manual list below) | `GeneExchange.swift:111` |
| L3.4 | **PrivacyInfo.xcprivacy does not exist** — required-reason API in use (UserDefaults via AppSettings): declare CA92.1 + file-timestamp reasons + nutrition types once CloudKit records ship. Submission blocker. | `SixFour/Settings/AppSettings.swift:56` |
| L3.5 | **UGC Guideline 1.2**: the public gene economy has no report/flag/block/takedown/EULA. Add Report+Block record types in GeneCloudSchema + minimal UI, or review risks rejection. | `GeneExchange.swift:63` |
| L3.6 | **No app icon** (zero .xcassets — submission blocker); TARGETED_DEVICE_FAMILY "1,2" ships an untested iPad app (drop to "1" or plan iPad screenshots); push entitlement only if CKSubscription is adopted | `project.yml:16`, `:152` |
| L3.7 | Signing: team 9WANULVN2G is PERSONAL; Release/archive signing unexercised | `project.yml:215` |

**Manual (not in repo — do in the portals):** paid Developer Program team;
App ID `com.sixfour.SixFour` with Game Center + iCloud; provision container
`iCloud.com.sixfour.SixFour` in CloudKit Console, create Gene/Adoption
(+Report/Block) record types with Sortable `createdAt`, deploy schema to
Production; distribution cert + profile; App Store Connect record, Game Center
enablement, privacy labels, screenshots, sandbox GC+iCloud review accounts.
NOTE: `CKContainer.default()` matches the entitlement only while the bundle id
stays `com.sixfour.SixFour` — renaming silently breaks it.

---

## L4 — train on adopted genes (warm-start = the remix mint)

**Hard rule discovered**: `DeviceTrainGolden.committed` is the bit-exact
four-backend gate and assumes zero init — **seed defaults OFF; the cold path
must stay byte-identical**; the seeded path gets its own golden.

| Step | Change | Anchor |
|---|---|---|
| L4.1 | Spec: `trainDeviceFrom :: [Double] -> …` with `trainDevice = trainDeviceFrom zeroParams`; laws `lawSeedZeroIsColdStart` (byte-identity) + `lawWarmStartConverges`; restate `lawTrainedDetailSurvivesCommit` on a foreign-seed fixture (the cross-capture above-floor claim) | `spec/src/SixFour/Spec/DeviceTrainStep.hs:147` (:173, :222) |
| L4.2 | Codegen: seeded golden section (seedTheta + committed) in DeviceTrainGolden — regen only | `spec/src/SixFour/Codegen/DeviceTrain.hs:29` |
| L4.3 | Metal: SIMT kernel reads init from the theta buffer (index 2 becomes inout) behind a `seeded` flag in FusedTrainParams — keep the Swift struct mirror in lockstep; fixed-order reduction preserves bitwise reproducibility (seed is bytes, no PRNG) | `SixFour/Metal/DeviceTrainShaders.metal:290`, `Train/RungDispatch.swift:21` |
| L4.4 | Swift: widen `trainOnVolume(…, seed: [Float]? = nil)` → `runSimtPass` pre-writes the 21 seed floats; `CaptureGene.train(…, seed: ThetaUp?)`; MPSGraph `DeviceTrainer.init` gains the same seed (it is the live pattern — AtlasTrainer exists only in a stale worktree, don't cite it) | `RungDispatch.swift:158`/`:227`, `Train/CaptureGene.swift:62`, `Train/DeviceTrainer.swift:181` |
| L4.5 | Lineage recording: `ThetaUp` gains `parents: [String]` (+creator/minted) mirroring GeneTag; `finishBurst` passes the user-selected adopted gene as seed → the result IS the remix (parents=[adopted]) | `Train/CaptureGene.swift:18`, `Capture/CaptureSession.swift:794` |
| L4.6 | The adopt→train bridge: `GeneExchange.adopt` decodes a `theta-up` blob to 21 Floats + its GeneTag hash, exposed as seed source; gate remix minting on lossReduction vs the seed's floor (the B3 cross-capture measurement — still the go/no-go) | `GeneExchange.swift:78` |

---

## L5 — the GeneAtlas (the "RAG" gene visualization)

Retrieval-augmented browse: genes laid out by SIMILARITY, retrieved
nearest-neighbor to YOUR capture's θ_up, with lineage edges — on proven substrates.

| Step | Change | Anchor |
|---|---|---|
| L5.1 | Spec: `atlasScene` (card grid + lineage strip + tap→trade region) under the SAME 8 layout laws; codegen into GridLayoutContract (+ selfCheck spans three scenes; LINT-GOLDEN list, L0.5) | `spec/src/SixFour/Spec/GridLayout.hs:124` (laws :178–262) |
| L5.2 | **`Spec.GeneSimilarity` — LANDED 2026-07-02 (5 laws green) as a PULLBACK, not a flat metric**: a θ is never compared word-by-word (gauge-ridden chart — the `buildPixels`/S₂₅₆-orbit lesson); it is EXPRESSED on a pinned 9-stimulus probe lattice via the real `predictDetail` (Q16 commit inside) into a P6 cloud, and `cloudDistance` is pulled back — pseudometric BY THEOREM. Gauge quotient proven (sub-quantum θ ≠ zero word-wise, distance 0); distance-to-origin = expressed detail energy. σ-look (384) joins only via its OWN expression map (palette reconstruction) — never a flat dot product. Remaining: the nearest-neighbor retrieval function over a gene list (trivial fold over `geneDistance`) + the sandwich port (L5.2b) | `spec/src/SixFour/Spec/GeneSimilarity.hs`, `spec/src/SixFour/Spec/CrossEncoderDistance.hs:77` |
| L5.2b | **The sandwich port** (see "The sandwich ruling" below): `[1] probe gather — int (Zig SIMT / Metal int twin)` → `[2] express+commit — the ONE float layer (MPS/tensor-op), fenced by reenterQ16` → `[3] d6 accumulate — int`. Three compartmentalized kernels, each oracle-gated separately; `geneDistance :: … -> Int` is the witness that everything after the commit is integer | `Native/src/kernels.zig` (new `s4_gene_express`/`s4_gene_d6`, header discipline L0.1), fixtures via `spec/app/Fixtures.hs:59` |
| L5.3 | Feed data: `GeneSummary` gains embedding vector (or projection), showcase-GIF reference, parentHashes — today it is embedding-blind and thumbnail-blind, the single biggest viz data gap | `GeneExchange.swift:12` (browse :69), `GeneCloudSchema.swift:54` |
| L5.4 | Renderers (reuse, don't invent): `PaletteCloudView`'s orthographic distance-true scatter for the similarity layout (screen distance IS metric distance — keep orthographic-only); `NudgePaintView`'s Morton cell grid as the card-gallery fallback | `SixFour/UI/Components/PaletteCloudView.swift:111` (:62), `Editing/NudgePaintView.swift:141` |
| L5.5 | Showcase-GIF cards need a decode path — **none exists**: add a Swift bridge to `s4_gif_decode` (header discipline L0.1) OR decode via ImageIO (system framework, contract-clean). Decide once; ImageIO is the cheap launch answer, the Zig bridge the byte-exact one. | `Native/src/kernels.zig:2066`, `SixFour/Native/SixFourNative.swift` |
| L5.6 | `UI/Screens/Atlas/GeneAtlasView.swift` + model (mirror DecideSurface): `place(_:in: atlasScene)`, browse feed + "my genes" lane from GeneStore, NN-to-my-capture rail, lineage overlay via a `GeneLibrary/Lineage.swift` port (ancestors/descendants/isOrigin), tap→trade routes into L2.8's trade surface | `UI/ScreenLattice.swift:36`, `GeneStore.swift:19` |

PICO-8 cart sketch for atlasScene is optional (owner bypassed it for
decisionScene — "grid-first" precedent).

---

## The sandwich ruling (cross-cutting, owner 2026-07-02)

**One large kernel cannot do everything.** Every GPU algorithm in this plan is a
SANDWICH of compartmentalized stages: integer floor ops (Zig SIMT on CPU, or
their byte-exact Metal integer twins) alternating with learned/float MPS
tensor-op layers, the Q16 commit sealing every seam. Each stage is its own
kernel, gated separately against its Zig oracle (the `v21AccumulateHistKernel`
precedent) — never one mega-kernel whose interior cannot be compartment-tested.
This is the `GeneTaxonomy` cascade generalized from training to EVERY pipeline:

- L1.2's 256³ builder: `[int octant gather] → [float θ_up invent → Q16 commit] →
  [int unlift/assemble]` per rung, staged encoders in one command buffer
  (the B2.3 two-encoder precedent), not one fused monolith.
- L4's seeded trainer: seed enters stage 2 as bytes; stages 1/3 untouched — the
  cold-path golden survives BECAUSE the stages are separable.
- L5.2b's gene metric: `int probe → float express+commit → int d6` — the
  minimal sandwich (exactly one float layer), integer-valued by type.

Flat objects are never compared or processed in their chart: lift by
PROJECTION/EXPRESSION onto the proven lattice objects (P6 clouds, A₇ detail
bands, S₂₅₆ orbits, the Q16 ℤ[1/2] window) and do the work there — discrete
geometry + algebraic number theory is the house frame, and every stage boundary
is a lattice re-entry.

## Dependency order

```
L0 (gate repairs)
 ├─ L1.1 spec FSM+scene ─ L1.2 builder(Zig→fixtures→Metal) ─ L1.3 UI loop ─→ curated export
 ├─ L2.1 codegen ─ L2.2 codecs ─ L2.3/2.4 mint seams ─ L2.5 import ─ L2.6–2.9 store/ledger/arms
 │        (L2.5 needs L3.2 doc types; L2.3 grant path needs L2.8 ledger; showcase ships without it)
 ├─ L3 services/portal (parallel; L3.4/3.5/3.6 are submission blockers)
 ├─ L4 needs L2.2+L2.7 (decode adopted θ) — spec L4.1 can start immediately
 └─ L5 needs L2 feed (L5.3) — spec L5.1/5.2 can start immediately
```

Per-round loop, always: `cabal test` → `cabal run spec-codegen` (+`git add` new
Generated files) → `scripts/regenerate.sh` → arm64 compile-check → the L0.2
test verb → device run for anything the simulator can't prove (camera, GameKit,
CloudKit, jetsam).

## Honest gaps (carried, not hidden)

- Cross-capture θ_up quality (does a foreign gene express/seed WELL?) is
  unmeasured — B3 `lawAboveFloorMarginMeasured` is the go/no-go for promising
  anything in the trade UI (L4.6 gates the remix mint on it).
- Paint→pixels conditioning awaits the D1 field encoder; the curate preview is
  honest about it until then.
- The GeneId/CreatorId content-hash (and Swift agreement) is unpinned — blocks
  CloudKit record-id dedup (L2.8).
- App Review 1.2 moderation surface (L3.5) is designed nowhere; it is a launch
  requirement for a public trading economy, not polish.
