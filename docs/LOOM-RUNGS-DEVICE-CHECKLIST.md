# LOOM RUNGS — DEVICE VALIDATION CHECKLIST (iPhone 17 Pro)

The rung-telemetry GRID + independent-ladder capture landed sim-green but the
exposure hardware only exists on a real device (`setExposureModeCustom` is
ignored/unavailable in the Simulator). This is the on-device pass, in two
phases: **Phase A validates the shipped DERIVED mode with no flips**, then
**Phase B flips `Feature.multiScaleLadder` and validates the independent
ladder**. Do Phase A first — it exercises every meter, log line, and record
path without touching the exposure hardware.

Log filtering: Console.app (or `log stream`), subsystem `com.sixfour.SixFour`,
search `[perf]`. All perf lines are once-per-burst — if you see any of them
scrolling per frame, that is itself a failure.

---

## Phase A — DERIVED mode (no flips; today's flag state)

Flags as committed: `rungTelemetry = true`, `yinYangBands = true`,
`v21Capture = true`, `multiScaleLadder = false`. Build + run on the phone,
fire a burst with the 16² shutter.

### A1. The four grid regions populate live

`GridLayoutContract.liveScene` — all four are non-interactive flanks; confirm
none of them ever eats the ground LOOK-swipe, the EV-drag, or the 16² shutter.

| Region   | Where                                        | What it shows |
|----------|----------------------------------------------|---------------|
| `rung64` | right flank beside the 64² pyramid band (col 84, row 49, 14×64) | fine-rung meter |
| `rung32` | right flank beside the 32² band (col 84, row 117, 14×32)        | mid-rung meter |
| `rung16` | right flank beside the 16² band (col 84, row 153, 14×16)        | coarse-rung meter |
| `system` | machine ring below the pyramid (col 18, row 178, 64×24)         | tick CPU / v21 buffer / thermal |

Each rung meter has four sub-blocks; expected DERIVED readings during a burst:

1. **Arrival pulse** — the 6×6 block flips full/hollow at each rung's own
   cadence (64² fastest, 16² slowest; snapshots arrive coalesced at 5 Hz).
   It must STOP pulsing the instant the burst ends (stalled = no movement =
   the honest gap read). Before the first burst all meters are absent
   (σ.rungTelemetry is nil) — that is correct, not a bug.
2. **Exposure state** — the pooling-equivalent vocabulary: `POOL` with EV
   +0 / +1 / +2 stops (0c / 100c / 200c) for 64/32/16. No duration/ISO text.
3. **√N significance** — fill bars normalized to the 16² rung (largest N):
   the derived lattice N(k)=8^k·N₀ reads as √-ladder 1 : 2√2 : 8, so rung64
   ≈ 1/8 of rung16's fill, rung32 ≈ 0.35. Bars are cell-count fills — no
   alpha anywhere.
4. **Independence health** — hollow DIAMOND on 64 and 32 (derived = the
   expected 1000‰ maximal-correlation pole, deliberately not an alarm).
   If you see the triangle (warn ink) in derived mode, that's wrong.

Arrivals count to 64 / 32 / 16 over the burst (expectedArrivals = side).

### A2. The system region

- **Tick CPU**: mean/max vs the 50 ms budget. On-device x420 pooling at
  cropSide 512 should be low single-digit ms mean. Max spikes near 50 ms =
  investigate before flipping anything else.
- **v21 buffer lifecycle**: `.allocated` at burst start → `.held` when the
  detached flow-encode job takes it → `.freed` when the job completes. This
  is the ~384 MiB meter — confirm it reaches `.freed` after every burst and
  never reads `.freed` while a next burst's buffer is live (the generation
  guard).
- **Thermal/pressure**: 0 (nominal) at rest. Fire 5+ bursts back-to-back and
  watch it; note the level where it leaves nominal — this feeds the thermal
  budget doc.

### A3. The [perf] burst lines (once per burst, at the seam)

```
[perf] yin-yang tick CPU: 64 ticks, mean X.XX ms, max Y.YY ms (50 ms tick budget)
[perf] s4cr: N KiB (v2)
```

- Tick mean should be ~1–5 ms; max well under 50 ms.
- NO `[perf] rung …` lines in Phase A (those are ladder-mode only).

