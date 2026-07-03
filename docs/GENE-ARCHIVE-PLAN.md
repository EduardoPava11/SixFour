# GENE ARCHIVE + SWAP PROTOCOL: PLAN OF RECORD

2026-07-02. Synthesized from three candidate designs (Diversity-First, Economy-First, Minimal-Ship) judged under three lenses (economy integrity, QD soundness, ship cost). VERDICT UP FRONT: **Minimal-Ship skeleton wins** (highest lens total 22/30, only design whose critical path contains zero unbuilt prerequisites and zero wire change), with three grafts: `neutralStash` + `lawReindexTotalOnStoredPhenotype` from Diversity-First, recompute-and-verify GeneId at insert + content-dedup invariant from Economy-First. Spec laws first, per the house pattern: law, Zig/Swift port, golden gate.

Grounding docs: DEVICE-MODEL-MAP.md §7.3 (Hart EDQD merge strategies, M2 MemoryMap ruling), the four map reports (swap-economy contract state, gene payload/fitness survey, descriptor feasibility, archive physical home). Every file:line anchor below is carried from those reports; none is invented.

---

## 1. PROBLEM STATEMENT

Phones train genes. The only gene trained on device today is `CaptureGene.ThetaUp` (CaptureGene.swift:18-33): 21 fp32 up-rung weights plus telemetry, trained per burst by `RungDispatch.trainOnVolume` (RungDispatch.swift:203-220), bitwise-reproducible, riding `Surface.thetaUp`. It has no persistence, no hash, no identity: it dies with the capture.

Genes travel in GIF carriers. The S4GX Application-Extension block (spec/src/SixFour/Spec/SwapCarrier.hs:53-57, MAJOR=2 at :159; Swift port SixFour/GeneLibrary/SwapCarrier.swift) embeds one gene per carrier GIF: content-address `gtGene` (i64 FNV-1a over Q16 payload plus ordered parents, GeneHash.hs:79-110), `gtCreator`, ordered `gtParents`, `gtMinted`. Two profiles: Showcase (weights physically absent, floor-rendered, `lawShowcaseIsInert` SwapCarrier.hs:457) and Grant (weights present, gated by `mayGrant` :381-384 on creator sovereignty or a settled trade). The Swift codec is golden-gated (L2.1/L2.2 DONE, LAUNCH-BUILD-WORKFLOW.md:166-175) but no export or import call site ships it yet.

The economy must spread quality without collapsing to monoculture. The Hart 2018 EDQD result (DEVICE-MODEL-MAP.md §7.3) says cell-wise argmax merge over a behaviour-descriptor archive is coverage-monotone by construction: merging never deletes a cell, it only upgrades champions, so more sharing means more quality pressure with no diversity cost. The monoculture risk lives elsewhere: a single global fitness scalar, drifting learned descriptors, or gossip that inflates one popular look. The archive IS both the mint ledger's local view and the browse gallery.

Provenance must keep the mint ledger sound. Credit is created only by `mintGrant` from a settled trade (`lawGrantOnlyFromSettledTrade` SwapCarrier.hs:468-486); holdings are a monotone fold over an append-only ledger proven G-Set CvRDT (Spec/LedgerCRDT.hs). But tag fields on the wire today are unauthenticated claims: CRC32 is integrity, not authenticity. Re-share, replay, and forged carriers must not mint credit or corrupt attribution.

All of this under device constraints:
- **Sparse AirDrop contact.** No always-on network; encounters are rare. This forces M2 semantics (persistent MemoryMap across encounters does the work robot density did in the paper, §7.3 ruling).
- **Byte-exact floor.** Cell-wise argmax merge converges only if two phones compute the SAME cell for the same gene. Descriptors must be integer/Q16 with golden-pinned bin edges; float drift splits one gene across two cells and breaks coverage monotonicity.
- **Unfrozen-adjacent wire.** The v2 wire is frozen to the extent of a byte-exact dual-implementation golden gate. Any wire change reopens that gate; a MAJOR bump breaks the just-landed Swift codec.
- **Only theta_up live today.** The only real fitness scalar is `ThetaUp.lossReduction = 1 - loss/floorLoss` (CaptureGene.swift:30-32), computed every burst, floor-relative, local-only. It does not ride the wire, so received genes arrive fitness-unknown. Social fitness (`GeneExchange.popularity`, GeneExchange.swift:96-99) is built but dead behind disconnected entitlements.

