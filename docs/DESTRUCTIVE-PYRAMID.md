# DESTRUCTIVE PYRAMID: the learned multi-scale ladder, the 32³ pitstop, and the determinism concession that must buy rate

> Status: DESIGN OF RECORD · 2026-07-02 · Owner: SixFour
> Companions: `docs/GENE-COMPUTE-ECONOMY.md`, `docs/DEVICE-MODEL-MAP.md`, `docs/GIF-NATIVE-MODEL.md`, `CLAUDE.md`.
> Spec wins on any disagreement. Anchors are `file:line`, grep-confirmed against the gather reports; PROPOSED laws are named as such and are not anchors. Start any spec browse at `SixFour.Spec.Map`.

---

## 1. THE DIRECTION + VERDICT

The direction: build the coarse-to-fine ladder 16³ / 32³ / 64³ / 128³ / 256³ as a **destructive learned Laplacian pyramid**. ANALYSIS descends (64³ pooled down to 32³ to 16³), storing one band-pass residual latent per rung and freeing the source buffer in place. SYNTHESIS ascends, adding residuals back. The 32³ rung is materialized as a **resumable pitstop**: base cube plus latents-so-far plus a scale marker, banked to disk, expandable to 128³/256³ later, and tradeable as the swap carrier. Determinism is **negotiable per rung**: byte-exactness may be conceded on the analysis collapse where information theory says exactness buys nothing.

**VERDICT: SOUND-WITH-FIXES, and the fix is a sequencing rule, not a redesign.** The byte-exact spine is real and buildable today: the up-ladder (`s4_cube_expand_rung` `Native/src/kernels.zig:924`), the additive prefix residual (`RefinementSystem.unliftVec` `RefinementSystem.hs:143`), the lossless held-residual collapse (`SuccessiveRefinement.split`), the single float-to-int door (`reenterQ16` `ByteCarrier.hs:92`), and the conservation tripwire (`JepaMemory.hs:11`) give roughly 90% of the substrate. Three things reopen locked decisions, and one claim is a hallucination unless renamed. What **reopens a lock**: materializing 32³ as a surfaced cube directly contradicts `lawIntermediateNeverSurfaces` (`RungPivot.hs:158`) and drags `HalfwayLatent.lawFuseIsMidpoint` and `JepaMemory.lawLatentCapacityMatchesPivotCube` with it. What is a **hallucination if mislabeled**: everything above 64³ has no captured ground truth (`SelfSimilarReconstruct.lawBeyondCaptureInvented`), so "expand the pitstop to 128³" is invented extrapolation, never a rebuild. **The one info-theoretic condition the determinism concession must meet: it must BUY rate, not merely accept loss.** Concretely, byte-exactness may be conceded on rung k only when a MEASURED, DescriptorQuasiIsometry-lower-bound-passing, additive-in-rank residual coder beats LZW-on-the-source-GIF at fixed distortion, AND the REDUCE operator is a proven Markov degradation (the Equitz-Cover refinability precondition). Until that number exists on real captures, the concession is unjustified: a lossy collapse is a strictly WORSE predictor than the deterministic block-sum, so it inflates the residual it must then store. Ship the pyramid **lossless first** (the genuine wins, the 768 MiB reclaim and the resumable tradeable pitstop, are independent of lossiness), and gate every lossy path behind that rate witness.

---

## 2. THE SCALE LADDER

Five first-class rungs, depth bounded (octree ceiling `octreeDepth`=8). Each octant rung DOUBLES side (2×2×2 per voxel), so every 16→32, 32→64, 64→128, 128→256 hop is exactly ONE `levelsPerStep=1` application of `s4_cube_expand_rung` (`kernels.zig:924`).

| Rung | Synthesis (up) today | Analysis (down) today | This design |
|---|---|---|---|
| 16³ | materialized base | `split`/`distill` target, lossless | KEEP as palette-basis, do NOT make content (§2 reopening) |
| 32³ | computable, NOT exposed; `IntermediateLatent` continuous-only (`RungPivot.hs:117`) | none (never surfaced) | **materialize as resumable pitstop cube** (breaks `lawIntermediateNeverSurfaces`) |
| 64³ | capture pivot, identity (`HJepaLevels.hs:29`) | pivot; `poolSpatial` 64→16 lossy-no-residual | freed in place after residual commits (destructive) |
| 128³ | computable via `s4_cube_expand_rung(side=64)`, NOT exposed | n/a (never captured) | INVENTED tail, needs 32/64-level latents; no byte-golden |
| 256³ | materialized (`reconstruct256` `SelfSimilarReconstruct.hs:145`) | n/a (synthesis-only) | unchanged, invented above 64³ |

