export const meta = {
  name: 'layered-acts-screenmap',
  description: 'DESIGN-ONLY: review HOW Haskell builds the spec (the FLAT FSM that caused the clutter), design a LAYERED spec — act → few decisions → surfaces — define each act with FEW decisions, and MAP the cell-grid screen real estate (data-shapes vs the few touch surfaces + their gestures). The cell grid limits touch surfaces; gestures + shapes surface the richness. Writes a design doc + screen map. No code.',
  whenToUse: 'When a flat spec has produced a cluttered UI and you need to add a spec LAYER below the phase (per-act decisions) and map the screen so form follows the layered function.',
  phases: [
    { title: 'Ground', detail: 'spec-layering reviewer (why flat→clutter) + screen-geometry cartographer (the cell lattice) + gestures/shapes inventory (surface info without buttons)' },
    { title: 'Design', detail: 'the layered Haskell spec (act→few decisions→surfaces) + per-act decision sets (FEW each) + the cell-region screen map per act' },
    { title: 'Review', detail: 'adversarial: are decisions truly FEW per act (count them)? does the map FIT the cells? is the layering a real Haskell structure? enough info via gesture+shape without buttons?' },
  ],
}

const ROOT = '/Users/daniel/SixFour'
const SPEC = `${ROOT}/spec`

// ── Phase 1: GROUND ─────────────────────────────────────────────────────────
phase('Ground')
const lenses = [
  {
    label: 'ground:spec-layering',
    prompt: `You are the SPEC-LAYERING reviewer. Working dir: ${SPEC}. THESIS to test (the user's): "the LACK OF LAYERS in the spec is what delivered the cluttered app." Investigate HOW Haskell currently builds the spec and how it SHOULD layer it.
    1. Regenerate + read the map: \`bash ${SPEC}/scripts/spec-docs.sh 2>&1 | tail -15\`; read src/SixFour/Spec/Map.hs.
    2. Read Spec.Display (the phase FSM — phases/events/δ/laws) and docs/SIXFOUR-SPEC-METHODOLOGY.md (the Haskell-as-spec depth ladder). DIAGNOSE: the FSM layers the PHASES (Live→…→Review) but is there ANY spec layer BELOW the phase — i.e. does the spec define, per act, the SMALL SET OF DECISIONS the user makes in that act? Show that it does NOT (that's why Review could accrete 8 co-equal buttons — nothing in the spec bounded the per-act decision set).
    3. Read Spec.CellMechanics (the interaction algebra — lifetime FSM, detent, gestures) + how it relates to Display. Is there a layer connecting (phase) → (the decisions/affordances available in that phase)?
    4. DESIGN the missing layer in Haskell terms: how should the spec express "an Act has a FEW Decisions, each bound to a Surface (touch/gesture/shape)"? Propose the Haskell structure — e.g. a per-phase \`decisions : Phase -> [Decision]\` with a law bounding the count, a \`Decision\` algebra (what it changes), and \`surface : Decision -> Surface\` (Tap | Drag | Swipe | LongPress | Shape) — golden-pinned + codegen-able to Swift so the UI CANNOT exceed the spec's decision set. Draft the key types/laws.
    Return: the diagnosis (flat→clutter, with evidence), and the drafted LAYERED spec structure (Decision/Surface algebra + the per-act bound law).`,
  },
  {
    label: 'ground:screen-geometry',
    prompt: `You are the SCREEN-GEOMETRY cartographer. Working dir: ${ROOT}. Map the cell-grid SCREEN REAL ESTATE precisely.
    Read SixFour/UI/GlobalLattice.swift + spec/src/SixFour/Spec/Lattice.hs (the 4pt atom, the column/row count of the full screen — e.g. cols=safeWidth/4, rows=safeHeight/4 — and the cell-count constants), the placement primitives (View.place / GridLayoutContract / Spec.Boundary the rounded safe region), and how the movable triad (Field64 64², Palette16 16², DiversityRing 20²) occupies space.
    Report, in CELLS (the 4pt atom): the total usable grid (cols × rows), the safe/rounded boundary, the footprints already claimed (hero 64², palette 16², shutter, gauge, action row, status), and HOW MUCH FREE real estate remains. Produce a coarse ASCII map of the screen grid with the major regions labelled. This is the canvas the per-act screen map must fit within — give exact cell numbers.`,
  },
  {
    label: 'ground:gestures-shapes',
    prompt: `You are the GESTURES + SHAPES inventory. Working dir: ${ROOT}. PRINCIPLE (the user's): "the cells constrain the user to a FEW touch surfaces, but with GESTURES and SHAPES we can surface a LOT of information for the user to play with." Inventory the levers for surfacing richness WITHOUT adding buttons.
    Read Spec.CellMechanics + SixFour/UI/Components/CellDetent.swift (the frame-locked detent), the gesture handlers (MovableColorWidget liftDrag, LivePhaseField lookSwipe, ReviewPhaseField .cellDetent sliders, PaletteCloudView orbit), and the cell RENDER MODES (CellSprite/CellField — how a cell→colour by mode at 20fps: GIF field, 16² palette, cloud, treemap, the data-coloured field).
    Report two inventories: (A) GESTURES available on a touch surface — tap, drag (→ frame-locked detent), horizontal swipe, long-press-lift, orbit — and what each can CONTROL. (B) SHAPES / render-modes available to SURFACE information passively — the 64² field, the 16² palette, the cloud, treemap, brightness/recede overlays, the influence field, gauges — and what each can SHOW. The goal: a small palette of {gesture × shape} primitives the design can compose so FEW touch surfaces carry MUCH information.`,
  },
]
const grounding = await parallel(lenses.map(l => () => agent(l.prompt, { label: l.label, phase: 'Ground' }))).then(r => r.filter(Boolean))
const BRIEF = `SPEC-LAYERING (flat→clutter + the missing layer):\n${grounding[0] ?? ''}\n\nSCREEN GEOMETRY (the cell canvas):\n${grounding[1] ?? ''}\n\nGESTURES + SHAPES (surface richness without buttons):\n${grounding[2] ?? ''}`
log('Spec layering + screen geometry + gesture/shape palette grounded; designing the layered acts + screen map.')

