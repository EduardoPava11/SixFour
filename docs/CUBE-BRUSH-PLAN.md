# CUBE-BRUSH-PLAN — resolution-typed paint, network-constructed 64³

*The port plan for the Form-Follows-Function change (2026-07-04). Keystone spec landed:
`SixFour.Spec.CubeBrush` (semilattice stroke algebra, full-bandwidth realizability, the
regress teeth that force network construction). This doc is the change-map; each stage
names its gate.*

## The change in one paragraph

The user paints with **rung-typed brushes** — a 16-brush lays 4×4×4 spacetime cubes (in
64³ terms), a 32-brush 2×2×2, a 64-brush voxels. Strokes form a set of **overlapping
cubes**; the induced depth field is the pointwise **max** (finest wins). The pull render
is only the **floor**: inside granted cubes the **network constructs** (θ_up invention,
gated exactly like the committed W1 arm — the algebra forces this: pull-only rendering
of overlapping cubes can strictly regress, `lawOverlapPullCanRegress`). Choice
(`Spec.ChoiceTraining`) is re-scoped to taste-training on the network's proposals, not
retired. The W1 binary mask survives as the depth ≥ 1 superlevel set — an old mask IS a
cube set of depth-2 cubes, so the change is backward compatible at the gate layer.

## Stages (each lands green before the next)

- **S0 — spec keystone (DONE)**: `Spec.CubeBrush` — 6 laws incl. full-bandwidth
  realizability and the regress teeth. Gate: spec suite.
- **S1 — mask derivation**: `Spec.ModelForward` gains `masksOfField` — the nested
  per-transition invention masks as superlevel sets ({d≥1} for 16→32, {d≥2} for 32→64;
  nesting automatic from max). Gate: new laws + existing W1 laws unchanged (the binary
  path must reproduce byte-for-byte via depth-2-only cube sets).
- **S2 — brush UI**: `NudgePaintView` gains the rung selector (three brush sizes — the
  lattice channel strip pattern, committed QoL); strokes record `(depth, origin)` cubes
  Morton-side; `NudgePaintModel.deviceCubes(budget:)` replaces/extends `deviceMask`.
  Gate: PaintGateTests extended — cube strokes at depth 2 reproduce today's mask path
  bit-for-bit; commute/absorb tested on the Swift twin.
- **S3 — arm construction**: `OctantCube.expandProposal` takes the nested masks (S1)
  instead of one mask; `CurateBuilder` twin follows. Gate: GPU/CPU gated parity
  (extends the committed PaintGateTests parity), floor unchanged when no cubes.
- **S4 — decide rescope**: DecideSurface arms become (network-constructed inside cubes)
  vs (pull floor); choice taps keep their BT role on regions the user did NOT cube.
  Gate: build + the capture→decide flow sanity (device).
- **S5 — Zig/wire (later)**: `s4_render_pull` voxel-field variant if the floor render
  moves native; byte-golden vs the Haskell render. Not needed until the floor is hot.

## Decisions locked by the spec (don't relitigate in code review)

1. **Finest wins** at overlap (max, not blend) — the semilattice is what buys order-free
   strokes and trivial undo. Graded/energy blending stays design headroom (V2.1 curves).
2. **Cubes are grid-aligned** to their own rung's lattice — alignment by construction
   (the `Cube` type carries block coordinates, not pixel coordinates).
3. **The network, not the pull, fills granted volume** — forced by the regress teeth.
4. **Uncubed volume = the certified/proposed floor** (the bin data's proposal survives;
   the user's cubes override, never start from zero).

## Open (Daniel)

- Brush ergonomics: does the 64-brush exist in v1, or is voxel-level reserved for the
  network (user places 4³/2³ only)? Spec supports both; UI complexity differs.
- Does a cube grant TIME depth too (it is 4×4×4 in spacetime) or do beats get a separate
  hold gesture (YINYANG-UIUX §0)? Spec treats spacetime uniformly; UI may split.
