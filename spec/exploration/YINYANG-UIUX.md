# YINYANG-UIUX — the capture loop where inference and training are one surface

*Design doc (exploration, not wired). Derived from landed laws — every claim cites its gate.
Companion spec: `Spec.PullField`, `Spec.ChoiceTraining`, `Spec.FidelityLadder`,
`Spec.KinematicHaltPrior`, `Spec.TriScaleTraining`. 2026-07-04.*

## 0. The beat: the temporal quantum the UI is built on

One 16-rung frame = two 32-rung frames = four 64-rung frames = **200 ms** (the cadences
20/10/5 Hz over the shared 3.2 s window; `s4_ladder_delay_cs` 20/10/5 cs — GIF-exact).
So the burst is **16 beats of 200 ms**, each beat subdividable in halves and quarters —
a musical measure, not a filmstrip. The influence field is already spatiotemporal
(4×4×4 regions), so ONE gesture vocabulary covers space and time:

```
depth 0  = the beat, one look        (16-rung: 1 frame / beat)
depth 1  = the offbeats              (32-rung: 2 frames / beat)
depth 2  = the sixteenths            (64-rung: 4 frames / beat)
```

UI consequence: the timeline scrubber shows 16 beat-cells (not 64 frames). A beat
renders at its region's dominant depth; expanding a beat (pinch on the timeline) is the
temporal twin of deepening a spatial region. "Hold this moment" = spend 4 frames on the
beat; unheld beats pull to one look. Same law, both axes (`lawTemporalPullSkipsFrames`).

## 1. Should the user paint the subject? — No. The bin data proposes; the user corrects.

The post-capture UI is downstream of the bin data (FidelityLadder; ColorHead derives
everything from the 64-rung sums). The machinery already computes "the subject" without
being asked:

- **contested regions** = where the certified kinematic order hits cap (motion arithmetic
  can't explain) AND W > 1 (real conditional entropy — TriScaleTraining's skip law
  inverted). Static background certifies order 0 and W→1: it prunes itself.
- The **subject volume** is the contested set — a spacetime volume, exactly "keeping the
  detail in a volume."

So the flow is *propose → correct*, never *paint from scratch*:

1. The render shows its own field (the pixelated pop IS the visualization — coarse
   regions look coarse; no overlay, `Spec.PullField`).
2. The proposed subject arrives already deep; background already pulled.
3. **Paint = correction only**: tap-hold a region to force-deepen; tap a deep region to
   release it. This is the committed W1 gate used for its true bandwidth — paint says
   WHERE (`lawPaintUnderdeterminesDepth`: it provably cannot say how deep), and the
   correction taps are exactly WHERE-information.

The answer to "should the user paint the subject": the user should be able to *disagree
about* the subject with one tap. Making them define it is asking the low-bandwidth
channel to carry the message the sums already carry.

## 2. The decide surface: choices resolve depth (the crisp channel)

Depth questions go through the choice channel (`Spec.ChoiceTraining`):

- Arms are **regionwise splices of the three pure GIFs** (`lawMixIsRegionwiseSplice`) —
  zero re-renders per arm.
- Each question is a **single-region A/B**: the two arms are byte-identical except one
  region (`lawSingleRegionChoiceIsUnambiguous`) — shown side by side, LOOPING (it's a
  GIF; temporal depth differences are visible as motion smoothness in that region).
- **Scheduler = coarse-to-fine on questions**: ask about the highest-W contested region
  first (most entropy hangs on the answer); descend into children only where the parent
  was contested — the question tree is the octree, so the question count scales with
  genuine ambiguity, not volume (16³ regions never get enumerated).
- Two taps per region resolve it exactly (`lawTournamentIdentifiesField`); every tap
  weakly improves fidelity (`lawDeeperIsCloser` — monotone descent, so the user can stop
  ANYWHERE and hold the best render for that budget).

## 3. What the yin-yang looks like — every surface moment is both directions

```
        YIN (inference shown)                    YANG (training taken)
 ┌───────────────────────────────┐   ┌─────────────────────────────────────┐
 │ LIVE  16-rung mosaic @ 5 Hz   │   │ (pre-training: certified orders +   │
 │ = the GCT as a self-portrait; │──►│  W computed live; contested regions │
 │ contested regions shimmer     │   │  queued as tomorrow's questions)    │
 ├───────────────────────────────┤   ├─────────────────────────────────────┤
 │ CAPTURE  EngineStage beats    │   │ per-transition θ_up steps on the    │
 │ LOCK/BURST n/64/REFINE/ENCODE │──►│ free coarse=pool(fine) labels       │
 │ (already committed, QoL)      │   │ (TriScaleTraining: disjoint bits)   │
 ├───────────────────────────────┤   ├─────────────────────────────────────┤
 │ DECIDE  spliced A/B pairs,    │   │ every tap = one Bradley–Terry       │
 │ one region apart, looping     │──►│ observation (AtlasTrainer 12.4 ms); │
 │ + tap-hold paint corrections  │   │ paint taps = WHERE-labels           │
 ├───────────────────────────────┤   ├─────────────────────────────────────┤
 │ SHIP  the mixed GIF; its      │   │ the field + trained utility ride    │
 │ field visible as block sizes  │──►│ into the NEXT capture's priors      │
 └───────────────────────────────┘   └─────────────────────────────────────┘
```

The loop property (the research round's verdict, now as UX): the user never performs a
"training task." They look (live), shoot (capture), pick the better-looking loop
(decide), keep it (ship). Every one of those acts is simultaneously the training signal,
gated by exact arithmetic underneath — certified orders prune, W prunes, splices
isolate, fidelity descends monotonically. Inference is what the user sees; training is
what their seeing does.

## 4. Wireframe sketch (decide surface)

```
┌──────────────────────────────┐
│  ┌──────────┐  ┌──────────┐  │   two spliced GIFs, looping, identical
│  │  arm A   │  │  arm B   │  │   except the outlined region (auto-zoomed
│  │ ▒▒▓▓██▓▒ │  │ ▒▒▓▓██▓▒ │  │   if < 1/8 of canvas)
│  │ ▒▒[██]▓▒ │  │ ▒▒[▓▓]▓▒ │  │
│  └──────────┘  └──────────┘  │   tap either = pick (1 BT observation)
│   ●○○○  contested: 4 left    │   progress = contested regions remaining
│  ┌────────────────────────┐  │
│  │ ▁▂▁▄▁▁▂▁▄▁▂▁▁▂▄▁ beats │  │   16 beat-cells; pinch a beat = temporal
│  └────────────────────────┘  │   deepen; held beats show 4 sub-ticks
│      [ keep this one ✓ ]     │   stop anywhere: fidelity is monotone
└──────────────────────────────┘
```

## 5. What this doc does NOT decide (open, needs Daniel)

- The shimmer treatment for contested regions on LIVE (candidate: 1-cell-amplitude
  breathing at the beat rate — visible, not decorative noise).
- Whether ship-time requires the contested set to be empty (recommend: no — monotone
  descent means any stopping point is coherent; default field = certified floor).
- The gene/BT utility's persistence granularity (per-user vs per-scene-class) — MAP-
  Elites axes decision, `docs/GENE-ARCHIVE-PLAN.md`.
