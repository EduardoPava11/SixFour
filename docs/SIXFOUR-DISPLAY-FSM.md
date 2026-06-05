# SixFour Display FSM — the formal map (PhD-grade specification)

> **Status:** design map, pre-implementation. This document is the *mathematical
> contract* that the Haskell module `SixFour.Spec.Display` will discharge and
> that `Generated/DisplayContract.swift` will pin cross-language. No code is
> written until this map is accepted. Every claim cites the existing proven
> oracle that supplies it — **the FSM is a colimit of four modules already in
> `spec/`, not a new invention.**

---

## 0. Thesis

The iPhone-17-Pro display, driving SixFour, **is** a finite state machine

```
            M = (Σ, ι, δ, λ, Π, κ)
```

advanced by a single **20 Hz logic clock** `κ` and presented by the panel's
**120 Hz scan-out** as a pure re-read. The user's two requirements —

1. *every cell is an I/O unit whose colour is computed every 1/20 s*, and
2. *GIF (64×64), palette (16×16) and shutter (4×4) share one cell*

— are **not two features**. They are, respectively, the **totality of `δ` over
the lattice** (Theorem T5) and the statement that the three grids are
**projections `Π` of one state `Σ`** (Theorem T3). "Pin the clock" and "kill
`cellPt`" were never separable: they are `κ` and `Π` of the same `M`.

PhD-level certainty means: each component is **typed against the repo's actual
representation**, and each invariant is a **theorem with a proof obligation that
either (a) reduces to arithmetic, (b) reuses an already-proven law, or (c) is a
type signature**. Nothing is asserted.

---

## 1. Notation and the ground constants

All sourced from `spec/src/SixFour/Spec/Lattice.hs` (verified) and
`Native/include/sixfour_native.h` (the C ABI, verified).

| Symbol | Meaning | Value | Source |
|---|---|---|---|
| `H, W, T` | frame height, width, count | `64` | `SixFourShape` |
| `K` | palette leaves | `256` | global palette |
| `P` | pixels per frame `H·W` | `4096` | — |
| `atom` | one GIF pixel pitch | `6 pt = 18 device-px` | `Lattice.gifPx` |
| `(w_pt, h_pt)` | screen, portrait pt | `402 × 874` | `Lattice.screenWidthPt/HeightPt` |
| `s` | point→pixel scale | `3` (@3x) | `Lattice.scale` |
| `(w_px, h_px)` | physical pixels | `1206 × 2622` | `w_pt·s, h_pt·s` |
| `R` | panel scan-out rates | `{60, 120}` Hz | ProMotion (web-verified) |
| `f` | logic / capture / GIF rate | `20` Hz | `SFTheme.gifFrameRate` |
| `Q16` | fixed-point scale | `2^16` | `sixfour_native.h:68` |

`OKLab_Q16 := (Int32, Int32, Int32)` — one OKLab colour, each channel `value·2^16`.

---

## 2. The objects (state space — typed exactly)

### 2.1 The carried state `Σ`

```
Σ  :=  (P, F, c)
   where
     P : Vector K  OKLab_Q16          -- the ONE global palette (K=256 leaves)
     F : Vector T  (Vector P  Fin K)  -- T index fields; F[t][p] ∈ [0,K) is a palette index
     c : Fin T                        -- the playback cursor (which frame is shown)
```

- `P` is the **global** palette (CLAUDE.md "Palette: global vs per-frame" — the
  NN emits ONE global genome reconstructed to `K` leaves). Carried as `Q16`,
  exactly the bytes `s4_global_collapse` / `s4_quantize_frame` produce.
- `F` is the index cube: each frame `t` is `P` palette indices. This is *exactly*
  the GIF89a local-image representation (indices + one table).
- `c` is the cursor; `c ∈ Fin T = Z₆₄` is the carrier of `Spec.PlaybackClock`.

### 2.2 The fork, resolved: state is an S_K-quotient

The genuine design fork was *"is the state the OKLab field or the palette-index
field?"* **Neither — it is the equivalence class `[Σ]` under the gauge group
`S_K`.** `Spec.Gauge` proves `(P, F)` and `(σ·P, σ·F)` decode to the **same**
image for any permutation `σ ∈ S_K`:

```
gaugeAction σ (P, F)  decodes identically to  (P, F)     -- Spec.Gauge, the module's central law
```

