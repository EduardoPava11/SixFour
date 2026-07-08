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
