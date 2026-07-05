# YIN-YANG = ZIG ↔ METAL/MPS? — an identification, tested against the code

> Status: EXPLORATION · Created: 2026-07-05 · Owner: SixFour
> Question (Daniel): is the yin-yang split (Spec.YinYangCNN) the SAME thing as the
> Zig-integer-floor ↔ Metal/MPS-float split? Yin = Zig (frozen, exact, K/I carrier),
> Yang = Metal/MPS (float, learning, S/section). Is that EXACT, APPROXIMATE, or does it BREAK?
> Every claim below is `file:line`-anchored. Spec wins on disagreement.

## Verdict

**APPROXIMATE — true in one direction, false in the other, with a clean structural
correction.** The yin-yang axis in this project is a *computational-role* axis, not a
*substrate* axis. Yin = the frozen-exact K/I combinators (pool + reversible lift, zero
parameters, byte-exact); Yang = the learned S section (all the parameters, float gradient
descent). That role split is real and it is enforced. But it runs *through* the substrates,
not *between* them:

- **`yin = Zig` HOLDS as containment, not as equality.** Nothing in the Zig floor has a
  parameter or a gradient — `Native/src/` is 100% K and I: pooling (`s4_pool_sums_bgra8`,
  `palette16.zig`), the reversible lift/unlift pair (`s4_octant_lift`/`_unlift`,
  `kernels.zig:857/887`), the halting *floor* not a learned halt (`kinematic.zig`
  `s4_certified_order`). So **Zig ⊆ yin** is exact. But **yin ⊋ Zig**: much of the shipped
  *Metal* is also pure frozen-exact yin (see the muddy cases). So "yin = Zig" understates
  yin: Zig is a strict subset of the frozen-exact side.
- **`yang = Metal/MPS` BREAKS as stated.** A large fraction of shipped Metal is exact-integer
  *yin twins* of Zig — byte-identical, parity-gated, zero parameters
  (`PaletteLadder.metal` `p16PoolSumsBGRA`, `DeviceTrainShaders.metal` `octantLiftKernel`).
  Metal/MPS is a MIXED substrate: it hosts both the yin integer twins AND the yang float
  descent. The claim is only true if restricted to the *float sublayer* of Metal/MPS
  (the descent kernels + MPSGraph).

The honest one-liner: **the yin-yang boundary is the FROZEN-EXACT (K/I, integer) vs
LEARNED (S, float) boundary; the Zig↔Metal boundary is a CPU-authority vs GPU-throughput
deployment boundary. They are correlated (Zig is all yin) but not identical (Metal is both).**
The two boundaries are made to *coincide operationally* by the parity gates: a Metal kernel
that is byte-exact to its Zig oracle is provably yin; a Metal kernel that is only
order-deterministic float, gated at post-commit bytes, is yang. **The parity gate is the
yin-yang boundary made testable.**

## The mapping table