**Materialized today: 16³, 64³, 256³ only.** The shipped API jumps 16↔64↔256, each a two-octant-level `levelsPerStep=2` hop (`SelfSimilarReconstruct.hs:154`). The driver is per-rung generic (any `side`), so 32³ and 128³ are individually computable but never exposed as stop points. This design exposes them.

**Analysis is DESTRUCTIVE, synthesis is exact-from-latents.** ANALYSIS (down): 64³ pool to 32³ pool to 16³, storing only the residual at each rung, freeing the source buffer the moment the residual commits (reclaims A6 `v21HistBuffer`, 768 MiB, alloc `CaptureSession.swift:649`). SYNTHESIS (up): 16³/32³ + banked residuals expand deterministically; the 128³ residual is invented S-detail (`synthBeyond` `CubeLadder.hs:93`, `lawZeroTailIsFloor`), never claimed exact.

**The "16 = basis not content" reopening and its cost.** V21Pyramid pins 16×16 as a PALETTE basis: `lawSixteenIsPaletteBasis` (16²=256 = one atom per palette slot), `lawCoarseModeIsRealizable`, `lawFineNotRecoverableFromCoarse` (`V21Pyramid.hs:79`). These say 16³ is a lossy non-invertible colour-distribution context, NOT a content raster. Making 16 a content scale reopens all three. RECOMMENDATION: do NOT. Keep 16³ as the palette basis and make **32³ the coarsest CONTENT pitstop**; stop destructive analysis at 32³. The "burst-SR 16→64 KILLED" note is a memory decision with no code law behind it (grep found none), so it is cheap to leave settled: 16³ stays plan/palette, 64³ stays the capture pivot.

---

## 3. ANALYSIS + SYNTHESIS

**The Laplacian-on-the-octant-ladder skeleton (Burt-Adelson 1983), realized in lifting form (Sweldens 1996).** Per rung k, the band-pass residual is `residual_k = fine − EXPAND(REDUCE(fine))`, where EXPAND is the zero-detail octant floor (`s4_cube_expand_rung(details=null)` `kernels.zig:945`; spec `synthBeyond`) and REDUCE is the analysis pool. Reconstruction is `fine = EXPAND(coarse) + residual`, i.e. `refine ∘ split = id` restated as a Laplacian. The lifting scheme gives the in-place mechanism: the residual overwrites its inputs as you descend (no auxiliary buffer), which is exactly the destructive in-place consumption. Integer-rounding lifting is the byte-exact mode; the same structure without rounding (or with residual quantization) is the lossy mode. One pyramid, two modes, one mode switch per rung.

**The per-rung residual latent: what, how stored, how quantized.**
- WHAT: the "surprise" the coarser scale cannot predict, `fine − EXPAND(coarse)`, a decorrelated low-variance band (bits concentrate on detail, not redundancy).
- HOW STORED: additive-in-rank int32 bands, RLE-serialized in the `V21FlowExport.mapsData` format (`:355`, little-endian i32), alongside a Q16 scale marker. Additivity is load-bearing (§5): it is what keeps the strong AnytimeDecode prefix law alive.
- HOW QUANTIZED: through the single sanctioned door `reenterQ16` (`ByteCarrier.hs:92`) before any byte commits. There is no other `Latent -> Int`; a float carrying a device byte is a type error (`ByteCarrier.hs:87`, law `lawByteOnlyFromQ16 :109`). Lossiness lives strictly ABOVE this seam; the add-back arithmetic below it stays ℤ[1/2] with no `recip` (`RefinementSystem.hs:8,:61`).

**predict(coarser) to finer.** EXPAND is the deterministic zero-tail floor: each coarse voxel expands to its 2×2×2 block via `s4_octant_unlift` (`kernels.zig:887`), the I-pair of `s4_octant_lift` (`:857`). Feeding banked `residual_k` as the `Maybe [Detail]` argument recovers the fine rung exactly; feeding `null` yields the valid-but-lossy floor. This is the same fork that `reconstruct256` iterates (`SelfSimilarReconstruct.hs:145`); the design merely stops hiding 32/128.