// ── Phase 2: DESIGN ─────────────────────────────────────────────────────────
phase('Design')
const DESIGN_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['layeredSpec', 'acts', 'screenMap', 'gestureShapeMapping', 'haskellDraft', 'decisions'],
  properties: {
    layeredSpec: { type: 'string', description: 'the new spec LAYER below the phase: act → few decisions → surface, and the law bounding decisions-per-act' },
    acts: { type: 'array', description: 'each act with its FEW decisions', items: {
      type: 'object', additionalProperties: false, required: ['act', 'decisions', 'completion'],
      properties: {
        act: { type: 'string' },
        decisions: { type: 'array', items: { type: 'string', description: 'one decision, with its surface: Tap/Drag/Swipe/LongPress/Shape' } },
        completion: { type: 'string', description: 'the single action that completes the act' },
      } } },
    screenMap: { type: 'string', description: 'the cell-region allocation per act — an ASCII map per act labelling which cell regions are the data-shapes (surface info) vs the few touch surfaces (+ their gestures), with cell counts that FIT the grid' },
    gestureShapeMapping: { type: 'string', description: 'which {gesture × shape} primitive carries each act\'s information/decisions — richness via gesture+shape, not buttons' },
    haskellDraft: { type: 'string', description: 'drafted Haskell for the layered spec: the Decision/Surface algebra, decisionsFor : Phase -> [Decision], the bound law, codegen sketch' },
    decisions: { type: 'array', items: { type: 'string' }, description: 'open decisions for the user' },
  },
}
const design = await agent(
  `You are the LAYERED-ACTS DESIGNER. Working dir: ${ROOT}. Apply the user's architecture: the FLAT spec caused the clutter, so add a spec LAYER (act → FEW decisions → surface), define each act with few decisions, and MAP the screen so the cell grid's few touch surfaces + gestures + shapes carry the richness (NOT buttons).
   GROUNDED BRIEF:\n${BRIEF}\n
   Produce: (1) layeredSpec — the Haskell layer below the phase + the law bounding decisions-per-act (propose a hard cap, e.g. ≤3); (2) acts — each act (Live/Capture/[Browse]/Render/Review) with its FEW decisions, each bound to a surface (Tap/Drag/Swipe/LongPress/Shape) + the single completion action; (3) screenMap — a per-act ASCII cell-region map (data-shapes vs touch surfaces + gestures) with cell counts that FIT the grounded grid; (4) gestureShapeMapping — the {gesture × shape} primitive carrying each act's info; (5) haskellDraft — the Decision/Surface algebra + decisionsFor + bound law + codegen sketch; (6) open decisions. RUTHLESS on decision count: if an act has >3 decisions, justify or merge. Honour the cell-field law + the completion-criterion principle. DESIGN ONLY.`,
  { label: 'design:layered-acts', phase: 'Design', schema: DESIGN_SCHEMA }
)