The archive's physical body already half-exists: genotypes plus provenance belong in the `GeneStore` actor (`AppSupport/SixFour/genes/<slot>/`, GeneStore.swift:14-56, today a flat replace-by-hash catalog), phenotype carrier GIFs in `Documents/sixfour_<ISO8601>.gif` (CaptureViewModel.swift:1079-1088, today write-only and unbounded). The job is to turn that catalog into a MAP with laws.

---

## 2. CONSTRAINTS LEDGER

Hard constraints, each with its anchor:

| # | Constraint | Anchor |
|---|-----------|--------|
| C1 | Descriptors must be integer/byte-exact (Q16 or counting) with golden-pinned bin edges; identical GIF bytes must yield identical cells on any device, else merge loses coverage monotonicity | Report 2 §0; Spec/CoverageMonotone.hs lemma shape |
| C2 | Wire is v2, dual-implementation golden-gated; future-MAJOR refused, future-MINOR tolerated | SwapCarrier.hs:159, `lawVersionTolerance` :560; LAUNCH-BUILD-WORKFLOW.md:166-175 |
| C3 | Showcase serializes ZERO weight bytes and expresses `FloorExact`; it is inert | SwapCarrier.hs:255-257, :404-408, `lawShowcaseIsInert` :457 |
| C4 | Grant only from creator sovereignty or settled trade; `mintFor` total, refusal degrades to Showcase | `mayGrant` SwapCarrier.hs:381-384, `mintGrant` :388-391, `lawGrantOnlyFromSettledTrade` :468-486 |
| C5 | GeneId = FNV-1a over Q16 payload plus ORDERED parents; creator/epoch are metadata outside the preimage (Merkle-DAG dedup, acyclicity a theorem) | GeneHash.hs:79-110, :14-17; `lawBuiltGenealogyAcyclic` |
| C6 | Tag fields are unauthenticated claims; CRC is integrity only; signature-on-wire (R6) UNBUILT | Report 0 §2 |
| C7 | Only live fitness = `ThetaUp.lossReduction`; no held-out margin, no JEPA energy on device | CaptureGene.swift:30-32; Report 1 §3A |
| C8 | Above-floor survival threshold = 1 Q16 LSB; device witness = nonzero `committed` bands | AboveFloorMargin.hs:57-58; CaptureGene.swift telemetry |
| C9 | No Swift caller for `s4_gif_decode` exists; pixel decode is unavailable to Tier 2 today | kernels.zig:2122 (scratch :1983), Report 3 §3 grep-confirmed |
| C10 | Import seam does not exist: no CFBundleDocumentTypes, no onOpenURL; the OS cannot route any file to the app | Report 3 §3 |
| C11 | Export mint-at-share (S4GX splice into the Documents GIF) UNBUILT; all pieces exist unconnected | L2.3, anchor V21CaptureField.swift:377-440 |
| C12 | GeneStore is a flat JSON catalog with replace-by-hash `addOrgan`; no descriptor bins, no fitness field | GeneStore.swift:5-13, :85-94 |
| C13 | Documents GIF store is write-only, unbounded, never enumerated; only `Surface.gifURL` reaches the current capture | CaptureViewModel.swift:1079-1088; Surface.swift:70-71 |
| C14 | GameCenter/iCloud entitlements DISCONNECTED pending PLA; CreatorID auth and CloudKit unusable; social fitness dormant | project.yml ~:153-170; CreatorIdentity.swift:16-28; GeneExchange.swift:111 |
| C15 | Cloud creator is a String gamePlayerID, wire creator is i64; no bridge exists | GeneCloudSchema.swift:59 vs SwapCarrier.swift:27; Report 1 §4 |
| C16 | Float diversity stats are inadmissible as axes: `gaussianColorEntropy` goes negative | Spec/EncoderModalityLoad.hs:129; Report 2 §1E |
| C17 | Gallery display rides ONE CADisplayLink at 20 Hz; thumbnails share the single κ clock; cell pitch = 4 pt atom times integer b | Generated/DisplayContract.swift:14, :22-31; PlaybackClock.swift:60 |
| C18 | Sparse-contact ruling: M2 persistent MemoryMap on device; M3 re-broadcast is the economy question and requires provenance | DEVICE-MODEL-MAP.md §7.3 closing ruling |
| C19 | Swift fnv1a64 UNBUILT (golden pinned only); Swift mintGrant/ledger (L2.8) UNBUILT | Generated/GeneHashGolden.swift:10-12; SwapCarrier.swift:12-14 |
| C20 | SixFourTests are not in any gate; Swift goldens run only by hand | gate-order.txt ends at build |