So:
- the **carried** representation is the integer pair `(P, F)` — what GIF stores,
  what Zig `δ` computes, deterministic and cross-device bit-exact;
- the **observable** is `gather(P, F[c]) : Vector P OKLab` — the decoded field,
  which is `S_K`-invariant.

The state space is therefore the quotient `𝒮 := Σ / S_K`, and `λ` (§3) is
well-defined on `𝒮` **because** of `Spec.Gauge.gather`. This is the rigorous
resolution: we carry indices (cheap, integer, deterministic) and *observe*
colour (gauge-invariant). Theorem **T6** discharges well-definedness.

### 2.3 Input

```
ι_τ : OKLabField_Q16   -- one camera frame at wall-tick τ, H·W·3 Q16 (capture mode)
```

In review mode `ι` is the empty input `()`; the only motion is the cursor.

### 2.4 The grid bundle and provenance on the base

The display is not carried as a flat cell array but as a **fibre bundle**

```
Grid  ≅  Place(WHERE) ─fibre→ Cell(WHAT)
```

— a Swift-owned finite **base** `Place` (the *where*: a coordinate/address in the
§3.3 lattices) carrying a Zig-owned **fibre** `Cell` (the *what*: the integer
colour datum the deterministic Zig core computes). **Provenance lives on the
base**, as a typed binding

```
binding : Place → Source        Source = {Zig, Swift, Cursor}   -- fixed, finite
```

assigning each place its authoritative producer. Because `Source` is a **fixed
finite** set and `Place` is a finite enumerated carrier (`Spec.CellGrid`), the
provenance carrier is bounded by construction — this **dissolves the
unbounded-carrier concern**: there is no place whose origin is unaccounted, and
no source outside the three. The grid algebra (the fibre join and its pointwise
lift `gridJoin`, Theorem **T9**) is **realized as `Spec.CellFiber` (the fibre
+ its join law) `+ Spec.CellGrid` (the finite-`Place` base)**.

#### 2.4.1 Ownership is on widgets; overlap is detected, never blended

Refining the above: the base is **partitioned by widgets**, `owner : Place →
Maybe Widget` (`Spec.CellGrid.Owner`). A well-formed layout has **disjoint** owned
regions, so every cell is `⊥` or a singleton and overlap never occurs
(`lawDisjointNoContest`). When two widgets *do* claim one place, the system does
**not** blend and does **not** error — it makes the collision **detectable and
loud**:

- `isContested : Cell → Bool` and `contestedPlaces : Grid → [Place]` are total —
  you *always know* a collision happened.
- The observer **never synthesises a colour**. `render` returns only the neutral
  anchor, an *actual* claimant, or a reserved `contestedSentinel` (a vivid magenta
  marker) — proven by `lawNoSynthesis` / `lawNoSilentMerge`. This is the formal
  statement of *"I do not blend."*
- A place flagged as an **effect-zone** instead `shimmer`s its claimants on the
  20 Hz clock `κ` (`renderGridAt t`), showing one *real* claimant per tick
  (`lawShimmerIsClaimant`) — the opt-in "overlap as effect" that is still never a
  mixture. Accidental overlap = loud sentinel (a bug you see); intentional overlap
  = shimmer (an effect you chose).

So contention is a **first-class, total, visible** event, not a failure mode — the
spatial complement of T5's "every cell is computed" is "every collision is seen."
Implemented and `cabal test`-green in `Spec.CellFiber` + `Spec.CellGrid`.

#### 2.4.2 The layer law — content is the only layer (glass retired 2026-06-05)

> **SUPERSEDED.** Earlier drafts of this section factored presentation into two
> orthogonal layers — a flat content grid `C` under an optical glass layer `G`, with
> the safety theorem `encode(G(C(Σ,t))) = encode(C(Σ,t))`. **Glass was retired
> app-wide on 2026-06-05 — *total pixelation wins*** (`docs/SIXFOUR-DESIGN-LANGUAGE.md`
> §9.7; `docs/SIXFOUR-TOTAL-PIXELATION.md`). The prior glass constitution is archived
> at `docs/archive/SIXFOUR-GLASS-LANGUAGE.md`. The two-layer formalism below is kept
> only as the limiting case it collapses to.

The display now has **one layer**. There is no presentation transform between the
committed state and the screen:

```
screen(Σ, t)  =  C(Σ, t)
                 └ CONTENT: the flat, deterministic cell grid = λ = renderGridAt
                            → sRGB8 (Zig-pure, byte-exact). This is what ENCODES,
                              and it is also exactly what is shown.
```

