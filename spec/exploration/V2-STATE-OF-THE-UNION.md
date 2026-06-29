# V2 STATE OF THE UNION

The canonical organized map of the V2 (opponent-literal latent) exploration. Source of truth for
what each file IS, what V1 element it relates to or supersedes, what is locked, and what is still open.
This document supersedes scattered per-cluster reading; every status below was MEASURED by runghc or
by running the Python self-check, not taken from a header claim.

## 1. V2 thesis (owner's terms)

V2 is a SEPARATE model from the production V1 OKLab H-JEPA. It drops OKLab entirely and works on raw
GIF89a 8-bit R,G,B. The latent is opponent-literal and integer: [L = R+G+B, a = R-G, b = R+G-2B, x, y, t],
stored as bytes, with sRGB appearing ONLY at the encode/decode boundary and byte-exactness never lost in
the interior. Colour algebra is Eisenstein Z[w] (the hexagonal A2 lattice), NOT Gaussian Z[i]; the
Eisenstein lens is DERIVED for analysis, never stored. Energy/entropy weighting of the six axes is the
dynamic that breaks the flat-L1 symmetry and gives the metric its shape. The reversible integer Haar
lift (one rung = two octree levels) is colour-ring-agnostic and ports byte-for-byte from V1. On top of
that spine, an SKI reading (S = invent/expand contraction, K = pool/contract weakening, I = reversible
held bijection) plus a PonderNet read-depth search drives the residual word from 16^3 up to 256^3. The
hard byte-exactness question (the /3 guard) is resolved structurally: representable colours are exactly
the index-3 sublattice Lambda = {l == a+b (mod 3)}, which is the ramified prime (1-w) of Z[w].

## 2. Status table of every V2 file

Measured legend: "green N/N" = explicit law-count PASS line printed; "green demo" = runs clean,
byte-exact round-trip printed, no law-count assertion; "prose-only" = no PASS/FAIL count, demo/derivation
text; "doc" = markdown, not executable; "tool" = Python self-check.
DRIFT column flags any file whose bare invocation does NOT match its green header (needs an import flag
or a specific working directory to reproduce the PASS).

### Cluster LATENT
| Path | Measured | Purpose | Tag | DRIFT |
|---|---|---|---|---|
| spec/exploration/V2Latent.hs | green demo (round-trip Just (200,50,10)) | Locks the opponent-literal 6-axis latent record; decode byte-exact on index-6 lattice | locked-decision | none |
| spec/exploration/V2LatentMaintenance.hs | green demo | Maintenance invariant: sRGB only in encode/decodeBoundary, every interior op Latent->Latent | locked-decision | none |
| spec/exploration/V2EncodeDecodeBoundary.hs | green demo | Three-layer arch: sRGB boundary / opponent store / Eisenstein lens DERIVED | locked-decision | none |
| spec/exploration/V2DualityTest.hs | green 8/8 | xyt<->Lab duality + phi6 survival under Gaussian->Eisenstein (SURVIVES-WEAKENED) | green-law | none |
| spec/exploration/V2-LATENT-BASIS-REVIEW.md | doc | Verdict: store opponent det-6, not green-blue; ANT lives in the lattice not coords | locked-decision (1 open fork) | n/a |
| spec/exploration/V2-GIF89A-LATENT-NOTES.md | doc | Synthesis (R,G,B,x,y,t)==GIF89a; covers V2Gif89aAxes/V2IndexLzw/V2SkiLevels | prose-only | n/a |

### Cluster COLOUR / ANT
| Path | Measured | Purpose | Tag | DRIFT |
|---|---|---|---|---|
| spec/exploration/V2RgbEisenstein.hs | green 8/8 | Eisenstein Z[w] hex chroma + colour-agnostic Haar/octant lift on raw RGB | green-law | none |
| spec/exploration/V2EisensteinPrime.hs | green 6/6 | /3 guard IS the ramification of prime 3: ideal (1-w), Z[w]/(1-w)=F3 | green-law | lawIndexThreeIsIdeal1mW sample-verified, not closed |
| spec/exploration/V2TrainingLattice.hs | green 7/7 | A2-norm training loss + index-3-Lambda byte-exact target snap | green-law | none |
| spec/exploration/V2A2ClosestPoint.hs | green 5/5 | Proves closestLambda is the genuine nearest Lambda point, beats luma-only snap | green-law | YES: bare runghc fails ("Could not find module V2TrainingLattice"); needs -iexploration |
| spec/exploration/V2PaletteScaling.hs | green 7/7 | 16x16=256 foundation; S/K/I word the PonderNet searches 16^3->256^3 | green-law | none |