---

## 3. THE THREE CANDIDATE DESIGNS

### 3.1 Diversity-First (illumination)

Adopts Report 2's full 4-axis integer descriptor set (mean palette L, hue octant, gamut coverage, temporal changed-index fraction; 288 cells), all computed from the carrier GIF so Showcase and Grant bin identically. Its signature mechanism is the `neutralStash`: a cell is an elite PLUS a bounded (cap 4) neighborhood of behaviorally near-identical losers (distance 0 under `lawGaugeQuotient`), preserving genotypic diversity beneath one phenotypic cell. Merge strategy = M3 transitive gossip by default, with rebroadcast COVERAGE-weighted (relay elites of sparse cells, never popularity). Two disjoint fitness domains: Grant ranked by `lossReduction`, Showcase ranked by social `popularity`; a cell holds both, `lawShowcaseGrantDomainsDisjoint`. Provenance judged already sufficient in v2 tags; one MINOR wire bump adds `lineageDepth: u8` capped at 16. Tie-break favors origins: fewer parents wins. Sharpest law: `lawReindexTotalOnStoredPhenotype`, keep every phenotype GIF so a descriptor-version bump re-bins the whole archive offline. Build step 1 is the unbuilt `s4_gif_decode` Swift caller.

### 3.2 Economy-First (mint-ledger soundness)

Treats provenance as adversarial input, not metadata. Bumps the wire to MAJOR=3: Ed25519 sign-at-publish/verify-at-import (creatorPubKey + sig over canonical tag bytes), hop count, bounded provenance chain (cap L=8); creator/hop/chain stay OUT of the GeneId preimage to preserve Merkle-DAG dedup. Same 4-axis/288-cell descriptors. Cell payload is a content-addressed SET keyed by GeneId (distinct distance-0 genes coexist); displayed elite = fitness argmax on `lossReduction` with tie-break higher fitness, lower hop, earlier minted, lower GeneId. M2 default; M3 gated behind verified provenance chains, hop >= L disables re-broadcast. Grant weights recomputed-and-rehashed at insert (claim is not content); unverified tags drop with zero ledger effect. Credit created only at settled-trade `mintGrant`: `lawMintCreditConserved`, `lawProvenanceUnforgeable`, `lawM3NoMemehoodInflation` (N re-broadcasts of one GeneId collapse to one entry), `lawShowcaseNoMintCredit`. Resolves the String-to-i64 creator seam via pubkey hash.

### 3.3 Minimal-Ship