**GRID Law #2 in its current (post-pixelation) form:** a cell is one flat indexed
sRGB8 colour — the byte-exact truth the GIF encodes. There is **no glass on any
surface**; all chrome is cell-rendered (pixelated), never glassy.

The old safety theorem now holds **vacuously**: with the glass layer `G` removed,
`encode ∘ glass = encode` degenerates to `encode = encode`. This is the *strongest*
possible form of the layer law — nothing can diverge what is displayed from what is
encoded, because there is no transform between them. (It remains the presentation half
of the Moore observation `λ` — T8 — but `λ` is now the identity on the rendered
cells.) The content layer is spec-verified (`CellAlgebra`/`CellContract` golden);
`ContestedCellGridView.swift` (L0) is composed **directly**, with no L1 wrapper. The
former `SixFour/UI/Components/GlassOverContent.swift` was deleted in the 2026-06-05
cleanup.

---

## 3. The morphisms

### 3.1 Transition `δ` — one per mode, one shared state

```
δ_capture : Σ × ι  → Σ        -- ingest a camera frame: quantize+dither → new index field, advance write head
δ_review  : Σ × () → Σ        -- δ_review (P,F,c) () = (P, F, frameAfter T c)
```

- `δ_review` **is** `Spec.PlaybackClock.frameAfter` lifted to `Σ` — already total
  and proven (`PlaybackClock.hs:61`).
- `δ_capture` is the deterministic quantize+dither core: `s4_quantize_frame`
  (`sixfour_native.h:128`) + `s4_dither_frame` (`:164`), mirrored by
  `Spec.QuantFixed` / `Spec.Dither`. It writes a **full** index field — every
  one of the `P` cells (Theorem T5).

One machine, one `Σ`, one clock; the mode selects the transition. This is why
"clock" and "cells" are the same object.

### 3.2 Observation `λ` — Moore, by signature

```
λ : Σ → Vector P  SRGB8        -- λ (P,F,c) = map (oklabToSrgb8) (gather P (F ! c))
```

`λ` takes **no input argument** — output depends only on the committed state.
This *type signature* is Theorem **T8** (Moore ⇒ tear-free double-buffering).
`oklabToSrgb8` is the fixed-point `s4_palette_oklab_to_srgb8`
(`sixfour_native.h:175`), mirrored by `Spec.ColorFixed`.

### 3.3 Projections `Π` — the three grids as ONE state's Haar views

The visible regions are not three states; they are three observers of `Σ`:

```
Π_gif     (P,F,c)  =  λ (P,F,c)                                  -- 64×64 = gather field   (level 0)
Π_palette (P,F,c)  =  map oklabToSrgb8 P                         -- 16×16 = K=256 leaves
Π_shutter (P,F,c)  =  map oklabToSrgb8 (levelNodesFixed 4 P)     -- 4×4   = 16 Haar level-4 nodes
```

`levelNodesFixed 4` is `Spec.PairTreeFixed` / `s4_haar_level_nodes`
(`sixfour_native.h:158-162`, "256 leaves → 16 level-4"). Because all three
factor through the **same** `P` (and `F`), they cannot drift — Theorem **T3**.

> **Ground-truth correction:** an earlier exploratory pass guessed palette=level-2,
> shutter=level-3. The verified C ABI says **shutter = level-4 = 16 colours**
> (4×4) and **palette = the 256 leaves** (16×16). The map uses the ABI.

### 3.4 The clock `κ`

```
κ : the single 20 Hz wall-clock that fires δ once per tick;
    the panel re-presents λ(Σ) for R/f scan-outs between firings.
```

`κ` is realized by `CADisplayLink` with
`preferredFrameRateRange = CAFrameRateRange(20,20,20)`. Its correctness is
Theorems **T1** (divisibility) and **T7** (capture phase-lock).

---

## 4. The theorems (with proof obligations)

Each law is named for the Haskell `lawX :: Bool` it becomes. The **proof
obligation** column states exactly what discharges it.

### T1 — Sub-refresh realizability (the clock divides the panel)
```
lawClockDivides :  ∀ R ∈ {60,120}.  R `mod` f == 0     -- 60%20=0, 120%20=0
```
⇒ one logic tick = exactly `R/f ∈ {3,6}` integer scan-outs; the panel holds the
committed `Σ` for a whole number of refreshes (no fractional hold, no judder).
**Obligation:** arithmetic (NEW — no existing module owns the wall-clock↔panel
relation; `PlaybackClock` owns only the `Z_N` cursor).