### Cluster ENERGY
| Path | Measured | Purpose | Tag | DRIFT |
|---|---|---|---|---|
| spec/exploration/V2EnergyWeave.hs | prose-only | Entropy-weighting the axes breaks flat-L1 symmetry and forces the phi6 pairing | prose-only | none (no PASS claimed) |
| spec/exploration/V2EnergyArchitecture.hs | prose-only | Derives CNN channel widths / depth / halt-gate from per-axis energy | prose-only | none (no PASS claimed) |
| spec/exploration/V2CrossFrameBEnergy.hs | green 4/4 | t-detail band IS the opponent-b energy seam; reversible, descends well-defined | green-law | none |
| spec/exploration/V2UncertaintyBudget.hs | prose-only | Haar 1-coarse+7-residual budget; HONESTLY retracts the Heisenberg-bound overclaim | prose-only | none (no PASS claimed) |
| spec/exploration/V2-HARDENED-ABSTRACTION.md | doc | The three-way == is a chain of three relations of different strengths, not one iso | open-question (K2 green, retractions) | n/a |

### Cluster SKI / PONDER
| Path | Measured | Purpose | Tag | DRIFT |
|---|---|---|---|---|
| spec/exploration/V2SkiLevels.hs | green 7/7 | One rung = two abstraction levels as a B-stack of SKI roles | green-law | none |
| spec/exploration/V2SkiHomomorphism.hs | green 6/6 | Closes the open S-homomorphism: native GIF invention == h applied to S-term | green-law | YES: needs -i. (imports V2SkiNativeGif) |
| spec/exploration/V2SkiResidualOrder.hs | green 7/7 | Reversible residual WORD; order+depth give different 256^3; reversibility = ANT unit | green-law | YES: needs -i. (imports V2TrainingLattice) |
| spec/exploration/V2SkiNativeGif.hs | green 6/6 | Seats S/K/I on native sRGB8 GIF frames; lawSrgb8NativeNoLab drops Lab | green-law | YES: needs -i. (imports GifSki) |
| spec/exploration/V2SkiTwoLevelEntropy.hs | green 7/7 | Level1 maximizes entropy (S), Level2 maximizes K; S barred on floor; halt-mass tracks contraction | green-law | none |
| spec/exploration/V2ProjectionScope.hs | green 6/6 | Opponent projections as SKI scope; mean/median/mode = L2/L1/L0 facets | green-law | none |
| spec/exploration/V2Hylo.hs | green 3/3 | Pyramid spine as deforested hylomorphism; IDENTICAL for V1 and V2 | green-law | none |
| spec/exploration/V2-SKI-EXPAND-CONTRACT.md | doc | Steelmans + grades the substructural SKI reading; lawRefineFactorsThroughOctantLift = Tier-0 candidate | open-question | n/a |
| spec/exploration/V2-SKI-PONDER-DIGEST.md | doc | Master index of the ski/eisenstein effort; resolves /3 via index-3 Lambda | open-question | n/a |

### Cluster GIF / MODEL
| Path | Measured | Purpose | Tag | DRIFT |
|---|---|---|---|---|
| spec/exploration/V2Gif89aAxes.hs | green 6/6 | GIF89a codec axes = V2 latent: render = palette . index = B | green-law (S/K naming suggestive) | none |
| spec/exploration/V2IndexLzw.hs | green 5/5 | LZW index head: lossless dict coder, code count = entropy proxy | green-law (S/contraction suggestive) | none |
| spec/exploration/V2ModelWiring.hs | green 7/7 | CNN U-Net over the 6-channel latent, channels DERIVED from per-stage energy | green-law (NOT wired) | YES: fails from spec/ ("Could not find module V2EnergyArchitecture"); run from spec/exploration |
| spec/exploration/V2-FITS-THE-MODEL.md | doc | Verdict: prod spec already saturates the typeclasses; only Eisenstein ideal theory is irreducible | open-question (verdict) | n/a |