| yin-yang concept | Zig artifact | Metal/MPS artifact | Does the identification hold? |
|---|---|---|---|
| **YIN — K (pool/collapse), zero params** (`YinYangCNN` "K is a theorem"; `CombinatorExactSequence` `kSurj`) | `s4_pool_sums_bgra8`, `s4_quantize_frame` (`kernels.zig:343`), block SUMs `palette16.zig` | `p16PoolSumsBGRA` (`PaletteLadder.metal:35`), `v21AccumulateHistKernel` — EXACT integer, byte-identical to Zig | **HOLDS in role, MUDDY in substrate:** K lives on BOTH substrates, parity-gated |
| **YIN — I (reversible lift), work=0** (`CombinatorExactSequence` `iSplit`, `lawISplitsExactly`) | `s4_octant_lift`/`_unlift` (`kernels.zig:857/887`) — the AUTHORITY | `lift_oct`/`unlift_oct`, `octantLiftKernel` (`DeviceTrainShaders.metal:71,99,178`) — accelerator TWINS | **HOLDS in role, MUDDY in substrate:** I lives on BOTH, byte-exact, parity-gated (`RungDispatchTests:37`) |
| **YANG — S (section/gene), all params** (`YinYangCNN` `stagedDetailCounts`; `MixSKI` "the gene lives on S") | *none* — Zig never mints a parameter | `deviceTrainSimtKernel` (`DeviceTrainShaders.metal:317`), `BandHeadTrainer.swift`, `DeviceTrainer.swift` (MPSGraph) — fp32 GD | **HOLDS cleanly:** all learning is float, off-Zig |
| **The yang→yin re-entry** (`ByteCarrier.reenterQ16`; CLAUDE.md "float re-enters the Q16 floor") | the destination lattice Q16 = `Int32<<16` (`kernels.zig:63`); `s4_cube_expand_rung` consumes committed Q16 | `committedOut[j] = int(rint(raw*kQ16))` (`DeviceTrainShaders.metal:243,336+`); `DeviceTrainer.quantizeQ16` (`DeviceTrainer.swift:72`) | **This IS the boundary itself** — a float→integer retraction performed in Metal, then handed to pure-integer Zig-twin ops |
| **Halting prior = FLOOR, not learned** (`YinYangCNN` "certified order → halting FLOOR"; `KinematicHaltPrior`) | `s4_certified_order` (`kinematic.zig`) — exact integers, refuses on short windows | (consumed by yang as a prior, not trained) | **Yin:** a gate that decides what yang is allowed to do; frozen |

## Where it holds cleanly

**The K carrier = `s4_octant_lift` is exactly yin.** `CombinatorExactSequence.hs:19-24`
pins K = the surjection `scalarCollapseLossy` (forget the 7 detail bands) and I = the
splitting `liftOct`/`unliftOct` (exact iso, `lawISplitsExactly`, `unliftOct∘liftOct=id`,
work=0). Both are *canonical* — "K and I are canonical (summation and reversibility leave
zero degrees of freedom)" (`MixSKI.hs:9-15`). The Zig implementations
(`kernels.zig:857-912`) are pure integer with `/2` floor-division, RC-guarded, golden-gated.
Zero parameters, no descent, deterministic across devices. This is yin with no asterisk.
`kinematic.zig`'s certified order is yin too: it is the halting-prior *floor*
(`YinYangCNN` diagram line "certified order → halting-prior FLOOR"), a gate that constrains
yang, not a learned object.