### T2 — Single clock (no competing timers)
```
lawOneClock :  |clocks(M)| == 1
```
The capture-advance and review-advance streams are both indexed by the one `κ`.
**Obligation:** structural — modelled as: both `δ_capture` and `δ_review` are
fired by the same tick function; pinned in Swift by a contract assertion that
exactly one `CADisplayLink` exists (retires the `VoxelCubeView` 60 Hz timer).
Mirrors Design Law #4.

### T3 — Projection consistency (the three grids cannot drift)
```
lawProjectionsShareState :
    Π_shutter Σ  ==  map oklabToSrgb8 (levelNodesFixed 4 P)   where (P,_,_) = Σ
    ∧  reconstructFixed (analyzeFixed P) == P                 -- byte-exact, Spec.PairTreeFixed
```
Since `Π_palette` and `Π_shutter` both factor through the **same** `P` via an
*exactly invertible* Haar transform, the shutter is a deterministic coarsening of
the palette — never an independent value. **Obligation:** reuse
`Spec.PairTreeFixed` round-trip law (already proven; `sixfour_native.h:147`
"reconstruct∘analyze = id byte-exact").

### T4 — Atom invariance across levels (kill `cellPt`)
```
lawUniformAtom :  ∀ view i.  cellPitchPt(i) == atom * b_i,   b_i ∈ ℤ⁺
                  ∧  extentPt(i) == gridDim(i) * b_i * atom    -- integer pt, lands on the lattice
```
with block factors `b_gif = 1`, `b_palette`, `b_shutter` chosen so each grid
tiles the lattice. There is **no free `cellPt`**: every cell is `atom × ℤ`.
**Obligation:** extends `Spec.Lattice.lawEveryGovernedDimIsCells`
(`Lattice.hs:332`) from a flat dimension list to per-view block factors. The
pitch-uniformity check that `LatticeContract.selfCheck()` currently **lacks**.

### T5 — Totality over the lattice ("every cell MUST be I/O at 20 fps")
```
lawDeltaTotal :  touched(δ_capture) == fullLattice          -- all H·W cells written each tick
              ∧  ∀ Σ ι.  δ_capture Σ ι  is defined           -- total function
```
`touched(δ)` is the set of cell coordinates whose next value `δ` *writes*. The
requirement "each cell has its colour computed every 1/20 s" **is** the assertion
`touched = {0..H-1}×{0..W-1}` — no cell carried over uncomputed, no cached path.
**Obligation:** structural — `δ_capture` is defined by a total `∀(x,y)` map (the
per-cell quantize+dither), and the contract forbids a cache-indexing observer
(the current `GIFCanvas` has `touched = ∅` — it violates T5 and must be replaced
by the `PaletteGridView` reactive pattern). This is the theorem that turns the
user's requirement into a *checkable* property. Its **spatial sibling** is
Theorem **T9** (`gridJoin` totality), which lifts a *total fiber join* over the
*total finite Place base* — the same totality discipline, indexed by the spatial
`Place` fibre rather than by the temporal tick.

### T6 — Gauge invariance of observation (well-definedness on 𝒮)
```
lawGaugeInvariant :  ∀ σ ∈ S_K.  λ (gaugeAction σ Σ) == λ Σ
```
⇒ `λ` descends to the quotient `𝒮 = Σ/S_K`; the choice of palette index labels is
unobservable, so carrying integer indices loses nothing. **Obligation:** reuse
`Spec.Gauge.gaugeAction` + `gather` (the module's central, already-stated law —
`Gauge.hs:63`).

### T7 — Capture phase-lock (1:1 ingest, no pile-up)
```
lawCapturePhase :  captureRateHz == f == 20
                ∧  bijection (τ-ticks over a burst)  (captured frames)   -- N ticks ↔ N=64 frames
```
⇒ exactly one `ι_τ` per `δ_capture` tick: no frame starvation, no buffer
pile-up. **Obligation:** arithmetic + the capture-session interval = `1/f`
(`CaptureViewModel`). NEW (cross-cuts capture and clock).