### Cluster PLANS
| Path | Measured | Purpose | Tag | DRIFT |
|---|---|---|---|---|
| spec/exploration/V2-PLAN.md | doc | Top-level pivot + 6-step build plan; V2 is a SEPARATE model | locked-decision | n/a |
| spec/exploration/V2-RGB-FIRST-CLASS-PLAN.md | doc | Gated dependency-ordered promotion roadmap M1-M5; Section 1 is a hard gate-wall | locked-decision | n/a |
| spec/exploration/V2-HASKELL-TOOLS-MAP.md | doc | Every V2 concept -> dependency-free Haskell typeclass/oracle lesson | tool (reference) | n/a |
| spec/exploration/V2-LATENT-LAB-ENERGY-SKI-DESIGN.md | doc | Consolidates V2LatentMaintenance/V2CrossFrameBEnergy/V2SkiTwoLevelEntropy | prose-only (unwired) | n/a |

### Cluster TRAINER (Python, none wired into a training loop)
| Path | Measured | Purpose | Tag | DRIFT |
|---|---|---|---|---|
| trainer/mlx/eisenstein.py | green 7/7 (tool) | The real substrate: lattice loss + Lambda byte-exact snapper, ported from spec | green-law (library-only) | none |
| trainer/mlx/frame_energy.py | green 6/6 (tool) | Per-frame residual energy vs palette-usage entropy, sRGB-native | tool (diagnostic) | none |
| trainer/mlx/frame_stats.py | green 6/6 (tool) | Abstracted facet diagnostic: projection x statistic x time | tool (diagnostic) | none |

### V1 SURFACE (reference, not V2 files; the crosswalk ledger)
| Path | Measured | Purpose | Tag |
|---|---|---|---|
| spec/src/SixFour/Spec/Map.hs | index module (no laws) | Canonical ship-status / retirement record for every Spec.* module | locked-decision (ledger) |
| CLAUDE.md | doc | Project contract: three-tier zero-dep rule, train/deploy spine, amendment stack | locked-decision (contract) |

## 3. Dependency sketch

Foundation layer (no V2 siblings imported):
- V2Latent.hs is the root latent type. V2LatentMaintenance.hs and V2EncodeDecodeBoundary.hs extend its lock.
- V2RgbEisenstein.hs is the foundational colour file (Eisenstein ring + ported Haar lift, base-only).
- V2Hylo.hs and GifSki.hs are file-level ports from OneSix, colour-agnostic.

Colour/ANT chain (each builds left to right):
- V2RgbEisenstein.hs -> V2EisensteinPrime.hs (prime-3 ramification justifies the /3 guard).
- V2RgbEisenstein.hs -> V2TrainingLattice.hs (A2-norm loss + closestLambda snap).
- V2TrainingLattice.hs -> V2A2ClosestPoint.hs (imports Eisen/enorm/metricCost; closest-point proof). NEEDS -iexploration.
- V2-SKI-PONDER-DIGEST.md supplies the index-3 Lambda theorem that TrainingLattice and EisensteinPrime consume.

SKI/Ponder chain:
- GifSki -> V2SkiNativeGif.hs (native S/K/I on frames). NEEDS -i.
- V2SkiNativeGif.hs -> V2SkiHomomorphism.hs (closes the S-homomorphism). NEEDS -i.
- V2TrainingLattice.hs -> V2SkiResidualOrder.hs (reversible word over Lambda). NEEDS -i.
- V2SkiLevels.hs feeds V2SkiTwoLevelEntropy.hs (twiceness, level1/level2 split).
- V2-SKI-EXPAND-CONTRACT.md is the conceptual root; its open questions are answered by Homomorphism / NativeGif / Levels.