### A4. The .s4cr v2 record (derived signature)

Saved next to the GIF (`<capture>.s4cr`). Pull via Files/Finder and check:

- `[perf] s4cr:` should read roughly **60–130 KiB** (v2). The bulk is `c16`:
  16 frames × 16·16·3 = 12,288 u64 sums at ~5 CBOR bytes each ≈ 60 KiB,
  plus `s16`/`dtus`/`gct`/`weave`.
- **c16-only provenance signature**: `c64` and `c32` are EMPTY arrays,
  `c16` has 12,288 uints; `ev` carries pooling-equivalent triples
  (duration 0, iso 0, zigzag EV 0/+100/+200 centistops); `tel` comovement
  = 1000 (fully determined — honest).
- A byte-level sanity check: `python3 -c "import cbor2 …"` on the Mac, or
  just confirm the size + the golden tests already pin the bytes.

---

## Phase B — INDEPENDENT ladder (the flip)

### B1. What to flip

In `SixFour/Settings/Feature.swift`:

```swift
static let multiScaleLadder = true   // was false
```

Nothing else. `rungTelemetry` stays true. Rebuild for device
(`xcodegen generate` if files changed; TEAM QFTX3897B7, cached wildcard
profile). NOTE what the flip gates OFF per burst, by design: the v21
histogram buffer and the ColorHead (EV-cycled frames would corrupt both), so
ladder bursts have **no GCT / no s16 / no yin-yang band training / no field
export** — the system meter's v21 state stays `.none`. That is expected.

### B2. The ladder exposure schedule (what the hardware should do)

The burst AE-locks, meters, then weaves a deterministic 64-tick plan — a
repeating 16-tick super-cycle of dwells **fine64 ×8 → mid32 ×5 → coarse16 ×3**
with the first 2 ticks of each dwell unsettled (ISP settle), giving owned
counts **24 / 12 / 4** per burst. The schedule (evSpreadStops = 4, reference =
the metered AE-locked exposure):

| Rung | EV offset | How it's realized |
|------|-----------|-------------------|
| fine 64² | 0 (reference) | metered duration + ISO |
| mid 32²  | +2 stops (+200c) | ~1 stop exposure TIME + ~1 stop GAIN |
| coarse 16² | +4 stops (+400c) | ~2 stops TIME (capped at 1/20 s frame duration) + ~2 stops GAIN |

Both clamped to the active format's real envelope — in bright light the ISO
floor can eat part of the offset; the meters show the REALIZED values, so read
them, don't assume the ideal.

Verify on the meters / logs:

- **Exposure state block** now shows optical text (e.g. `1/20` + ISO) and the
  EV centistops per rung — 0 / ~+200c / ~+400c (less if clamped).
- **Arrival pulse**: arrivals count toward 24 / 12 / 4 (expectedArrivals =
  planned owned counts, not 64/32/16). `skipped > 0` tints the pulse block —
  settle ticks are accounted per rung, plus any kernel-dropped frames.
- **Independence health**: filled DISC (independent, ok) on 64 and 32. A
  TRIANGLE means the streams co-move everywhere (1000‰) — the ladder is not
  actually separating exposures; check that custom exposure took (some modes
  silently ignore it) before blaming the math.
- **Visually**: the live preview will visibly pulse brighter during mid/coarse
  dwells — that's the ladder working, not a bug. Confirm the preview returns
  to continuous AE the moment the burst ends (the viewmodel defer).

### B3. The [perf] burst lines (ladder mode)

```
[perf] yin-yang tick CPU: 64 ticks, mean X.XX ms, max Y.YY ms (50 ms tick budget)   ← now measures weave ingest
[perf] rung 64²: 24/24 owned, 0 skipped, N=…, EV 0c, comove …‰
[perf] rung 32²: 12/12 owned, 0 skipped, N=…, EV 200c, comove …‰
[perf] rung 16²: 4/4 owned, 0 skipped, N=…, EV 400c, comove …‰
[perf] s4cr: N KiB (v2)
```

- owned/expected short of plan + `skipped` high ⇒ frame drops during the
  burst; check pressure level before re-running.
- comove `< 1000‰` on 64 and 32 = genuinely independent evidence. Record the
  typical value — it's the number the fell-back-to-derived warning threshold
  will be set from.