**The S descent = `BandHeadTrainer` / `deviceTrainSimtKernel` is exactly yang.**
`YinYangCNN.hs:3` — "YANG (learning, the S-direction) is ALL the parameters." The band heads
whose widths `{1,2,4}` are theorems (`lawStagedExpansionCountsSumToSeven`) are trained by
`BandHeadTrainer.swift` ("THE YANG HEADS TRAIN ON THE IPHONE... plain-Metal fused gradient
descent", `BandHeadTrainer.swift:3-14`) and the θ_up somatic gene by
`deviceTrainSimtKernel` (fp32 mean-gradient SGD, `DeviceTrainShaders.metal:340-360`).
`MixSKI.hs:3` closes it: "the ONLY choice in the whole pipeline is the mix... Teaching the
network to produce custom 64³ GIFs is, verbatim in the algebra: TRAINING S." All the freedom
is on S; all of S is float; none of it is in Zig. This half of Daniel's hypothesis
(`yang ⊃ the float learners`, `Zig learns nothing`) is airtight.

So at the two poles the identification is exact: **the frozen K/I authority is Zig, and the
learned S lives only in the float layer.** The muddiness is entirely in the middle, on the
Metal substrate.

## Where it's MUDDY: substrate and role disagree

Every case below is a place where the *substrate* (Zig vs Metal) and the *yin/yang role*
(frozen-K/I vs learned-S) point in different directions.

1. **Yin computed on the yang substrate — the integer Metal twins (the biggest muddy set).**
   `PaletteLadder.metal` `p16PoolSumsBGRA` (`:35`) is a Metal *GPU* kernel — the "yang
   substrate" by Daniel's mapping — but it does pure **integer pooling (K)** and is
   "BYTE-IDENTICAL to the Zig kernel by construction" (`PaletteLadder.metal:6-12`). Its own
   header disclaims authority: "This kernel is throughput plumbing, not authority: the Zig
   kernel is the deterministic floor, and any Metal/Zig mismatch is a bug in THIS file"
   (`:20-21`). Same story for `DeviceTrainShaders.metal`'s `lift_oct`/`unlift_oct` twins:
   "line-for-line ports of the spec's integer math... Zig stays the CPU source of truth;
   these are its accelerator twins" (`DeviceTrainShaders.metal:8-14`). **These kernels are
   YIN (frozen, exact, zero-parameter K/I) running on the Metal substrate.** The substrate
   says "yang," the role says "yin," and the role wins — proven by the parity gates
   (`ColorHeadTests.swift:67` `metalParityAgainstZigFloor`;
   `RungDispatchTests.swift:37` `metalLiftIsByteExactToZigOracle`).

2. **The one kernel that is a yin/yang/yin SANDWICH.** `deviceTrainSimtKernel`
   (`DeviceTrainShaders.metal:317-360+`) is not purely yang. It is three stages in one Metal
   dispatch: **(I)** `lift_oct` manufactures the supervision pairs by the *exact* reversible
   lift (`:344`, "strided INT LIFT (pair manufacture)"); **(S)** fp32 mean-gradient descent
   from the zero floor (`:349-360`, the only float, the only parameters); **(K/re-entry)**
   `committedOut = int(rint(raw*kQ16))` commits back to the integer lattice
   (`:336`, `deviceTrainFusedKernel:243`). So a single "yang" Metal kernel *contains* yin at
   both ends: the exact lift that generates yang's own targets, and the exact re-entry that
   lands its output. Yang here is a thin float filling between two integer slices of bread
   (the "cascade sandwich," `kernels.zig:924` header, `CurateBuilder.swift:37-41`: "only
   integers enter the dispatch," the θ float layer committed OUTSIDE the pure-integer
   `s4_cube_expand_rung`).

3. **Zig that participates in the learning loop (but does not learn).** The DEVICE-MODEL-MAP
   ledger tags `s4_cube_expand_rung` as "I / **S-SITE** if details from θ_up"
   (`DEVICE-MODEL-MAP.md:321`). The kernel itself is pure-integer yin (I), but it is the
   *consumer* of the yang gene: when `details != null` it replays a learned θ_up's
   Q16-committed bands. So a Zig kernel is on the *inference side of a learned object*. It
   never sees a float or a gradient — the float layer "stays OUTSIDE this operator"
   (`kernels.zig` `s4_cube_expand_rung` header) — but it is where yang's output becomes
   visible bytes. Zig is yin, but it is the yin that yang commits *into*.

4. **The re-entry `reenterQ16` is neither substrate but the seam between them.** `ByteCarrier`
   makes the float→device crossing a single typed door: "there is exactly ONE float→device
   crossing, `reenterQ16`" (`ByteCarrier.hs:20-22`), `toByte someLatent` does not typecheck
   (`:22-26`). On device this door is `int(rint(raw*kQ16))` inside Metal
   (`DeviceTrainShaders.metal:336`) and `quantizeQ16` in Swift (`DeviceTrainer.swift:72`).
   It is a Metal/Swift operation (yang substrate) that performs a yin act (collapse a float
   onto the exact integer lattice). It belongs to *neither* Zig nor "the float layer"
   cleanly — it is the membrane. `AboveFloorMargin.hs` measures whether yang cleared the
   membrane: `commit = toByte . reenterQ16 . mkLatent` (`:76`), and the margin law asks
   whether the committed byte moved OFF the deterministic floor (`Map.hs:781`).

Summary of the disagreements: **Zig is always yin (0 exceptions). Metal is yin OR yang
depending on the kernel; the parity gate is the discriminator. The training kernel is
internally both. The re-entry is the seam.**

## The I (reversible floor) third element — where does it live?

The yin/yang binary hides a triad: S, K, **I**. `CombinatorExactSequence.hs` is explicit that
there are exactly three canonical maps of the exact sequence `0→detail→fine→coarse→0`, and I
(the splitting, `unliftOct∘liftOct = id`, work=0, `:14-18`) is a distinct object from K (the
lossy surjection) and S (the learned section).

**I lives on BOTH substrates, byte-exactly, by parity construction — and that is the whole
point of it.** The authority is Zig `s4_octant_lift`/`_unlift` (`kernels.zig:857/887`); the
accelerator twin is Metal `lift_oct`/`unlift_oct` (`DeviceTrainShaders.metal:71,99`); both are
gated equal (`RungDispatchTests.swift:37`). In the yin/yang framing I gets folded into "yin"
(it is frozen and exact), but structurally it is the **shared reversible substrate that both
yin and yang stand on**, for a concrete reason: I is what *manufactures yang's supervision*.
`deviceTrainSimtKernel` runs `lift_oct` FIRST (`:344`) to make the exact pool→detail pairs the
descent then fits — "supervision manufactured by the exact lift on device, no corpus crosses
to the phone" (`DEVICE-MODEL-MAP.md:132-133`). So I is not merely yin-among-K; it is the
bridge the yang leans on: the free, exact, reversible lift that turns raw bins into
`(coarse, detail)` so the section S has something to learn against.

There is a *second* I-like object: `reenterQ16`, described in `RingReduction.hs` as an
idempotent retraction (`DEVICE-MODEL-MAP.md:294`, "`reenterQ16` idempotent retraction").
The lift-I is the reversible bridge *before* learning; the reenterQ16-I is the
projection-I *after* learning (float back onto the lattice). One I opens the door to yang,
the other closes it. Both are frozen, both are exact-by-construction, both straddle Zig and
Metal.

## Closing — the honest statement and what it implies

**The yin-yang split is NOT the Zig↔Metal split; it is the frozen-exact-K/I ↔ learned-float-S
split, which the Zig↔Metal split only partially tracks.** Precisely:

- Zig is a *pure yin substrate*: every Zig kernel is K, I, or a frozen gate; none learns. So
  `yin ⊇ Zig` is exact, and Daniel's intuition "Zig is the floor every learned float must
  re-enter" is exactly right (`ByteCarrier`, the single `reenterQ16` door).
- Metal/MPS is a *mixed substrate*: it carries the yang float descent AND a large set of
  frozen-exact yin twins of Zig (pooling, lift/unlift, hist). So `yang = Metal` is false;
  `yang = the float sublayer of Metal/MPS` is true.
- The two boundaries are forced to *coincide where it matters* by construction: any Metal
  kernel claiming to be yin must pass a byte-for-byte parity gate against its Zig oracle
  (`ColorHeadTests`, `RungDispatchTests`); any Metal kernel that is yang is float,
  order-deterministic only, and gated solely at its post-commit bytes
  (`DEVICE-MODEL-MAP.md:335`, "gate = post-commit bytes").

Architectural implication: **the parity gate between `PaletteLadder.metal` (and the
`DeviceTrainShaders.metal` lift twins) and their Zig floor IS the yin-yang boundary made
testable.** It is the mechanism that lets the yang GPU substrate host yin computation without
the role leaking: a kernel is *certified yin* iff it is byte-exact to Zig, and *admitted as
yang* iff its only non-determinism is float order, quarantined behind the single `reenterQ16`
re-entry. Daniel's identification is best stated as a refinement of his own words: **Zig is
the yin authority; Metal is where yin and yang are made to share one substrate, and the parity
gate is the referee.** The `Spec.SkiLedger` TODO (`DEVICE-MODEL-MAP.md:578`) is exactly the
proposal to pin this referee as a spec contract rather than a per-test convention — which
would turn this document's verdict into a gate.