**The invented 128³ rung (no ground truth).** Analysis descends only FROM 64³, so residual@128 was never captured. Reaching 128³ therefore falls to the invented S-detail tail (`lawBeyondCaptureInvented`), gated by the zero-detail floor, NEVER a stored-latent recovery. This must be labeled invented extrapolation in the data-flow language: "SYNTHESIS up to 256³" reads as reconstruction but above 64³ it is hallucination-with-a-floor. Corollary: content-addressing (`GeneHash`) MUST be forbidden above 64³, because a 128³ address depends on inventor weights and is non-reproducible across retrains.

**Destructive in-place consumption.** The moment `(coarse_k, residual_k)` commits, release the source buffer. A6 `v21HistBuffer` (768 MiB) is the prime target; B2 flow transients (anchor 12 MiB + 64× slice copies) follow. Peak RSS drops from ~1 GiB toward the ~30 MB render tail. This free is the GC that D1 lacks today (`DEVICE-MODEL-MAP.md:54`, "files accumulate forever, NO GC"). HONEST CAVEAT (from critique): this reclaims RAM, not disk. A lossless pyramid on disk is ~4/3 of its finest level and does NOT beat the source LZW GIF; the destructive free is a peak-RSS win, not a compression win, and must never be sold as the latter.

---

## 4. THE PITSTOP

**The resumable 32³ artifact.** A serialized record `Pitstop = { base :: Cube32 (Q16 int), latents :: [(scale, Detail)] held-so-far, scale :: Int, resumable :: Bool }`, a fusion of the two Codable shapes that already round-trip on device: `CaptureGene.ThetaUp` (`CaptureGene.swift:18`) and the UUID-stamped `CaptureBundle` JSON (`CaptureBundle.swift:97`). On disk it is a V21-style stem bundle: `<stem>.gif` (32³ rendered small, S4GX-carriable, = Showcase depth-0 floor) + `<stem>_latents.bin` (i32 RLE, `mapsData` format `:355`) + `<stem>_manifest.json` (extend the `V21Manifest` schema `V21CaptureField.swift:284` to `sixfour.pyramid/1`: `base_scale=32`, rung list, `resumable=true`). Storage slot: the GeneStore organ pattern (`GeneStore.swift:5,81`), durable, indexed, AirDrop-importable.

**The reachability law: 128 needs the 32-latents.** State machine over nodes {16,32,64,128,256}; legal transition `expand(s to 2s)` iff `residual@s` is held (else zero-detail floor expand, valid but lossy). To reach 128³ from a banked 32³ you must climb `expand 32 to 64` (needs residual@32) then `expand 64 to 128` (residual@64 is INVENTED, not held). PROPOSED `lawScaleReachableIffLatentsHeld`: scale s+1 is exactly-reachable from the banked artifact iff all residuals through s are held; a missing residual is not a fault, it falls to `lawFloorAlwaysDecodable` (valid lossy expand). CRITICAL HONESTY (from critique): this law spans two provenances that MUST NOT share one `latents` list. residual@32 recovers the original 64³ (real, rebuild). Nothing recovers 128³ (invented, hallucination). "Bank at 32³, expand to 128³" is selling super-resolution invention as checkpoint resume unless the provenance split is explicit in the type.

**Resume determinism.** Analysis may be lossy and float; once residuals commit through `reenterQ16` the synthesis add-back is pure integer, so a paused pyramid is byte-identical to a resumed one across devices. PROPOSED `lawResumeIsDeterministic`: `synthesize(load(bank)) == synthesize(base, latents, scale)`. This is real and matches the ledger CKPT semantics (`DEVICE-MODEL-MAP.md:5.3-5.4`: lift/unlift are `I` replayable seams; S-mint rungs log blob-hash + committed bytes). CAVEAT (from critique): deterministic REPLAY of a lossy bank proves the two replays agree, NOT that the output equals the destroyed 64³. If the pitstop base is a lossy commit of the ViT fuse waist (32768 continuous dims, `HalfwayLatent.lawFuseIsMidpoint`), a resume from 32³ CANNOT reach the same 256³ the continuous path would. Do not sell "resumable == one-shot"; sell "resumable == a valid, banked, lower-distortion prefix."