### B4. The .s4cr v2 record (independent signature)

- `[perf] s4cr:` should now read roughly **1.5–2.5 MiB**: `c64` = 24 × 64·64·3
  = 294,912 uints (~1.4 MiB), `c32` = 12 × 32·32·3 = 36,864 (~180 KiB),
  `c16` = 4 × 16·16·3 = 3,072 (~15 KiB).
- All THREE cubes non-empty; `ev` triples carry the real duration_us /
  iso_milli / zigzag(ev_centistops); `tel` comovement = the worst measured
  pair (should be < 1000).
- The encode+write is detached (background priority) — confirm no hitch at
  the capture seam when the record saves (the `.done` transition should feel
  identical to Phase A).

### B5. Repeat-burst stability

5 bursts back-to-back in ladder mode: pressure level, tick CPU max drift,
and that every burst's record lands (5 `.s4cr` files, each ~MB). Memory
should NOT climb burst-over-burst — the cubes are per-burst and released at
the seam.

---

## Exit criteria

- Phase A all green → the telemetry GRID + v2 record are validated; keep
  `rungTelemetry = true`.
- Phase B all green (meters optical, comove < 1000‰, AE restores, no seam
  hitch, records ~MB with all three cubes) → `multiScaleLadder` is a
  candidate default; bring the result back to `docs/STATUS.md` + the spec
  session notes before flipping anything permanently.
- Any failure: flip `multiScaleLadder` back to `false` — with it off the
  capture path is byte-for-byte the shipped single-exposure burst.

---

## UX round (proposition + controls)

THE DESIGN (docs/UI-FORM-FOLLOWS-FUNCTION.md, 2026-07-08) landed sim-green:
all gates pass (spec 1851, app 430, lint-grid, verify-doc-claims). Everything
below beats off the ONE 20 Hz `SurfaceClock.tick`; every cadence is a theorem
of the ladder (`Spec.ColorTimeDisplay` → `ColorTimeDisplayMath`), never an
animation constant. This is what to LOOK AT on the phone.

### U1. The color-time gathering beat (the proposition itself)

- **Honest rung cadence**: the 64² streams at ~20 Hz as before, but the 32²
  now swaps whole-tile at 10 Hz and the 16² at 5 Hz — each coarse tile is a
  TRUE temporal integral (u64 accumulators over 2 / 4 fine frames, divisors
  1 : 8 : 64), not a downscaled copy of the latest frame. Pan the phone: the
  16² should visibly smear motion across its 4-frame window. The smear is
  the lesson (4× the time, same photons), not a bug.
- **Intake tallies**: 2 slots above the 32², 4 slots above the 16², drawn in
  the pyramid gutters. Each tick a slot fills with that frame's mean colour;
  on the realize tick the filled slots flash lit for 1 tick and clear as the
  coarse tile swaps — that emptying + swap together are the 4-into-1 pour,
  at 5 Hz, forever. If the tally clear and the 16² swap ever come apart,
  the one-clock derivation is broken.
- **The BEAT**: the shutter brackets go lit-ink for exactly 1 tick on every
  16-rung realize (tick ≡ 0 mod 4). The affordance heartbeats at the cadence
  its own frames land at. With Reduce Motion on, the BEAT must be OFF
  (steady ghost brackets) and the tallies/ground ramp calm down.

### U2. The live burst — no freeze (E7, the critical path)

- The old bug: the non-quantized preview branch published empty indices and
  starved the pyramid, so firing a burst froze the surface. FIX: during
  `.capturing` the renderer is FORCED onto the quantized path.
- Fire a burst and confirm the surface stays alive all ~3.2 s: the 64² keeps
  streaming landed frames, the 32² keeps integrating at 10 Hz, the tallies
  keep beating (now counting landed frames). Capture is visibly the same
  machine, recording — never a frozen picture.
- **The banked ledger**: during the burst the 16² fills PERMANENTLY — landed
  frame n takes raster cells 4(n−1)…4n−1 with that frame's 16²-pooled
  colours; unfilled cells stay ghost-dim. 64 frames × 4 cells = 256: the
  WeaveOrder arithmetic drawn live. The finished tile is a genuine
  time-woven image (each 4-cell strip 5 cs apart). A transient "…/320cs"
  CellText steps in the tally row, burst only.
