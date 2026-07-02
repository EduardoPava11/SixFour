# The swap-economy carrier — one GIF is the whole trade artifact

> Status: LIVING · Created: 2026-07-02 · Owner: SixFour
> Companions: `docs/V3-BUILD-WORKFLOW.md` (the cascade + gene registry),
> `spec/src/SixFour/Spec/SwapCarrier.hs` (the landed wire contract).
> Spec wins on any disagreement.

## 1. The objective, mapped to what exists

"Tight synergy between the MPS-accelerated nets and the Zig code, SIMT; genes
expressed; a GIF89a-plus-metadata file type; gamified with the governance swap
mechanic." Audit of where each clause stands:

| Clause | Status | Where |
|---|---|---|
| Zig ↔ Metal SIMT cascade | **LANDED** (V3 B2.2–B2.4) | `deviceTrainSimtKernel` (deterministic SIMT standard: fixed-order tree reduction, bitwise-reproducible), byte-exact Metal integer twins of the Zig rung ops, fused `[int lift → fp32 θ_up descent → Q16 commit]` in one command buffer |
| Genes categorised | **LANDED** | `Spec.GeneTaxonomy` (Germline/Somatic/Identity/Meme × train-site × size; the 32 KiB fold-in boundary as law) |
| Genes trained per capture | **LANDED** | `CaptureGene.swift` — every burst trains its somatic θ_up at the capture seam; carried as `BurstResult.thetaUp` |
| OWN gene expressed | **LANDED** | `OctantCube.expandProposal` — gene vs floor toggle on the decide surface |
| Governance / swap economy | **LANDED (spec + Swift ports)** | `Spec.Trade` (hybrid grant ledger), `Spec.Lineage` (genealogy DAG), `Spec.Governance` + `GuildScale` (constitutions, councils), `GeneLibrary/` (CloudKit publish/browse/adopt) |
| Look genome in the GIF | **LANDED (spec)** | `Spec.GenomeCarrier` — the `S4GN` Application-Extension block (σ-pair genome, CRC32, golden emitted) |
| **Tradeable-gene file type** | **LANDED THIS ROUND (spec)** | `Spec.SwapCarrier` — the `S4GX` block, below |
| FOREIGN gene expressed | **GAP** | §4 — the receive→express path |
| Codec in the shipped app | **GAP** | §5 — Swift/Zig ports + the export/import seams |

## 2. The file type: GIF89a + S4GX

One file is the animation, the gene's provenance, and (grant profile only) the
working weights. No sidecars, no `.sixfour-genes` directory bundles — the
existing AirDrop directory-bundle path (`AirDropHandler.swift`) is superseded by
this once ported. Every GIF viewer plays the file: decoders skip Application
Extensions by spec, and the app's own Zig parser already does
(`kernels.zig s4_gif_decode`, the `0x21` skip branch).

```
0x21 0xFF                  Application-Extension introducer
0x0B                       block size = 11
"SIXFOUR1" "X10"           identifier (X = eXchange; coexists with S4GN's "G10")
<data sub-blocks>          each: <len 1..255> <len bytes>
0x00                       terminator

body = "S4GX" major minor profile
       nameLen name                     -- GeneTaxonomy registry key ("theta-up", …)
       gene(i32) creator(i32) minted(i32)   -- the Lineage GeneTag
       parentCount parents(4·k)             -- remix genealogy edges
       weightCount(u16) weights(4·m)        -- Int32 Q16; ABSENT on a Showcase
       crc32
```

Sizes are not free-form: a grant of `theta-up` must carry exactly its 21
registry words, `sigma-look` its 384 (`grantWeightCountValid`,
`lawWireSizesFromRegistry`). A whole somatic θ_up grant is ~120 bytes of
extension block — noise next to the GIF frames.

## 3. The governance swap mechanic, as laws

`Spec.Trade` locked the hybrid model: *the showcase GIF is public and abundant;
the working blob moves only through a settled trade.* `Spec.SwapCarrier` makes
that a wire fact, not a policy:

- **Showcase profile** — `encodeSwapBlock` physically serializes zero weight
  bytes (`lawShowcaseIsInert`). A received showcase `expressionSource`s as
  `FloorExact`: viewable, coveted, inert. This is `GeneTaxonomy`'s
  zero-gene == floor claim surfacing at the file level.
- **Grant profile** — `mintGrant` is the only constructor and consults the
  ledger: the creator may always mint their own; anyone else must appear in
  `Trade.holdings`, i.e. a trade **settled** (`lawGrantOnlyFromSettledTrade`).
  `mintFor` is the total game verb: ask for a file, the ledger governs which
  profile you receive — refusal degrades to the showcase, never errors, never
  leaks.
- **Carriage is memehood** — a somatic θ_up minted into a carrier has crossed
  its capture boundary: carried class is `Meme` by definition
  (`lawCarriageIsMemehood`); the registry's class⇒site coherence is untouched.
  A shared wild capture is an *origin* in the lineage DAG (`parents = []`).

The game loop this buys, end to end, every stage already spec'd:

```
capture → somatic θ_up trains (SIMT fused dispatch, ~200 ms)
        → mint SHOWCASE (public: CloudKit feed / AirDrop / anywhere a GIF goes)
        → covet → propose trade (Spec.Trade)
        → accept ⇒ settled ⇒ mintGrant (both parties, hybrid grant)
        → express the foreign gene on YOUR captures (§4)
        → remix ⇒ new GeneTag with parents ⇒ lineage influence
        → prestige (demand) + tenure + grades ⇒ constitution ranks the guild
          (meritocracy / gerontocracy / majority-judgment / monarchy)
```

## 4. The expression path (the remaining synergy gap)

Expressing a *received* grant is the same machinery that expresses your own:

1. `extractSwapBlock` (total: `NoBlock`/`Corrupt`/`VersionMismatch`) →
   `GeneStore.addOrgan` keyed by content hash.
2. Route by registry name: a foreign `theta-up` is bit-compatible with
   `BurstResult.thetaUp` (same 21-word shape, enforced at the wire) → feed
   `OctantCube.expandProposal` / the fused rung dispatch exactly as the somatic
   gene toggle does today.
3. Float re-enters the Zig Q16 floor at the commit seam — the established
   determinism rule; a foreign gene cannot produce non-byte-exact output,
   only a different (still floor-anchored) invention.

So "genes are expressed" needs no new kernel: it is a *source switch* on the
already-landed dispatch. The decide surface's gene toggle grows a third arm:
floor / my gene / adopted gene.

## 5. Ordered port plan

1. **Codegen golden** — `Codegen.SwapCarrier` emitting `SwapCarrierGolden.swift`
   (mirror `Codegen.GenomeCarrier`): canonical payload bytes both profiles +
   corrupt/version negative vectors.
2. **Swift codec** — hand-written `GeneLibrary/SwapCarrier.swift`
   (encode/extract), golden-gated. Note the S4GN Swift port does not exist yet
   either; port both in one round, they share framing.
3. **Export seam** — append the S4GX (+S4GN) blocks after `s4_gif_assemble`
   output at the share path; showcase by default, grant via `mintFor` against
   the local ledger.
4. **Import seam** — share-sheet / AirDrop of a plain `.gif`: probe for S4GX,
   on hit offer adopt (showcase ⇒ browse card + trade proposal; grant ⇒
   `GeneStore` + expression toggle).
5. **Zig twin (optional)** — `s4_swap_extract` if the import probe should live
   on the floor; Swift-only is contract-clean since the block never touches
   pixel bytes.

## 6. Honest gaps

- No proof a foreign θ_up expresses *well* on an unrelated capture — it is
  trained on its own capture's supervision pair. The gene may be a look, or may
  be noise off-distribution; B3's above-floor measurement should be re-run
  cross-capture before the trade UI promises anything.
- Trade/Governance Swift ports are roster math + CloudKit records; no trade UI
  exists.
- `CreatorId`/`GeneId` are Int stand-ins for Game Center identity + content
  hashes; the hash function choice (and its Zig/Swift agreement) is unpinned.
- The S4GN module header still says "test wiring pending" — stale, it is wired
  and green; clean up on next touch.