### T8 — Moore observability (tear-free double buffer)
```
lawMoore :  λ : Σ → Pixels      -- λ has NO Input argument
```
⇒ any scan-out at a sub-tick instant reads a fully-committed `Σ`; `δ` computes
`Σ_{t+1}` into the back buffer and the swap is atomic at the tick boundary.
**Obligation:** the *type signature* of `λ` (§3.2) — discharged by construction.

### T9 — `gridJoin` total over the place fibre (the SPATIAL sibling of T5)
```
lawGridJoinTotal :
    Grid  ≅  Place(WHERE) → Cell(WHAT)                     -- the display factors as base → fibre
    ∧  ∀ g₁ g₂ : Grid.  gridJoin g₁ g₂  is defined          -- totality, inherited pointwise
       where  (gridJoin g₁ g₂)(π) = cellJoin (g₁ π) (g₂ π)  -- Place π : pointwise lift of the fibre join
```
Where T5 asserts **temporal** totality — `δ_capture` writes *every* cell each
tick — T9 asserts the **spatial** totality of the display's *combination*
operation. The display is not a flat array of cells; it **factors** as a fibre
bundle

```
Grid  =  Place(WHERE) ─fibre→ Cell(WHAT)
```

a Swift-owned **base** `Place` (the finite *where* — a grid coordinate / address
in the 64²/16²/4² lattices of §3.3) carrying a Zig-owned **fibre** `Cell` (the
*what* — the integer colour datum a cell holds, computed by the deterministic Zig
core). `gridJoin` is the join of two grids; by the fibre factorisation it is the
**pointwise lift** of the per-cell join over the base:

```
gridJoin g₁ g₂  :=  λ(π : Place). cellJoin (g₁ π) (g₂ π)
```

**Totality is therefore inherited, not re-proved.** Two facts compose:
1. the **fibre join** `cellJoin` is total — `Spec.CellFiber` proves its join law
   (the fibre is a bounded join-semilattice; every pair of cell values has a
   defined join);
2. the **base** `Place` is *total and finite* — `Spec.CellGrid` enumerates the
   place lattice as a finite carrier, so the pointwise lift quantifies over a
   complete, bounded index set.

A total binary operation lifted pointwise over a total finite index is total.
Hence `gridJoin` is total **by construction of the bundle**, exactly as `δ`'s
totality (T5) follows from a total per-cell map over the full lattice. **This is
the same theorem one fibre-axis over:** T5 lifts a total cell-update over the
temporal tick; T9 lifts a total cell-*join* over the spatial `Place`.
**Obligation:** reuse — the **`Spec.CellFiber` join law** (fibre join totality) +
**`Spec.CellGrid`** (finite-`Place` enumeration). No new totality argument is
introduced; the lift is the content. (Cf. the provenance note in §2.4/§5: the
base is *also* where `binding :: Place → Source` lives, so the carrier is fixed
and finite, dissolving any unbounded-carrier worry about `gridJoin`.)

---

## 5. The reuse map (M is a colimit, not an invention)

| FSM component | Supplied by existing oracle | Status |
|---|---|---|
| cursor / `δ_review` (`Z₆₄`) | `Spec.PlaybackClock` (`frameAfter`, `clampFrame`) | **proven** |
| spatial atom / lattice / T4 base | `Spec.Lattice` (`gifPx`, `lawEveryGovernedDimIsCells`) | **proven** |
| pixel-gauge anchor (1206×2622) | `Spec.Lattice` (`screenWidthPt·scale`, …) | **proven** |
| projections `Π` / T3 | `Spec.PairTreeFixed` (`levelNodesFixed`, round-trip) | **proven** |
| gauge quotient / T6 | `Spec.Gauge` (`gaugeAction`, `gather`) | **proven** |
| `δ_capture` (quantize+dither) | `Spec.QuantFixed`, `Spec.Dither` | **proven** |
| observation `λ` (OKLab→sRGB8) | `Spec.ColorFixed` | **proven** |
| grid bundle / fibre join / T9 | `Spec.CellFiber` (fibre + join law) `+` `Spec.CellGrid` (finite-`Place` base) | **to write** |
| **NEW: T1, T2, T4-ext, T5, T7, T8, T9 + the composition** | **`Spec.Display`** (this map) | **to write** |