Energy -> Model:
- V2EnergyWeave.hs supplies the asymmetric weights that break B_6 symmetry (fixes the K3/d6 gap in V2-HARDENED-ABSTRACTION.md).
- V2EnergyArchitecture.hs turns that energy into channel widths / depth / gate (channelsFromEnergy, depthFromEnergy, gate).
- V2ModelWiring.hs imports BOTH V2Latent (latentChannelCount=6) AND V2EnergyArchitecture (channelsFromEnergy). NEEDS run from spec/exploration.
- V2CrossFrameBEnergy.hs builds on V2RgbEisenstein (sLift/sUnlift) + the opponent b axis.

Trainer:
- trainer/mlx/eisenstein.py mirrors V2TrainingLattice.hs + V2A2ClosestPoint.hs + V2EisensteinPrime.hs.
- trainer/mlx/frame_energy.py imports eisenstein.enorm. frame_stats.py shares the chroma coords but does not import.

Plans sit above everything:
- V2-PLAN.md sets direction -> V2-RGB-FIRST-CLASS-PLAN.md gates it (M1 RGBProjection -> M2 Eisenstein -> M3 EisensteinIdeal,
  green cross-tier, BEFORE any trainer work) -> V2-HASKELL-TOOLS-MAP.md supplies the dependency-free typeclass shapes.

## 4. Settled decisions (locked, do not relitigate)

1. OPPONENT-LITERAL LATENT. The stored latent is [L = R+G+B, a = R-G, b = R+G-2B, x, y, t], integer bytes.
   These six fields ARE the six CNN input channels. (V2Latent.hs, V2-LATENT-BASIS-REVIEW.md, V2-PLAN.md.)
2. BOUNDARY DISCIPLINE. sRGB 8-bit appears ONLY in encodeBoundary / decodeBoundary. Every interior op is
   Latent->Latent or Latent->Int. Byte-exactness is never lost; the boundary is crossed exactly twice per session.
   (V2LatentMaintenance.hs, V2EncodeDecodeBoundary.hs, V2-LATENT-LAB-ENERGY-SKI-DESIGN.md.)
3. EISENSTEIN IS A DERIVED LENS, NOT A STORE. Z[w] (hex A2) is computed for ANT analysis from the opponent
   store and never persisted. Position B (Eisenstein (R-B,G-B) as storage) is DISMISSED: its only exclusive
   asset, the integer hue-rotation operator, has no wired caller. (V2EncodeDecodeBoundary.hs, V2-LATENT-BASIS-REVIEW.md.)
4. EISENSTEIN, NOT GAUSSIAN, FOR V2 COLOUR ALGEBRA. Z[w] (order-6, 60-degree, hex A2) replaces Gaussian
   Z[i] (order-4, 90-degree, square) as the V2 chroma ring. (V2RgbEisenstein.hs, V2-PLAN.md.)
5. THE /3 GUARD IS STRUCTURAL. Representable colours = exactly the index-3 sublattice Lambda = {l == a+b (mod 3)},
   which is the ramified prime ideal (1-w) of Z[w]; decode is invert-or-refuse on Lambda. (V2EisensteinPrime.hs,
   V2TrainingLattice.hs, V2-SKI-PONDER-DIGEST.md.)
