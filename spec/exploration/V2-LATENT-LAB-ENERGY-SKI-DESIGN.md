# V2 Latent / Lab-Energy / Two-Level SKI Design

Status: EXPLORATION consolidation. The three modules described here are base-only,
runghc-checkable, NOT wired into any cabal target, Map, or gate. This document records
what they decide, how they extend the locked V2 latent, and the path by which each could
graduate into a real `Spec.*` module.

Modules covered:

- `exploration/V2LatentMaintenance.hs`  (owner ask 1: latent maintained at all times)
- `exploration/V2CrossFrameBEnergy.hs`  (owner ask 2: cross-frame b energy at the t-seam)
- `exploration/V2SkiTwoLevelEntropy.hs` (owner ask 3: one rung = expand then contract)

Verification verdict for all three: clean, runghc passes, non-vacuous, no forced jargon,
byte-exact. No em-dashes anywhere (owner directive).

---

## 1. The latent: [L, a, b, x, y, t] maintained at all times

### What is locked (V2Latent.hs), not re-litigated here

The V2 latent is OPPONENT-LITERAL and LOCKED. The six CNN channels are the record
`Latent { latL, latA, latB, latX, latY, latT }` with:

- `latL = R + G + B`     (luma, the (1,1,1) carrier axis)
- `latA = R - G`         (red-green)
- `latB = R + G - 2B`    (yellow-blue, STORED sign)
- `latX, latY, latT`     (position x, y, frame t)

Decode is invert-or-refuse on the index-6 lattice: a Latent is on-lattice iff
`(latL - latB) mod 3 == 0` AND `(latA + latB) even`. The inverse is
`R = (2L + 3a + b)/6`, `G = (2L - 3a + b)/6`, `B = (L - b)/3`. `snapColour` projects an
off-lattice nudge back on (parity first by adjusting b, then mod-3 by adjusting L). None
of this is re-opened. `V2LatentMaintenance` reuses the record and this arithmetic verbatim.

### What V2LatentMaintenance ADDS: the maintenance invariant

The new content is the rule "the model is created and maintained at all times in latent
space". Concretely:

- sRGB 8-bit (`type SRGB8`) appears in EXACTLY two function signatures: `encodeBoundary`
  (the only ingress) and `decodeBoundary` (the only egress, invert-or-refuse).
- Every interior operation is typed `Latent -> Latent` (a move: `moveColour`, `movePos`,
  `commit = snapColour`) or `Latent -> ... -> Int` (a measurement: `energy`). None of them
  mentions sRGB. The carried value is ALWAYS of type `Latent`, even when a raw nudge has
  pushed it temporarily OFF the index-6 lattice; off-lattice is still in latent space, it
  is simply not yet exportable.
- The boundary is crossed exactly twice per session: encode in, decode out. `commit`
  (snapColour) lands an off-lattice interior value back on-lattice before export, so
  `decodeBoundary` can only ever refuse on gamut, never on lattice.

"Lab in shape, free in RGB" is made precise by the carrier-family witness: a family of
RGBs that all share the SAME opponent chroma shape `(latA, latB) = (2, 4)` but differ only
along the luma carrier `latL`, each reversible to its own distinct unique RGB. The energy
metric reads the opponent AXES (that is the "Lab in shape" half); every on-lattice Latent
inverts to a unique sRGB (that is the "free in RGB" half).

Laws (all PASS):

- `lawBoundaryOnlyRoundTrip`  encode-in then decode-out is identity on the cube; an
  interior pipeline visits a genuinely off-lattice Latent (proving it was never decoded)
  and only decodes after `commit`.
- `lawShapeIsOpponentCarrierIsRgb`  the carrier family shares the opponent shape, differs
  only in the luma carrier, each member reverses to its unique RGB, chroma-only energy is 0
  between members while full energy is positive.
- `lawCarrierByteExactUnderChosenSign`  random RGB (LCG, not just the grid) round-trips
  byte-exactly under the STORED sign, with a tooth showing the owner sign would break the
  mod-3 guard.
- `lawEnergyBSignInvariant`  owner b is the real negation of stored b, yet the energy/dW
  comparison is sign-invariant.
- `lawInteriorStaysInLatent`  a full session keeps a Latent at every interior step,
  measures a real positive scalar, and decode refuses only on gamut.

### The b-sign reconciliation decision (stated, not silently flipped)