`Spec.Display` imports the modules above and proves T1–T9. Most reduce to a
one-line citation of an imported law; the genuinely new content is **T1, T5, T7,
T8 and the composition theorem** that `Π_gif`, `Π_palette`, `Π_shutter` are all
observers of one `Σ`. That composition theorem is *the single artifact that makes
the clock and the cells provably the same machine.* **T9** adds the spatial axis:
the grid factors as the bundle `Place(WHERE) → Cell(WHAT)` (base + fibre, with
provenance `binding : Place → Source` on the finite base — §2.4), and `gridJoin`
totality is **inherited** as the pointwise lift of the total fibre join
(`Spec.CellFiber`) over the total finite `Place` base (`Spec.CellGrid`) — making
it the spatial sibling of T5's temporal totality.

---

## 6. The new module + codegen target

### 6.1 `spec/src/SixFour/Spec/Display.hs` (signature only — to implement)
```haskell
module SixFour.Spec.Display
  ( -- * Mode + state
    Mode(..), DisplayState(..)
    -- * Morphisms
  , deltaReview, deltaCapture        -- δ
  , observe                          -- λ  (Moore: no Input arg)
  , projGif, projPalette, projShutter-- Π
    -- * Clock arithmetic
  , logicRateHz, panelRates, holdCounts   -- 20 ; [60,120] ; [3,6]
  , blockFactor                      -- per-view b_i for T4
    -- * Laws (T1..T8)
  , lawClockDivides, lawOneClock, lawProjectionsShareState
  , lawUniformAtom, lawDeltaTotal, lawGaugeInvariant
  , lawCapturePhase, lawMoore
    -- * Golden gate (N=64)
  , goldenTickTrace                  -- [(DisplayState, Input)] → [DisplayState]
  ) where
```

### 6.2 `SixFour/Generated/DisplayContract.swift` (codegen, à la `PlaybackClockContract`)
Pins, cross-language: `logicRateHz = 20`, `panelRates = [60,120]`,
`holdCounts = [3,6]`, the per-view `blockFactor`s, the `touched == fullLattice`
totality flag, and a **golden tick-trace** — a short `[(Σ, ι) → Σ']` sequence the
Swift `PlaybackClock`/capture path must reproduce bit-for-bit. Emitted from
`Spec/Codegen/Swift.hs`; `cabal test` is the gate (CLAUDE.md build/test).

### 6.3 Order of work (spec-first, per `SIXFOUR-SPEC-METHODOLOGY.md`)
1. Write `Spec.Display` + `Properties.Display` (T1–T8), `cabal test` green.
2. `cabal run spec-codegen` → `DisplayContract.swift`.
3. Swift: swap `PlaybackClock`'s `Timer` → `CADisplayLink(20,20,20)`; advance off
   `targetTimestamp`; retire the `VoxelCubeView` 60 Hz timer (T1, T2).
4. Swift: delete the `cellPt` parameter from `CellSprite`/`HaarShutterView`/
   `PaletteGridView`; render at `atom × blockFactor` (T4).
5. Swift: replace `GIFCanvas`'s 64-`UIImage` cache with the reactive per-cell
   `Canvas` keyed on the cursor (T5); feed blue-noise (per-pixel independent),
   not error-diffusion (sequential).
6. Extend `LatticeContract.selfCheck()` with the pitch-uniformity assertion (T4).

---

## 7. Out of scope (deliberately, to keep the proof tight)

- The **content** of `δ_capture`'s palette extraction (Lloyd/Wu/k-means) — owned
  by `Spec.QuantFixed`; `Spec.Display` only asserts its *totality* (T5), not its
  clustering quality.
- The **look-NN** genome path — orthogonal; it produces `P`, which `Σ` carries.
- Per-cell **touch routing** (which data axis a tapped cell edits) — a separate
  interaction spec (`Spec.AddressPicker` lineage); `M` here governs *display*
  I/O, not gesture semantics.

---

## 8. One-paragraph summary

The display is `M = (Σ, ι, δ, λ, Π, κ)`. State `Σ = (palette, index-cube, cursor)`
carried as integers, observed up to the `S_K` gauge. One 20 Hz clock `κ` fires
`δ`; the 120 Hz panel re-reads `λ(Σ)` `R/f` times per tick (T1). The GIF, palette
and shutter are three Haar projections `Π` of the *one* `Σ` (T3), each rendered at
`atom × ℤ` (T4) — so "kill `cellPt`" is a theorem, not a refactor. "Every cell is
I/O at 20 fps" is `touched(δ) = fullLattice` (T5). All seven sub-oracles are
already proven; `Spec.Display` adds T1/T5/T7/T8 and the composition. That is the
PhD-grade map; the Haskell is now mechanical.
```