- **Haptics**: one frame-locked detent per completed pour group — 16 felt
  ticks across the 64-frame burst, the 4:1 banking rhythm. Count them.
- Watch for dropped burst frames from the forced quantize (the [perf] lines
  + arrivals count). If frames drop, the pre-agreed fallback is publishing
  raw-RGB tiles — NEVER back to freezing.

### U3. The shutter affordance (E3)

- The 16² wears corner BRACKETS in the gutter outside the tile (zero content
  pixels obscured); the bracket rect IS the hit rect (~80 pt, over the touch
  floor — noticeably easier to hit than the old bare tile tap).
- States to see: idle = ghost + BEAT; pressed = bracket + tile inversion for
  2 ticks; busy = CellButton red brackets with the banked ledger filling
  inside. All opaque ink — if anything looks translucent, that's a bug.
- TAP the 64² = meter: a 3×3 inverted-cell crosshair at the metered point
  for 20 ticks (the 64² deliberately has NO control face — it is a surface
  you point at, not a button).

### U4. LOOK / EV visibility (E5 rails + E6 flux bar)

- **EV rail** (left edge, vertical drag): 13 detent blocks, one per ⅓ stop,
  ±2 EV, centre ghost = 0 EV. It materializes outward from centre while the
  drag is live (≤6 ticks) and dematerializes 8 ticks after release; one felt
  detent per ⅓-stop crossing. Idle it collapses to a 3-cell ghost notch
  spine — nearly nothing, but discoverable.
- **LOOK strip** (above the 64², horizontal swipe): one 4×4 swatch per look
  = that look's OKLab grade on a fixed probe; the active look wears the
  1-cell FRAME; swipe slides the frame, commit on release as before; the
  strip lingers 20 ticks then dematerializes. This replaces the deleted
  palette widget's only defensible job (LOOK indicator) — grade shown ON
  colours, no flicker.
- **Flux bar** (16×1, directly under the shutter brackets): log₂-scaled
  paletteW1 between consecutive 5 Hz GCTs (`s4_v21_wdist1d`) — the wave
  meter, the instrument framing's single number. Wave the phone at a
  colourful scene: it should surge; hold still on a wall: it should sit
  near empty. All-ghost = no GCT feed (expected when the head is off).
- The four verbs of Live, total: DRAG the ground = grade (LOOK ↔ / EV ↕),
  TAP the 64² = meter, TAP the 16² = fire. Everything else watches.

### U5. The Decide rebuild (D3)

- HERO: the 64 reconstruction wearing BRACKETS (brackets invert while
  scrubbing — horizontal drag scrubs the burst frame), with the raw 16³
  coarse tier beside it carrying the same tally idiom (static ledger
  structure — the equivalence language crosses scenes).
- TWO VERBS at the bottom, the clearest controls in the app (44×16 cells
  each, 4× the touch floor): ACCEPT = filled control-ink face + seal glyph
  (heavy haptic); AGAIN = hollow FRAME + retake glyph (light haptic).
  Confirm both are hittable without looking.
- ADVANCED FOLD: paint / channels / gauge / gene-toggle all live behind one
  12-cell chevron; opening paints the advanced rows in top-down, 1 row/tick.
  Their W1 semantics are untouched — placement demotion only; nothing
  golden-gated was deleted.

### U6. What got deleted (confirm the absences)

- The legacy 16×16 palette widget is GONE from Live (authorized 2026-07-08):
  its region crowded the 32/16 bands and its rebake flicker dies with it.
  Its LOOK-indicator function moved to the LOOK strip. Mounts remain on
  non-live acts only.
- The idle marching shimmer is gone — the BEAT is the one moving invitation.
- The ground no longer blazes at idle: `liveIdleEnergy` dims it to a calm
  near-void; during `.capturing` it rises with a (tick mod 4)/4 pour ramp —
  the ground glows exactly when photons are being banked, and only then.
- PAINT is gone from Live (it lives in Decide, behind the fold).

### U7. If the surface reads busy (pre-agreed drop order)

Drop in this order, nothing else: ground pour-ramp → meter crosshair linger
→ the BEAT. The intake tallies and the honest cadence go LAST — they carry
the charter's whole point. If the 5 Hz vertex reads as jank rather than
integration, the fallback is honest-cadence-during-capture-only (idle keeps
smooth pooling) — but judge the true design on device first.