**How the pitstop BECOMES the swap carrier.** The 32³ GIF carries the S4GX App-Extension block unchanged (`SwapCarrier.swift:41`), because the carrier targets the CONTAINER not the resolution (`extract` probes bytes without LZW decode, `:88`). A `.showcase` trade = depth-0 = the coarse base floor = zero weight words = `FloorExact` (`GENE-COMPUTE-ECONOMY.md:294`); a `.grant` carries real latents. The residual side-channel rides alongside in the V21-field pattern. The banked base+latents ARE the persisted app state D1's un-GC'd GIF store never had, so the destructive collapse is simultaneously the missing GC and the tradeable checkpoint. UNBUILT: no serializer for the partial-pyramid tuple, no Swift persist/reload caller, and `s4_gif_decode` (`kernels.zig`) still has zero Swift callers (on device the GIF is write-only).

---

## 5. DETERMINISM LEDGER

The single crossing everything pivots on is `reenterQ16 :: Latent -> Q16` (`ByteCarrier.hs:92`), the only sanctioned float-to-byte door. Lossiness lives above it; everything below is integer. The rule: **analysis MAY relax under a rate-distortion witness; synthesis stays deterministic-from-latents so a swapped pitstop rebuilds identically cross-device.**

| Op | Verdict | Reason |
|---|---|---|
| `reenterQ16` seam (`ByteCarrier.hs:92`) | KEEP, becomes MORE load-bearing | Both the analysis float and the synthesis float now re-enter here; it is the boundary, not the fidelity |
| Final GIF89a emit (`SwapCarrier.hs:442` `lawGif89aValidity`, `:434` round-trip) | KEEP byte-exact, free + non-negotiable | A lossy file is not a valid file; every viewer must play it; it is the container, not the pixels |
| Swap-carrier id / GeneHash (FNV-1a over `canonicalBytes`, `lawParentsChangeAddress`) | KEEP byte-exact | Dedup = identical content implies identical id; a lossy id breaks the acyclic-DAG dedup theorem |
| GeneRecombination `lerpWord` (dyadic `>>16`) | KEEP byte-exact | Operates on committed integer gene words; relaxing makes bred children non-reproducible |
| Synthesis add-back (octant/prefix, ℤ[1/2], no `recip` `RefinementSystem.hs:8`) | KEEP byte-exact | This is the cross-device resume guarantee: identical latents rebuild identically |
| Analysis collapse encoder (64→32→16 REDUCE) | MAY RELAX under RD witness | Today deterministic block-sum (`poolSpatial`); the natural site for a learned lossy pool, IF it buys rate |
| Residual-latent quantization | MAY RELAX under RD witness, MUST stay additive-in-rank | Lossy-but-additive is a valid successive-refinement code; lossy-non-additive breaks the strong prefix law |
| Total golden gates | SPLIT | Integer ops stay total-golden; a learned float collapse moves to trainer-tier tolerance (Tier-0/Tier-1 line) |

**The laws.**
- PROPOSED `lawEmitByteExact`: the shipped GIF is deterministic. Constructible now over `lawGif89aValidity` + the emit path. Tier-0.
- PROPOSED `lawCarrierIdByteExact`: swap dedup survives. Constructible now over `GeneHash.canonicalBytes` injectivity + `lawParentsChangeAddress`. Tier-0.
- PROPOSED `lawAnalysisMayRelaxUnderRD`: the collapse MAY be lossy IFF R-D-justified (`λ·ΔD` vs `ΔR`). The `RemainderTail` exact/lossy TYPE split (`Surfaced` vs `Remainder`, `lawTailWithinEps`) gives the eps-typed skeleton; the RD-slope comparator is a new primitive. Tier-0 STATEMENT constructible, WITNESS is trainer-tier.
- PROPOSED `lawLossyFloorIsValidPrefix`: each coarse scale is a valid R-D prefix, not a byte-exact reconstruction (Equitz-Cover successive-refinement form, `AnytimeDecode.hs:30`). Constructible NOW only in its weak-totality half (a coarse base always expands to a valid image); the "valid R-D prefix" half is TRUE only when REDUCE is a genuine Markov degradation, which a learned VQ is not guaranteed to be. Name it honestly: it does not cover the learned lossy case.

**The rule, stated as the corridor a lossy analysis must fit.** From the three critiques converging: the RD gate fires "go lossy when `H(fine|coarse)` approaches raw residual entropy," i.e. where the residual is WHITE and near-incompressible, which is exactly where quantization saves ~0 bits. Rate savings live on the STRUCTURED low-rung residuals, which is exactly where DescriptorQuasiIsometry's lower bound (no code collapse, Vandermonde full-rank `DescriptorQuasiIsometry.hs:133,:173`) AND additive-in-rank forbid a naive VQ. So determinism may be conceded only where it purchases nothing, and is forbidden where it would purchase rate. The safe inhabitant is a **deterministic scalar quantizer on the additive prefix-difference residual**, NOT a learned VQ codebook: it keeps additivity, keeps the strong AnytimeDecode half, keeps `coarse + residual = finer` up to 64³, and lets a learned net only PREDICT to shrink the residual entropy, never DEFINE the transform. The learned VQ and the additive residual are mutually exclusive; pick additive.