// ── Phase 3: REVIEW (adversarial) ───────────────────────────────────────────
phase('Review')
const review = await agent(
  `You are an ADVERSARIAL reviewer. Working dir: ${ROOT}. Attack this layered-acts + screen-map design.
   DESIGN:\n${JSON.stringify(design, null, 2)}\n
   Check HARD: (1) Are decisions truly FEW per act — COUNT them; does any act exceed the cap; is the cap honest or are decisions hidden inside "one" decision? (2) Does the screen map actually FIT the grounded cell grid (add up the cell regions per act — do they overflow cols×rows or the rounded boundary)? (3) Is the layered spec a REAL Haskell structure that codegens to a Swift constraint (so the UI literally cannot exceed the decision set), or is it prose dressed as a spec? (4) Do gestures+shapes genuinely surface the needed information, or did the design quietly re-introduce buttons / need a tap target the cells can't host (≥11×11 touch floor)? (5) Does it LOSE capability vs today? List concrete problems + a verdict (sound / needs-rework / over-constrained).`,
  { label: 'review:adversarial', phase: 'Review', schema: {
      type: 'object', additionalProperties: false,
      required: ['decisionsFew', 'mapFits', 'specIsReal', 'gesturesSufficient', 'verdict', 'problems'],
      properties: {
        decisionsFew: { type: 'boolean' }, mapFits: { type: 'boolean' }, specIsReal: { type: 'boolean' },
        gesturesSufficient: { type: 'boolean' },
        verdict: { type: 'string', enum: ['sound', 'needs-rework', 'over-constrained'] },
        problems: { type: 'array', items: { type: 'string' } },
      } } }
)

// ── Write the design doc ────────────────────────────────────────────────────
phase('Design')
const doc = await agent(
  `Write ${ROOT}/docs/SIXFOUR-LAYERED-ACTS-AND-SCREEN-MAP.md — the layered-spec + few-decisions-per-act + screen-real-estate-map design.
   DESIGN:\n${JSON.stringify(design, null, 2)}\n
   ADVERSARIAL REVIEW:\n${JSON.stringify(review, null, 2)}\n
   Sections: ## Diagnosis (flat spec → cluttered app, with evidence), ## The missing spec layer (act → few decisions → surface, the Haskell structure + the decisions-per-act bound law, with drafted Haskell), ## The acts (each with its FEW decisions + surfaces + completion), ## Screen real-estate map (per-act ASCII cell maps that FIT the grid — data-shapes vs touch surfaces + gestures, with cell counts), ## Gesture × shape palette (how few touch surfaces carry the richness), ## Adversarial review + resolutions, ## Open decisions, ## First implementation slice (spec-first: the layered spec before any UI). End with an executive summary. Keep the cap on decisions-per-act central. This workflow implemented NOTHING.`,
  { label: 'design:doc', phase: 'Design' }
)
return { doc: 'docs/SIXFOUR-LAYERED-ACTS-AND-SCREEN-MAP.md', verdict: review?.verdict, decisionsFew: review?.decisionsFew, mapFits: review?.mapFits, summary: doc }
