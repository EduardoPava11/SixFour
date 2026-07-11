# Session notes 2026-07-09/10 — THE MERGE arc: SUNSET (device verdict: failure)

## THE VERDICT (Daniel, 2026-07-10, on device — outranks everything below)

**This session's UI direction FAILED**, for two reasons, verbatim:

1. **"It does not fit the screen of the iPhone."** The Decide scene as built —
   the playing hero + coarse tier + tally + signal rail + POUR face + fold +
   verbs, plus the slide rail/chip overlays — does not fit the real device
   experience. The GridLayout proofs (in-bounds, disjoint, touch-floor) held,
   which is exactly the lesson: **lattice-legal is not the same as
   fits-the-screen.** Region math cannot judge crowding, hierarchy, or what a
   thumb and an eye can actually use on a 6.3" phone.
2. **"It is borrowing a lot of technical debt."** The arc generated three new
   spec modules, a playhead, a hero cache, evidence schedules, a reads
   pipeline, new lint, and new feature flags in two days — much of it
   workflow-generated at high speed. Even with the review round and the
   cleanup round, the session ADDED more machinery than the app's current
   stage has earned. Debt was borrowed against a UI composition that is now
   rejected.

## What was landed (the six commits, for the record)

- `8a45447` Spec.MergeBoard game algebra + `.s4cr` v3 decision word (`dw`)
- `f89a546` S4MergeBoard Swift core + the ACCEPT seal
- `fab48df` THE MERGE playable on the Decide hero (tap=S / hold=K / pooling)
- `7cdc77b` THE TIME SLIDE + reads-as-signal (Spec.TimeSlide /
  Spec.RungReadDisplay / Spec.MergeEvidence + Swift twins)
- `f600ea8` review cleanup (one owner per integer, one cache mechanism)
- `25d9150` DecideModel → @Observable

All gates were green throughout (spec 1916→1957, sim suite, lints, Haddock).
Green gates did not save the session: **the failure axes (screen fit, debt
budget) were never gated.**

## What SURVIVES the sunset (sound regardless of the UI verdict)

- **The spec laws.** Spec.MergeBoard / MergeEvidence / TimeSlide /
  RungReadDisplay are true mathematics with golden gates; the replay keystone
  (decision word + sealed telemetry replays the exact board, flag-free) and
  the anti-conflation theorem are wire-level facts, not UI.
- **The `.s4cr` v3 wire** (`dw` key; v1/v2 bytes pinned unchanged) and the
  seal path. Training-corpus records written by any future UI remain lawful.
- **The capture-side hardening**: BurstWeaveDriver atomic slice bookkeeping +
  required tickIndex; the causal-hold fix (raw-tick, late-in-window slices
  reachable); the reads realize at the exact radiometric base.
- **The lints** (MERGE-REPLAY span-aware gate) and the cleanup discipline
  (one owner per ladder integer, key-based cache invalidation, @Observable).

## What is SUNSET (do not build further on these without a new decision)

- **The Decide-scene COMPOSITION**: hero-as-board + instrument column
  (signal/pour) + slide rail/chip + fold + verbs all on one screen. Rejected
  on device.
- **THE TIME SLIDE as shipped** (vertical slide on the hero). The color-time
  math survives in Spec.TimeSlide; the gesture/overlay composition does not.
  `Feature.decideTimeSlide = false` is the tested escape hatch that restores
  the pre-slide static hero byte-for-byte if wanted before the next redesign.
- **The reads-on-hero display** (`Feature.rungReadHero`) — data-gated inert
  today anyway (needs multiScaleLadder); its display composition follows the
  same rejected screen.

## Lessons (what the next session must do differently)

1. **Device-fit review BEFORE building.** The compile-only rule (sim has no
   camera) made "BUILD SUCCEEDED + lattice laws green" feel like enough. It
   is not. Any scene-level UI change needs a device look at a THROWAWAY
   mockup stage — screenshots of the real phone — before spec regions and
   widgets are built. A paper sketch on a real screen outranks eight proven
   regions.
2. **Debt budget per session.** One mechanic, landed small, device-checked,
   THEN deepened. The workflow's speed is real but it front-loads machinery;
   the next arc should cap new modules/flags per unit and require a device
   sign-off between units, not after six commits.
3. **The failure axes need gates.** "Fits the screen" and "debt borrowed"
   were never in any checklist. Add them to the device checklist
   (docs/LOOM-RUNGS-DEVICE-CHECKLIST.md style) for any UI arc.

## De-borrowing candidates (for a future cleanup decision, not now)

If the next direction abandons these mechanics, the reversible units are:
the slide gesture + rail/chip overlays in DecideHeroWidget; the playhead +
hero cache in DecideModel; `signal`/`pour` decisionScene regions (+ their
controlFaces row); Feature.decideTimeSlide / Feature.rungReadHero. The spec
modules can stay (true math, no runtime cost) or be pruned with their tests
in one commit each. The `.s4cr` v3 wire should stay regardless.