---

## 6. INTERACTION WITH LANDED LAWS

- **AnytimeDecode** (`AnytimeDecode.hs`). SPLITS. The strong prefix-optimality `lawDecodeIsAnytime` (`:75`) is stated on the additive `unliftVec` and is already deliberately FALSE on the averaging `unliftOct` (`:12`, `badRenorm :69`). A lossy VQ residual is generically non-additive, so it breaks the strong law the same way; it survives ONLY if the residual code is additive-in-rank. The weak `lawFloorAlwaysDecodable` (`:87`, totality on the 8·s³ voxel cube) survives verbatim: a coarse base is always expandable to a valid, if lossy, image. VERDICT: keep the weak floor unchanged, add a `lawDecodeIsAnytimeLossy` VARIANT (Equitz-Cover form) restricted to additive residuals.
- **DescriptorQuasiIsometry** (`DescriptorQuasiIsometry.hs`). SURVIVES and becomes an ACTIVE constraint, not free. The upper bound (no discontinuity `:169`) a CNN gets free; the LOWER bound (no collapse, Vandermonde full-rank `:133,:173`) is exactly what a naive VQ violates by collapsing distinct looks to one code. So DQ CAPS how lossy the collapse may be, or `κ` re-pins coarser. The floor-rep math (`quantizeQ16`) stays byte-exact. VERDICT: this is the admissibility gate a learned lossy collapse must pass; it is why the safe quantizer is scalar-on-prefix-diff, not VQ.
- **GeneRecombination** (`GeneRecombination.hs`). SURVIVES unchanged. Operates on committed integer gene words downstream of any float; dyadic `lerpWord >>16` stays byte-exact so bred children keep reproducible content-addresses.
- **PacketEconomy** (`PacketEconomy.hs`). SURVIVES. `meaning` is measured on committed output bytes vs a held target, so the integer metric stays integer even if the decode PATH is internally lossy; lossy analysis changes S/K/I packet ACCOUNTING, not the meaning scalar.
- **SwapCarrier** (`SwapCarrier.hs`/`.swift`). SURVIVES. The S4GX block targets the container not the resolution, so the 32³ pitstop GIF carries a gene unchanged; `.showcase` = depth-0 = the coarse floor. GIF89a validity (`:442`) + CRC32 (`:545`) + GeneHash dedup stay byte-exact and non-negotiable. CAVEAT: destroying the source 64³ GIF changes that capture's content-address, so lineage that hashed the 64³ artifact is orphaned and a re-derived 64³ will not match the banked 32³ id. Forbid content-addressing above 64³ and treat the pitstop as a NEW address, not a re-derivation.

---

## 7. BUILD PLAN + NEW LAWS

Dependency-ordered. Everything through step 6 stays byte-exact and gateable; only step 7 goes float, and only behind a measured rate witness.