Ships a local plus AirDrop M2 archive with palette-only integer descriptors and ZERO wire change. CORRECTION 2026-07-02: the shipped MVP writes NO Global Color Table (kernels.zig:1887 `no GCT`; GIFEncoder.swift:91 GCT flag 0; MVP is per-frame Local Color Tables, `Feature.globalPaletteV2 = false`). The three axes therefore read the PER-FRAME Local Color Tables, aggregated across the 64 frames into one gene-level descriptor (mean palette L via `s4_srgb8_to_oklab_q16` kernels.zig:1962 folded over all frames' LCT entries, hue octant, gamut coverage via shipped `ClusterStatisticsOps.gamutCoverage` over the union of frame palettes). This still needs no `s4_gif_decode` Swift caller (LCT bytes are parsed from the frame headers, not the pixel stream); 96 cells, axis 4 (temporal) deferred to v1.1 for 288. NOTE: aggregating 64 LCTs is the honest per-frame reading; a single-GCT shortcut only becomes available if globalPaletteV2 ships. One elite per cell. Fitness stays OFF the wire; the load-bearing merge rule is `lawReceivedFillsEmptyNeverDisplaces`: own genes ranked by local Q16 `lossReduction`, received (fitness-unknown) genes insert iff their cell is empty and never evict a scored incumbent, which keeps merge coverage-monotone without trusting senders. Dedup by content-hash GeneId (idempotent reinsert, G-Set/SEC aligned with LedgerCRDT.hs). M3 rejected; depth cap enforced at import as policy, not a wire field. Provenance = the existing GeneTag, unchanged. Steps 1-6 are entirely local and parallel to the launch workflow; step 7 (import/export) is the sole L2 join point. Avoids the L3 entitlement blocker completely.

---

## 4. JUDGE VERDICTS

Verbatim scores.

**Lens: ECONOMY INTEGRITY.** Economy-First 9/10 (the only design treating provenance as adversarial; docked one point because hop/chain are not per-hop signed, so the memehood cap is advisory against adversaries). Minimal-Ship 7/10 (sound by minimization, not mechanism; creator remains a visible unauthenticated i64 claim). Diversity-First 4/10 (adopts M3 gossip on unauthenticated tags; `lawGossipPreservesProvenance` binds honest implementations only; popularity is sybil-trivial; "fall back to sender's claimed value" admits claimed numbers). Ranking: 1 Economy-First, 2 Minimal-Ship, 3 Diversity-First.

**Lens: QD SOUNDNESS.** Diversity-First 9/10 (neutralStash is the only genotypic-diversity mechanism; best anti-monoculture stack; disjoint fitness domains; sharpest reindex law; docked for M3-by-default aggressiveness). Economy-First 7/10 (content-set per cell sound; crispest no-inflation guarantee; weakest on Showcase illumination, subordinated to ledger soundness). Minimal-Ship 6/10 (96 cells coarse, no stash; fills-empty-never-displaces means received genes get no within-cell competition; trades illumination quality for shippability). Ranking: 1 Diversity-First (9), 2 Economy-First (7), 3 Minimal-Ship (6).

**Lens: SHIP COST + DEVICE REALITY.** Minimal-Ship 9/10 (critical path avoids the one missing prerequisite; zero wire change; clean of L3; docked for deferred Documents GC and 96-cell coarseness). Diversity-First 5/10 (build step 1 is the unbuilt `s4_gif_decode` caller; Showcase fitness is dead-on-arrival behind entitlements; MINOR bump reopens a golden-gated codec; keep-forever worsens the unbounded store). Economy-First 3/10 (MAJOR=3 plus Ed25519 stacks R4/R5/R6 plus fnv1a64 plus L2.8 as hard prerequisites; "a security project wearing an archive costume"). Ranking: 1 Minimal-Ship, 2 Diversity-First, 3 Economy-First.

**Totals: Minimal-Ship 22/30, Economy-First 19/30, Diversity-First 18/30.** Each design wins exactly one lens; Minimal-Ship never scores below 6 and is the only design with no lens catastrophe (Diversity-First's 4 on economy, Economy-First's 3 on ship cost).

---

## 5. THE SYNTHESIS (plan of record)

**Skeleton = Minimal-Ship.** It wins on total, it is the only design whose every cited component is BUILT today (C9, C14, C19 all routed around), it touches no wire byte (C2 preserved), and its one honest weakness (no within-cell competition for received genes) is the correct price while fitness cannot ride the wire. Three grafts, each credited:

**Graft 1 (from Diversity-First, the QD judge's top pick): `neutralStash`.** A cell = elite PLUS a bounded stash (cap 4, owner-tunable, §8) of behaviorally near-identical losers, distance 0 under `lawGaugeQuotient` (GeneSimilarity.hs:168) or displaced by argmax. Eviction deterministic by fitness then the pinned total order. This restores genotypic diversity beneath phenotypic cells at zero wire cost and gives displaced incumbents somewhere to go, softening the skeleton's one-elite harshness. Law: `lawNeutralStashBounded`.

**Graft 2 (from Diversity-First, the ship judge's pick): `lawReindexTotalOnStoredPhenotype` plus retained carrier GIFs as the re-bin source, PAIRED with a GC size cap (not "forever").** Because descriptors are recomputed from stored GIF bytes, any future descriptor-version bump (axis 4 in v1.1, index entropy, the JEPA embedding axes) is a total offline migration: every archived gene re-bins to exactly one cell, no orphans, zero wire cost. This is the descriptor migration path. Elite-referenced phenotype GIFs are pinned against GC; non-referenced captures are evictable under the cap.

**Graft 3 (from Economy-First, the ship judge's pick): recompute-and-verify GeneId from Grant weights at insert, plus content-dedup as a named invariant.** Only needs the small Swift `fnv1a64` port against the already-pinned `GeneHashGolden.swift` (C19): a Grant whose recomputed hash mismatches its claimed `gtGene` is dropped with zero archive effect (claim is not content). Showcase ids remain explicit unverifiable claims (ruling 6) and can only fill empty cells anyway. Alongside it, adopt Economy-First's `lawM3NoMemehoodInflation` in its M2-applicable form: distinct arrivals of one GeneId collapse to one archive entry, so gossip echoes can never multiply coverage. Laws: `lawGrantHashRecomputedAtInsert`, `lawContentDedupCollapsesEchoes`.

**Forward reservation (from Diversity-First, the economy judge's pick): `lawShowcaseGrantDomainsDisjoint`.** Not activated in v1 (social fitness is dead behind C14), but the archive schema reserves a fitness DOMAIN discriminator now so that when `GeneExchange.popularity` revives, a social scalar can never argmax against a measured `lossReduction` in the same slot. Costs one enum field in archive.json, prevents a schema migration later.

**The plan of record, condensed:**
- **Archive schema:** cell = (meanL bin, hue octant, gamut coverage bin) aggregated over the 64 PER-FRAME Local Color Tables (NOT a GCT; see the 3.3 correction), 96 cells v1, 288 at v1.1 when axis 4 lands. Payload = `{ geneId: i64, cell, fitnessQ16: Int32?, domain: grant|showcase, provenance: GeneTag, stash: [entry] (cap 4) }`. Stored as `archive.json` beside `index.json` in GeneStore; `OrganDescriptor` (Organ.swift:15-24) gains `cell`, `fitnessQ16`, `domain`.
- **Merge policy:** M2 (GeneStore already persists, so M1 would throw persistence away; M3 rejected until provenance is authenticated, per C6/C18). Own scored genes: cell-wise argmax, loser to stash. Received genes: verify (CRC, and hash-recompute if Grant), dedup by GeneId, fill empty cells only, never displace a scored incumbent; on a scored-vs-scored tie use the pinned total order (higher fitnessQ16; unknown loses to scored; earlier gtMinted; lower gtGene).
- **Carrier provenance:** v2 wire UNCHANGED. GeneTag (gtGene/gtCreator/gtParents/gtMinted) is the provenance record; genealogy depth > 16 rejected at import as policy; Grant hash recomputed at insert; creator displayed as an unauthenticated claim until R4/R5/R6 land, at which point sign-at-publish/verify-at-import slots in WITHOUT touching the archive (Economy-First's design is the pre-approved successor for that layer).
- **Fitness:** `lossReduction` Q16-quantized at mint, local only, never on the wire. Archivability floor: nonzero `committed` band (C8). `expressedEnergy` (GeneSimilarity.hs:143-144) is a later Grant-only within-cell overlay, never a cell axis.
- **Descriptor migration:** stored phenotypes re-binnable forever under the GC pin; JEPA axes enter only after crossing `reenterQ16` with their own golden (C1), as axes 5-6, migrated by `lawReindexTotalOnStoredPhenotype`. v1 does not wait.

---

## 6. SPEC LAWS FIRST

New module `spec/src/SixFour/Spec/GeneArchive.hs`, wired per the maintenance contract (spec.cabal exposed-modules, Map entry, Haddock header). Authoring order:

Tier-0 (gate before any Swift ships):
1. `lawCellFunctionDeterministic`: descriptor to cell is a pure integer function; identical carrier bytes yield identical cellKey on any device (the merge-convergence precondition, C1).
2. `lawBinEdgesPinned`: bin edges are named constants with golden vectors; no derived or float edge.
3. `lawMergeCoverageMonotone`: merging any received map never shrinks the occupied-cell set (cite the Spec/CoverageMonotone.hs lemma shape).
4. `lawReceivedFillsEmptyNeverDisplaces`: a wire-received fitness-unknown gene inserts iff its cell is empty; it never evicts a scored incumbent (what makes law 3 hold with no wire fitness).
5. `lawArgmaxElitePicksMaxFitness`: the stored elite maximizes fitnessQ16 under the pinned total order; ties fully determined (scored beats unknown, then earlier gtMinted, then lower gtGene).
6. `lawContentDedupCollapsesEchoes`: any number of arrivals of one GeneId collapse to one archive entry; echoes cannot multiply coverage (Economy-First graft).
7. `lawGrantHashRecomputedAtInsert`: a Grant whose recomputed FNV-1a over (Q16 weights ++ ordered parents) mismatches gtGene inserts with zero archive effect (Economy-First graft; claim is not content).

Tier-1:
8. `lawArchiveIdempotentReinsert` and `lawMergeCommutative`: reinsert is a no-op and merge is order-independent, giving G-Set CvRDT / SEC (cite LedgerCRDT.hs proof shape).
9. `lawShowcaseArchivable`: v1 descriptors depend only on GCT palette bytes, so a zero-weight Showcase bins identically to its Grant twin (cites `lawShowcaseIsInert`).
10. `lawNeutralStashBounded`: stash size capped; eviction deterministic by fitness then total order (Diversity-First graft).
11. `lawReindexTotalOnStoredPhenotype`: under a descriptor-version bump, every archived gene re-bins from its retained GIF to exactly one cell; migration is total, never orphans (Diversity-First graft).
12. `lawLineageDepthPolicyBound`: import rejects genealogy depth > cap; pure predicate, no wire field.
13. `lawShowcaseGrantDomainsDisjoint`: reserved; the two fitness domains never argmax against each other (dormant until social fitness revives, C14).

---

## 7. BUILD PLAN

Dependency-ordered. UNBLOCKED unless flagged.

1. **`Spec.GeneArchive`**: 3 axes, bin edges, cell function, merge fold, laws 1-8 green under QuickCheck; wire spec/test/Spec.hs + spec.cabal + gate-order.txt; golden vectors for cell indices.
2. **Codegen**: new `spec/src/SixFour/Codegen/` emitter producing `SixFour/Generated/GeneArchiveGolden.swift` (bin edges + cell golden vectors). House pattern, never hand-edit Generated/.
3. **Zig reducers**: mean-L (i64 accumulate over `s4_srgb8_to_oklab_q16`, kernels.zig:1962) and hue-octant (sign/octant integer test, no atan2), oracle-gated in Native tests. `gamutCoverage` already ships (ClusterStatisticsOps.swift:306, live in GIFRenderer.swift:116,135,222).
4. **Swift `fnv1a64`**: hand-written port verified against `Generated/GeneHashGolden.swift:10-12`. Small; unlocks Graft 3. (Also a prerequisite Economy-First correctly identified for any later ledger work.)
5. **GeneStore rework**: parse GCT from stored GIF bytes via the `CarrierWire.swift` scan (no pixel decode); compute 3 descriptors and cell; add `cell`/`fitnessQ16`/`domain` to `OrganDescriptor` (Organ.swift:15-24); replace `addOrgan` replace-by-hash (GeneStore.swift:85-94) with verify, dedup, cell-wise argmax insert plus neutralStash; write `archive.json`. Same PR: `contentsOfDirectory` enumeration of Documents plus the bounded GC with elite-phenotype pinning (C13; the gallery is the first thing that ever lists that directory).
6. **Mint seam (local)**: at burst finish (CaptureSession.swift:792-811), Q16-quantize `lossReduction` (CaptureGene.swift:30) into the archive payload; require nonzero `committed` band as the archivability floor (C8). Independent of export.
7. **Gallery**: add `galleryScene` to `Spec.GridLayout` (contention-free proof) and regen `Generated/GridLayoutContract.swift` (today only capture/decision/curate scenes, :29,:37,:50); build `GeneAtlasView` reusing `PaletteGridView`'s cell vocabulary (PaletteGridView.swift:4-16) but with ABSOLUTE binned placement, holes allowed, never rank/sort; `ContestedCellGridView` shimmer (ContestedCellGridView.swift:4-14) for stash-tied cells; all animated thumbnails ride the single κ clock (C17). Thumbnails via ImageIO from stored bytes; the `s4_gif_decode` path is NOT required here.
8. **Import/export join point.** BLOCKED ON LAUNCH ITEMS: export mint-at-share = L2.3 (splice S4GX into the Documents GIF at share, `mintFor` per recipient; anchor V21CaptureField.swift:377-440 share path); import = L2.5 (Info.plist `CFBundleDocumentTypes` + `onOpenURL`, then `SwapCarrier.extract` into step 5's insert; C10). Steps 1-7 run in parallel with L0-L5 and do not touch these.
9. **v1.1, axis 4 (temporal changed-index fraction, 96 to 288 cells).** BLOCKED ON UNBUILT COMPONENT: the Swift `s4_gif_decode` caller (probe, alloc, decode two-call protocol; kernels.zig:2122, scratch :1983). Worth building regardless (it also unlocks GIF-import corpus collection and decoded thumbnails). Migration by law 11: recompute cellKeys from retained GIFs, rebuild archive offline.
10. **Later, non-gating.** JEPA descriptor axes 5-6: BLOCKED on a deploy-ready encoder (18.9M ViT is Mac-only MLX, no Swift forward, corpus work in flight) and on crossing `reenterQ16` with a golden (C1). Signature-on-wire: BLOCKED on R4/R5/R6 and the PLA (C6, C14); Economy-First's v3 layout is the pre-approved design when it unblocks. Social fitness domain activation: BLOCKED on entitlement restore (C14). Trade ledger on device: BLOCKED on L2.8 (C19).

---

## 8. OPEN DECISIONS FOR THE OWNER

1. **Documents GC policy (the top decision: it bounds the phenotype store AND the reindex guarantee).** Cap by count or bytes, and eviction order for non-elite captures. RECOMMENDED DEFAULT: cap 512 GIFs or 1 GiB, whichever first; pin every archive-referenced phenotype; evict oldest unpinned first. Law 11 only holds for pinned phenotypes, so the cap defines how much of the archive is migration-safe: recommend pinning ALL archived genes' carriers and letting only non-archived captures age out.
2. **neutralStash cap.** Diversity-First proposed 4. RECOMMENDED DEFAULT: 4; it is a UI-legible shimmer count and keeps archive.json small. Revisit after measuring real stash pressure.
3. **Genealogy depth cap at import.** RECOMMENDED DEFAULT: 16 (Minimal-Ship's policy number; `parentCount` u8 already soft-caps width). Policy-only, so changing it later costs nothing.
4. **When to ship axis 4 (96 vs 288 cells).** RECOMMENDED DEFAULT: ship v1 at 96, build the `s4_gif_decode` Swift caller immediately after (it is needed for the corpus pivot anyway), land axis 4 in the next release using law 11's migration. Do not hold v1.
5. **Received Grant whose fitness cannot be recomputed on device (cross-capture expression quality is unproven, SWAP-ECONOMY-CARRIER.md honest-gaps).** Fill-empty-only like a Showcase, or attempt local re-expression scoring? RECOMMENDED DEFAULT: fill-empty-only in v1 (never admit a claimed number, per the economy judge); revisit when the `s4_gene_express` sandwich port (L5.2b) lands and a foreign theta_up can be scored honestly on local probes.
6. **Reserve the fitness-domain enum now or add it at social-fitness revival.** RECOMMENDED DEFAULT: reserve now (one field in archive.json, prevents a migration); keep it dormant.
7. **Elite display preference when a cell eventually holds both domains.** RECOMMENDED DEFAULT: Grant (measured) over Showcase (social), per Diversity-First's own rule.
8. **How to aggregate the 64 per-frame Local Color Tables into one gene-level descriptor (raised by the 2026-07-02 GCT correction).** Options: (a) union all 64 LCTs then compute the 3 axes over the union; (b) compute per-frame then average; (c) use frame 0's LCT as the representative. RECOMMENDED DEFAULT: (a) union, because it is order-independent (helps `lawCellFunctionDeterministic`) and matches how gamutCoverage already reasons over a palette set; the union is bounded (<= 64*256 entries, deduped) and cheap. This must be pinned by golden vectors before any Swift ships.