The owner writes the yellow-blue / energy axis as `b_owner = 2B - (R+G)`. V2Latent LOCKS
the stored field as `latB = R + G - 2B`, which is the exact NEGATION: `b_owner = -(latB)`.

DECISION (identical across all three modules): KEEP the locked stored sign `latB = R+G-2B`.
The owner's axis is provided as a DERIVED, never-stored ENERGY VIEW `ownerBView lat =
negate (latB lat) = 2B - (R+G)`.

Why this is safe and load-bearing, not cosmetic:

- The decode congruences (`(latL - latB) mod 3 == 0`, `(latA + latB) even`) and the
  rr/gg/bb inverse are SIGN-SENSITIVE. Substituting `b_owner` into the mod-3 guard FAILS on
  real pixels (`lawCarrierByteExactUnderChosenSign` ships that tooth). So the stored sign
  must not be flipped, or byte-exactness breaks.
- Every distance and energy uses `|.|`, and `|b_owner| = |latB|`,
  `|b_owner1 - b_owner2| = |latB1 - latB2|`. So the ENERGY comparison the owner asks for is
  identical under either sign. We get the owner's readout without disturbing the locked
  decode.

This reconciliation is named at every site in all three modules (`lawEnergyBSignInvariant`,
`lawSignReconcile`, and the honesty header of V2SkiTwoLevelEntropy), never silently applied.

---

## 2. Cross-frame b-energy at the t-seam (V2CrossFrameBEnergy.hs)

### The picture

The 64^3 -> 16^3 octree decomposition pairs two t-slices ("two frames beside each other")
inside every 2x2x2 block. The t-axis seam between them is the reversible 1-D Haar lift
(`sLift`/`sUnlift`, copied verbatim from V2RgbEisenstein): coarse = floor-average of the
two slices, detail = their channelwise difference. The detail half is the "t-detail band"
the search descends.

Reading that band through the opponent-b projection recovers the owner's literal form
`[(2B1) - (R1+G1)] : [(2B2) - (R2+G2)]`. Because `ownerB` is LINEAR in (R,G,B)
(`ownerB = 2B - R - G`) and the Haar detail pixel is the channelwise difference
`(r1-r2, g1-g2, b1-b2)`, linearity gives the EXACT identity with no rounding:

```
ownerB(t-detail) == ownerB(f1) - ownerB(f2)
```

That is the whole reason the seam b-difference and the t-detail's b-projection coincide
byte-exactly: the t-detail band IS the cross-frame opponent-b difference.

### Reversibility (energy is a side-channel, never a lossy step)

The pairing stays byte-exact reversible: `seamUnliftCell . seamLiftCell == id` on every
pair including boundary pairs (0 vs 255, and odd-magnitude diffs where `div` floors toward
-inf so the detail is negative). The b-energy is computed ON THE SIDE; the carrier stays
byte-exact reversible to RGB. Energy is a READOUT, not a transform.

### The honest split on magnitudes

The exact identity is on the SIGNED opponent-b. The owner's phrasing uses magnitudes, and
`|b1| - |b2| == b1 - b2` only when b1 and b2 share a sign (same hemisphere). The module
splits the seam law into three parts so the restriction is named, not hidden:

- (a) signed linearity: `ownerB(detail) == ownerB f1 - ownerB f2`  for ALL pixels.
- (b) magnitude readout: `bEnergy(detail) == |ownerB f1 - ownerB f2|`  for ALL pixels.
- (c) owner's energy-difference reading `|ownerB1 - ownerB2| == |bEnergy f1 - bEnergy f2|`
  holds ONLY on same-sign pairs, shipped with a mixed-sign TOOTH where it fails (a blueward
  +200 vs a yellowward -200 pixel give 400 != 0). The mixed-sign tooth carries the real
  teeth.

Laws (all PASS): `lawSignReconcile`, `lawTDetailIsOpponentBSeam`, `lawSeamReversible`,
`lawEnergyDescentWellDefined`.

`lawEnergyDescentWellDefined` is scoped honestly as distance-monotonicity, not a quality
metric: a smaller seam b-energy means the two frames agree more closely on opponent-b
(the residual the search descends). It shows a single strict descent step, that energy
depends only on `|b1 - b2|`, and that the b-axis is non-degenerate (entropy > 0 so the
weight bites). It does not claim termination by itself; the weighted energy is a
non-negative integer bounded below by 0.

---

## 3. The two-level expand(S,I) -> contract(K) rung (V2SkiTwoLevelEntropy.hs)

### One rung = two levels

The 2x2x2 -> (1 coarse + 7 detail) rung is read as TWO octree levels
(`levelsPerStep == 2`, the V2SkiLevels twiceness). One rung = expand then contract.

LEVEL 1 (EXPAND) maximizes ENTROPY by doing as many S (invent-up) and I (held bijection)
moves as are ADMISSIBLE.

- I holds a cell where it is (length-1, value preserved, a bijection).
- S keeps the anchor and manufactures a new distinct detail (length-2): the unique
  cardinality-increasing move.
- S is BARRED on the byte-exact floor (a floor cell is a bijection, BCI excludes
  contraction), so floor cells are forced to I. The entropy-maximal admissible assignment
  is "S on every free cell, I on every floor cell". The floor genuinely CAPS how much S is
  admissible: the admissible-max band length is strictly less than the unconstrained all-S
  length. The maximizer is NOT trivially "all S".

On this distinct-value construction, Shannon entropy reduces to `log2(length)`, so more
admissible S means a longer band means strictly higher entropy.

LEVEL 2 (CONTRACT) maximizes K (pool-down weakening): every (coarse, detail) pair is pooled
to its coarse cell, dropping the detail. K is the only information-losing, non-injective
move. The all-K mask yields the minimal-length band and is consistent with the copied
`poolDown`.

### Steady state and the PonderNet tie

Iterating the contract level is a WELL-FOUNDED recursion. The measure "band length"
strictly decreases on every non-fixed step and is bounded below by 0, so it bottoms out at
the coarse DC (length <= 1) in finitely many steps. That bottom IS the PonderNet halt.

The Ponder tie is by analogy made checkable against `PonderHaltDistribution`: more K (a
higher per-step halt rate lambda) moves halt mass to earlier steps and lowers
`expectedSteps` (mirrors `lawLowerHaltRefinesMore`), and the fully-contracted band with no
detail left to refine is the degenerate `haltDist [] == [1.0]` (all mass at the halt step).

### The honest note: well-founded, NOT a metric contraction

Termination is a well-founded / monotone-decreasing argument on the discrete length
measure (a strictly decreasing function into the naturals, bounded below). It is NOT a
Banach metric contraction. No metric d and Lipschitz constant L < 1 are exhibited. In fact
`lawNoForcedContractionMapping` ships equal-length witnesses that differ only in a COARSE
cell `poolDown` preserves, so the value-distance is UNCHANGED by pooling (ratio 1, no
L < 1 exists) while the length measure still strictly drops. Substructural K = weakening
(drop a hypothesis) is a different notion from a metric "contraction"; only the
well-founded reading is claimed.

Laws (all PASS): `lawSInventsIHolds`, `lawSBarredOnFloor`, `lawLevel1MaximizesEntropy`,
`lawLevel2MaximizesK`, `lawContractReachesSteadyState`, `lawMeasureStrictlyDecreases`,
`lawNoForcedContractionMapping`, `lawHaltMassMovesWithContraction`.

---

## 4. Promotion path

None of these are wired yet. Each is a runghc explorer. The graduation route per module:

### V2LatentMaintenance -> a future `Spec.V2Latent` + `Spec.V2LatentBoundary`

- Graduate the locked record + decode into a real `Spec.V2Latent` (this lift is already
  blessed; the exploration only reuses it). The NEW content to land is the maintenance
  invariant: `encodeBoundary` / `decodeBoundary` as the SOLE sRGB sites, interior ops typed
  `Latent -> Latent`.
- Today the invariant is enforced by TYPE DISCIPLINE made checkable by inspection, not by a
  theorem about arbitrary code. To promote, it needs either a codegen-level guard (a lint
  that the generated Swift/Zig boundary is the only place an sRGB triple is constructed) or
  a newtype/module-boundary that structurally forbids a hidden boundary call. That is the
  main open question.
- The b-sign reconciliation (`ownerBView = negate latB`) should land as a named derived
  view next to `latB`, with `lawEnergyBSignInvariant` as a gate test.

OPEN before promotion: how to enforce "boundary crossed exactly twice" beyond Haskell's
type system; whether the carrier family should also exercise a pair that shares L but
differs in (a,b) to show chroma energy can be nonzero (the verifier flagged that the
chroma-only-energy==0 clause is true by construction and would be hardened by a
complementary nonzero-chroma witness); and an optional `det == 6` self-check so the index-6
grounding is computed, not just asserted in prose.

### V2CrossFrameBEnergy -> alongside `EncoderEntropyFloor` / `Spec.EnergyWeave` and the octree t-seam

- The seam Haar lift (`sLift`/`sUnlift`) is already blessed in V2RgbEisenstein and the
  octree spine; the NEW content is the opponent-b READOUT of the t-detail band and its
  linearity identity. This graduates next to the energy-weighted metric (the `dW` the
  EncoderEntropyFloor / EnergyWeave line owns), as the t-axis specialization of that metric.
- `lawTDetailIsOpponentBSeam` (signed linearity + magnitude + same-sign restriction +
  mixed-sign tooth) and `lawSeamReversible` are the gate-worthy laws.

OPEN before promotion: whether the search descends the SIGNED seam b (clean linearity) or
the magnitude reading (the owner's phrasing, but only piecewise-linear across the
sign-change); the energy-descent law currently demonstrates one monotone step, so a real
termination argument for the t-seam descent (bounded-below integer measure) would need to
be stated as such, not implied.

### V2SkiTwoLevelEntropy -> alongside `Spec.ScalePonder` / `Spec.PonderHaltDistribution`

- The S/K/I role grading and twiceness are blessed in V2SkiLevels; the NEW content is the
  two-level ASSIGNMENT structure (level 1 = entropy-max expand, level 2 = K-max contract)
  and the explicit well-founded steady-state tie to the Ponder halt distribution. This
  graduates as a bridge module between `ScalePonder` (per-scale refine/halt mask) and
  `PonderHaltDistribution` (haltDist / expectedSteps).
- `lawLevel1MaximizesEntropy` (floor caps S), `lawContractReachesSteadyState`,
  `lawMeasureStrictlyDecreases`, `lawNoForcedContractionMapping` (the honesty guard), and
  `lawHaltMassMovesWithContraction` are the gate-worthy laws.

OPEN before promotion: the Ponder tie is an ANALOGY (more K corresponds to higher lambda),
not a derivation that the octree contraction IS the Ponder halt process; to promote, the
correspondence between "pairs weakened by K" and "per-step halt rate lambda" would need to
be made into a typed map, not a parallel witness with matching numbers.

---

## 5. What is genuinely new vs what already existed

So the owner is not misled into thinking settled decisions were re-litigated:

ALREADY EXISTED (reused verbatim, NOT re-opened):

- The opponent-literal latent record and arithmetic (`latL=R+G+B`, `latA=R-G`,
  `latB=R+G-2B`), the index-6 lattice decode congruences, `snapColour`. (V2Latent lock.)
- The energy-weighted L1 metric `dW` and the per-axis entropy weighting. (V2EnergyWeave.)
- The reversible 1-D Haar S-transform `sLift`/`sUnlift`. (V2RgbEisenstein.)
- The S/K/I substructural role grading and the twiceness `levelsPerStep == 2`.
  (V2SkiLevels, V2-SKI-EXPAND-CONTRACT.md.)
- `haltDist`, `expectedSteps`, and the "lower halt refines more" monotonicity.
  (PonderHaltDistribution.) The per-scale refine/halt mask. (ScalePonder.)
- The b-sign fact itself (owner `2B-(R+G)` is the negation of stored `R+G-2B`) was already
  a known tension in the latent lock; the modules state the reconciliation, they do not
  discover or change the sign.

GENUINELY NEW (the actual contribution of these three explorations):

- The MAINTENANCE INVARIANT: sRGB confined to two boundary functions, every interior op
  typed in latent space, "Lab in shape / free in RGB" pinned by the carrier-family witness.
- The explicit, named b-sign reconciliation DECISION (keep stored sign, expose owner sign
  as a derived energy view) carried consistently across all three modules with teeth that
  prove the flip is real and that the stored sign is load-bearing for decode.
- The opponent-b READOUT of the octree t-detail band, with the exact linearity identity
  `ownerB(detail) == ownerB f1 - ownerB f2`, and the honest same-sign restriction with its
  mixed-sign tooth.
- The TWO-LEVEL rung assignment (level 1 entropy-max expand with S floor-capped, level 2
  K-max contract) and the well-founded (NOT Banach) steady-state argument tied by analogy
  to the Ponder halt distribution.