## THE SCROLL (tiling round)

Flag as committed: `Feature.scrollTube = true`. THE SCROLL is a self-excursion
inside `.live` — pure render state (`surface.scrollTube`), the FSM and the
capture flow untouched. Substrate: the Jeandel–Rao aperiodic Wang tiling as the
op syntax (`Spec.WangTiling`, exact ℤ[φ] oracle — random access, never repeats),
the θ_up gene as attention over it, `TubeSynth` slices generated off-main.

### S1. Scroll entry

- LONG-PRESS (0.5 s) on the 64² hero enters the tube (selection haptic); a
  quick tap on the hero still METERS — confirm the two gestures never collide.
- Entry is refused while a burst is staging (`!stage.active`) and outside
  `.live` — try both; nothing should happen.
- EXIT verb returns to the live pyramid; any phase change away from `.live`
  force-drops the tube (`surface.scrollTube = false` in SurfaceView). Confirm
  the shutter and EV/LOOK verbs behave identically after an exit round-trip.

### S2. Aperiodic novelty check

- Drag through 20+ consecutive slices: NO frame window may visibly repeat —
  the tiling is aperiodic by theorem (11 tiles, arXiv:1506.06492), so any
  perceived loop = a bug in the oracle window or the slice cache, not taste.
- RESEED: the whole tube changes character; the same seed after relaunch
  replays the SAME tube (deterministic SplitMix64 derivation — the floor is
  bit-exact). Fling far (±10⁹-scale coordinates are in-contract): no hitch,
  no edge tearing — edge-matching is automatic by construction.

### S3. 4-slice playback (the pour group)

- The viewport loops the current slice's 4 fine frames at 20 Hz — four fine
  frames = ONE coarse frame, the `Spec.ColorTimeDisplay` 4-into-1 pour. The
  SLICE readout (transient CellText, EV-overlay idiom) tracks the drag.
- One viewport of vertical travel = one slice; drag up = deeper. A slow drag
  must not drift (absolute from the drag's base slice); a fast fling must
  never block on neighbours — unmaterialized slices show an HONEST BLACK
  void, then fill when the `TubeLoader` actor delivers (visible ± prefetch).
- The tube-position rail (±32-slice ruler under a fixed cursor) stays in
  lock-step with the slice index.

### S4. Refine-on-linger

- A fresh slice arrives as its 16² pool INSTANTLY, then crystallizes up the
  reveal ladder where you linger: 32² at 8 linger ticks, 64² at 16
  (`S4WangTiling.revealTick`, reciprocity `revealTick·unitsOf = 16`) —
  decode-compute is spent where the user lingers, the gene-compute-economy
  read made visible.
- Scrolling away RESETS the linger; returning to a slice re-runs its ladder.
  A fast scroll should read as a river of coarse 16² pours — coarse-first is
  the design, not a loading artifact.

### S5. BOOT RESOLVE on Live (the warm-up crystallization)

- Cold-launch into `.live`: the pyramid warms up through the SAME reveal
  ladder — 16² first, 32² and 64² earn their reveal as `bootTicks` cross
  `revealTick` (one-shot `>=` latches, each rung's face rebakes ONCE at its
  crossing). The boot should read as crystallization, not pop-in.
- Re-enter `.live` (from Decide, or after an app background): a DECREASING
  `bootTicks` re-arms the latches — the ladder replays, no rung is stuck
  hidden and none double-fires. Previews and non-boot mounts (`Int.max`
  default) are fully revealed and untouched.

### S6. Gene-attention look changes

- The gene reaches the generator as the committed θ_up words through the ONE
  sanctioned float→Q16 crossing; no gene ⇒ the deterministic floor
  (zero-gene == floor). Compare pre-training vs post-training entry: the tube
  should change LOOK (weights + palette warp), NEVER structure — the tiling
  schedule is theorem-fixed (`lawAttentionModulatesNotMutates`).
- The gene is captured ONCE per tube entry — commit a new θ_up mid-scroll and
  confirm nothing shifts until you EXIT and re-enter; then the same slices
  wear the new look at the same positions (attention modulates, the oracle
  decides).