6. B-SIGN. Stored latB = R+G-2B (the exact negation of the owner's 2B-(R+G)). KEEP the stored sign: decode
   congruences are sign-sensitive and flipping breaks the mod-3 guard. Expose the owner axis as a derived,
   never-stored energy view ownerBView = negate latB; safe because energy is |.|-based.
   (V2LatentMaintenance.hs, V2-LATENT-LAB-ENERGY-SKI-DESIGN.md.)
7. WELL-FOUNDED, NOT BANACH, STEADY STATE. The contraction is well-founded recursion (a strictly-decreasing
   band-length measure bottoming at the coarse DC), explicitly NOT a metric contraction-mapping; lawNoForcedContractionMapping
   ships equal-length witnesses (ratio 1) as the anti-jargon guard. (V2SkiTwoLevelEntropy.hs.)
8. REVERSIBILITY (NOT CONFLUENCE) IS THE BYTE-EXACT CRITERION. Lossless == reversible <=> norm-1 unit of Z[w];
   the /3 threatens reversibility, not confluence; S is barred on the reversible floor (BCI excludes contraction).
   (V2SkiResidualOrder.hs, V2-SKI-EXPAND-CONTRACT.md.)
9. ONE RUNG = TWO OCTREE LEVELS. levelsPerStep == 2; the x4 band; 16:64 :: 64:256. The reversible integer
   Haar lift (RGBTLift / liftOct) and the ana/cata/hylo spine port byte-for-byte; the spine is IDENTICAL for
   V1 and V2 (never sees the colour ring). (V2Hylo.hs, V2SkiLevels.hs, V2-PLAN.md.)
10. LAB / OKLAB DROPPED ON THE ENCODE PATH. V2 is raw GIF89a sRGB8; lawSrgb8NativeNoLab. OKLab survives at
    most as display-only decode. (V2SkiNativeGif.hs, V2-RGB-FIRST-CLASS-PLAN.md, CLAUDE.md.)
11. GATE-WALL SEQUENCING. No trainer work until a module is proven transferable through gate.sh (cabal test +
    Map/compartment/cabal wiring + hermetic codegen + cross-tier golden). Order: M1 RGBProjection -> M2 Eisenstein
    -> M3 EisensteinIdeal, green cross-tier, FIRST. Eisenstein Z[w] is added ALONGSIDE GaussianChroma Z[i],
    not by deletion. (V2-RGB-FIRST-CLASS-PLAN.md.)
12. PHI6 DEMOTED. Under Eisenstein, phi6 keeps only its label-level Z-module set-involution and LOSES the
    search-plane lattice iso (Z[i] D4 order-8 is not isometric to A2 D6 order-12); it is bookkeeping, not a
    render automorphism. (V2DualityTest.hs, V2-SKI-EXPAND-CONTRACT.md, V2-PLAN.md.)

## 5. Consolidated open questions (deduped, tagged with raising file)

A. STORAGE LITERAL vs CONTAINER. Opponent det-6 storage (5/6 off-lattice refusal) vs RGB-direct det-1 container
   (zero refusal, opponent as a surfaced view). The single remaining latent fork.
   (V2-LATENT-BASIS-REVIEW.md Q1/Q2; V2-RGB-FIRST-CLASS-PLAN.md Q1 blend space.)
B. WHICH /3 SUBSTRATE SHIPS. Path4 lattice (Lambda) vs Path3 RGB-discipline vs carry-3 vs runtime guard.
   (V2-SKI-PONDER-DIGEST.md; V2-PLAN.md "the REAL V2 risk".)
C. GAUSSIAN C4 vs EISENSTEIN C6 as the live hue inductive bias. Does C6 survive XYTLabDuality/phi6? Promoting
   one detent ring from float-guidance to bit-exact may break the DetentNudge determinism floor; the two rings
   coexisting indefinitely vs a full rewire of the 7 Z[i] consumers. (V2-FITS-THE-MODEL.md; V2-RGB-FIRST-CLASS-PLAN.md Q2.)
D. K3 / d6 COMMENSURABILITY. Flat L1 leaves the full B_6 isometry group so phi6 is not load-bearing and the
   == is FALSE as distance-equality (squared norms 3,2,6 vs position 1). Energy-weighting is the proposed fix but
   is still a demo, not a green lawWeaveIsMetricSymmetry with asymmetric weights.
   (V2-HARDENED-ABSTRACTION.md K3; V2EnergyWeave.hs.)
E. SKI POWER. The two notes DISAGREE: V2-SKI-EXPAND-CONTRACT steelmans SKI as Tier-0-worthy via the still-unwritten
   lawRefineFactorsThroughOctantLift (the decisive next step); the DIGEST demotes the Path-2 SKI framing to decorative
   and keeps only reductionLength as a genuinely new quantity. Is reductionLength prior separable from --w-detail
   (the headline lives or dies here)? (V2-SKI-EXPAND-CONTRACT.md; V2-SKI-PONDER-DIGEST.md.)
F. CANONICAL K and S REFERENTS. K = scalarCollapseLossy (true weakening) vs octantDistill (K-with-receipt);
   S = liftKeyed/expandUp (coarse used twice) NOT octantLift; surface an S_dup vs S_inv split?
   (V2-SKI-EXPAND-CONTRACT.md; V2-GIF89A-LATENT-NOTES.md Q3/Q4.)
G. NUDGE RESIDUAL CARRIER (M5 blocker, the HARD CORRECTION). applyWord from V2SkiResidualOrder does NOT typecheck
   against [[Detail]] (generators are defined on Frame=[RGB], not on the 7-tuple Detail). Pick ONE carrier
   ([[Detail]] or LatentTail), define the generator action on it, re-prove laws, and exhibit a genuine
   64^3+residuals->256^3 UP form. (V2-RGB-FIRST-CLASS-PLAN.md Section 3.3 + Q5.)
H. K1 GIF ROUND-TRIP UNWRITTEN. lawGifTripleReconstructsRGBxyt does not exist; decodeGif . assembleGifRGB8 == id
   is never round-trip-tested. (V2-HARDENED-ABSTRACTION.md.)
I. LUMA POLARITY AND WEIGHT. Keep L = R+G+B unweighted (any perceptual weight breaks integer orthogonality);
   projL is ~39.8 degrees off Rec.709, an accepted give-up unless weighted luma is taken (which breaks the
   ring-clean story). Confirm sign polarity (+b yellowward, +a redward). (V2-LATENT-BASIS-REVIEW.md Q5;
   V2-RGB-FIRST-CLASS-PLAN.md Q4; V2-PLAN.md.)
J. CHROMA-COORDINATE CONVENTION SPLIT (trainer). Opponent (a=R-G, b=R+G-2B) vs Eisenstein (Cr=R-B, Cg=G-B)
   both listed as first-class with no decision on which the model latent uses. (frame_stats.py vs eisenstein.py/frame_energy.py.)
K. NONE OF THE V2 SUBSTRATE IS WIRED. lattice_loss / closest_lambda / facet_tensor are library/plot only; no
   trainer imports them. (eisenstein.py, frame_energy.py, frame_stats.py; V2ModelWiring.hs header "NOT WIRED".)
L. ONE-WAY CONDITIONING DIRECTION. Step 4 colour~>position vs position~>colour is an open design choice
   (phi6 bidirectional is dropped). (V2-PLAN.md; V2-FITS-THE-MODEL.md.)
M. PONDER TIE IS ANALOGY. "More K ~ higher lambda" is a parallel witness with matching numbers, not a typed map
   from K-weakened pairs to a per-step halt rate. (V2SkiTwoLevelEntropy.hs; V2-LATENT-LAB-ENERGY-SKI-DESIGN.md.)
N. SAMPLE-VERIFIED, NOT CLOSED. (1-w)|z <=> a+b == 0 (mod 3) is verified over a finite box, flagged honestly,
   carry verbatim do not upgrade to a law. (V2EisensteinPrime.hs lawIndexThreeIsIdeal1mW; V2-FITS-THE-MODEL.md.)
O. ZIG FLOOR KERNEL MISSING. liftOct has NO s4_octant_lift Zig kernel; named the single highest-value floor
   kernel to add; blocks the V2/I-JEPA model compartment. (Spec/Map.hs.)

## 6. Reading order for a newcomer

1. spec/exploration/V2-PLAN.md  - the pivot decision and the 6-step plan; why V2 exists and what it is.
2. spec/exploration/V2Latent.hs  - the locked latent type; the six fields = the six channels, byte-exact decode.
3. spec/exploration/V2-LATENT-BASIS-REVIEW.md  - why opponent storage and not Eisenstein-on-disk; det-6 verdict.
4. spec/exploration/V2RgbEisenstein.hs  - the two ported lenses: colour-agnostic Haar lift + Eisenstein Z[w] chroma.
5. spec/exploration/V2-HARDENED-ABSTRACTION.md  - the three-way == is a chain of three relations of different
   strengths; where the green keystones (K2) are and where the gaps (K1, K3) are.
6. spec/exploration/V2-RGB-FIRST-CLASS-PLAN.md  - the gated promotion roadmap M1-M5; the hard gate-wall before trainer work.
7. spec/exploration/V2-SKI-EXPAND-CONTRACT.md  - the SKI substructural reading and the one Tier-0 promotion candidate;
   read alongside the note it corrects, V2-SKI-PONDER-DIGEST.md, to see the live disagreement.