1. **Spec Tier-0 on the EXACT path** (constructible via `runghc -isrc`, no float, no kernel): PROPOSED `lawResidualIsLaplacianBandpass` (`EXPAND(pool(fine)) + residual == fine`, reuse `split`/`refine` + `synthBeyond`; this is `refine ∘ split = id` restated, green immediately, concedes nothing) + PROPOSED `lawReduceIsMarkovDegradation` (mirror `V21Pyramid.lawCoarseIsBlockSumOfFine` + `SuccessiveRefinement.lawMarkovByPooling`). AUTHOR THESE FIRST. Note the critique: law #1 is a definitional identity of the LOSSLESS path and says nothing about the shipped lossy mode, so it proves the skeleton, not the value proposition.
2. **Spec unblockers**: PROPOSED `lawScaleReachableIffLatentsHeld` (pure reachability fold over `[Maybe Detail]`) + PROPOSED `lawResidualAdditiveInRank` (clone `V21Transport.lawFlowAdditiveInRank` onto the residual store) + PROPOSED `lawResumeIsDeterministic` (equality over the integer add-back oracle). All constructible now.
3. **The keystone reopening**: PROPOSED `lawPitstopIsCommittedNotLatent`. The materialized 32³ is POST-`reenterQ16` committed bytes, a distinct TYPE from `RungPivot.IntermediateLatent` (a sub-ULP float), so surfacing it does not violate the "two sub-ULP latents share a byte" argument of `lawIntermediateNeverSurfaces` (`RungPivot.hs:158`). Constructible against `ByteCarrier.reenterQ16` + `RungPivot` types. HARDEST spec step; do before any code. HONEST COST: this quietly ABANDONS `lawLatentCapacityMatchesPivotCube` (the spatial VQ pool cube is not the 32768-dim ViT fuse waist), so re-green `HalfwayLatent`/`JepaMemory` dependents deliberately, do not pretend they are preserved.
4. **Floor restatement**: PROPOSED `lawDecodeIsAnytimeLossy` (VARIANT, weak totality reused verbatim, strong half only under additive) + PROPOSED `lawBeyondCaptureInvented`@128 (extend `synthBeyond`/`tailToDetail` to side=128, flag INVENTED, no byte-golden).
5. **Zig**: expose 32/128 stops (call `s4_cube_expand_rung` at `levelsPerStep=1`); add an EXACT-integer `s4_cube_pool_rung` REDUCE that STORES an additive residual (UNBUILT: `poolSpatial` stores none, `split`/`distill` keep everything). Ship destructive-but-LOSSLESS first.
6. **Swift lifecycle + format**: destructive in-place free of A6 after each rung commits, gated by PROPOSED `lawDestructiveFreePreservesReconstruction` (checked against `JepaMemory` conservation); the `sixfour.pyramid/1` manifest, `V21Npy.encode` + `mapsData` serializers, the `(base32, latents, scale)` Codable record, the S4GX wire onto the pitstop GIF, the missing `s4_gif_decode` Swift caller. Add a PROPOSED `lawPitstopBytesVsSourceGif` storage-size law so pyramid inflation is justified explicitly by resume/peak-RSS, never sold as compression.
7. **LAST, trainer tier (determinism conceded HERE, and only here)**: a learned residual coder that PREDICTS to shrink entropy while staying scalar-additive, passing the DQ lower bound; PROPOSED `lawRateDistortionGate` MEASURED (go lossy only where the residual is white AND the coder beats LZW-on-the-64³-GIF at fixed distortion AND REDUCE is a proven Markov degradation). Trainer-tier tolerance goldens, not total-integer. The 128³ invented rung gets NO byte-golden; its verification is distribution-only.

---

## 8. OPEN DECISIONS FOR THE OWNER

1. **Does destroying the GIF replace it with the pitstop artifact as the swap carrier?** (THE BIG ONE.) RECOMMENDED DEFAULT: NO for now, ADDITIVE later. Keep the 64³ GIF as the primary durable output and its content-address; bank the 32³ pitstop as a SEPARATE, additionally-tradeable artifact with its own address. Forbid content-addressing above 64³. Reason: destroying the 64³ orphans existing lineage (§6 caveat) and the on-disk win is unproven; the RAM reclaim (A6 free) does not require destroying the file.
2. **Materialize 32³ (reopen `lawIntermediateNeverSurfaces`) or stay non-resumable?** RECOMMENDED DEFAULT: materialize, via `lawPitstopIsCommittedNotLatent` (the committed-byte-vs-float escape), accepting that `lawLatentCapacityMatchesPivotCube` is abandoned not preserved. Fallback if review rejects the escape: compute 128³ one-shot from 64³, no bank.
3. **Learned VQ collapse or deterministic scalar-on-prefix-diff quantizer?** RECOMMENDED DEFAULT: scalar-on-prefix-diff. It is the only inhabitant of the corridor (additive + DQ-passing); the learned VQ is mutually exclusive with the resume guarantee and barely compresses where it is legal.
4. **Concede determinism now or ship lossless first?** RECOMMENDED DEFAULT: lossless first (steps 1-6), concede only after step 7's rate witness lands. The genuine wins (768 MiB reclaim, tradeable resumable pitstop) are independent of lossiness.
5. **Stop analysis at 32³ (keep 16³ as palette basis) or descend to 16³ content?** RECOMMENDED DEFAULT: stop at 32³. Descending to 16³-as-content reopens three V21Pyramid basis laws for no captured benefit.
6. **128³/256³ naming.** RECOMMENDED DEFAULT: rename every above-64³ path "invented extrapolation" in code and docs, never "rebuild"; forbid GeneHash above 64³.
