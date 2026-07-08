export const meta = {
  name: 'haskell-bloat-audit',
  description: 'Audit the SixFour Haskell spec for bloat (orphans, test-only, superseded, Fixed/float dups) and emit a verified, ranked remediation plan — NO deletions.',
  whenToUse: 'When the ~35K-LOC Haskell spec library has accumulated unused/duplicated/superseded modules and you want a safe, evidence-backed cleanup plan before touching anything.',
  phases: [
    { title: 'Baseline', detail: 'record green build + test count + gate status as the safety floor' },
    { title: 'Map', detail: 'one mapper per module family: importer graph + bloat classification' },
    { title: 'Verify', detail: 'adversarially refute each delete/consolidate candidate (default: still needed)' },
    { title: 'Synthesize', detail: 'rank confirmed-dead by LOC, emit cabal edits + verification recipe to docs/' },
  ],
}

// ── Working dir for every agent ─────────────────────────────────────────────
const ROOT = '/Users/daniel/SixFour'
const SPEC = `${ROOT}/spec`

// ── Module families (exhaustive cover of spec.cabal exposed-modules + codegen
//    + the gen/app exes). Disjoint, so no cross-slice dedup is needed. ────────
const FAMILIES = [
  {
    key: 'core-pipeline',
    mods: ['Color','ColorFixed','Shape','Map','Indices','Gauge','StageA','QuantFixed',
           'Coverage','Collapse','Diversity','Dither','SpatialDither','GMM','Palette',
           'Significance','SignificanceFixed','Pipeline','Laws','Order','Cyclic','STBN3D'],
  },
  {
    key: 'look-nn',
    mods: ['LookNet','LookNetE','LookNetR','LookNetD','LookNetCompose','LookNetEval',
           'LookCore','Look','LookCategory','Layer','Scale','Net','AxisNet','Tensor',
           'LinAlg','Loss','SigmaDecomp','SigmaPairHead','Bottleneck16','Preference','Bures'],
  },
  {
    key: 'palette-structure',
    mods: ['SplitTree','PairTree','PairTreeFixed','Quad4','Quad4Fixed','GroupRGBT',
           'HaarRibbon','SigmaPairFixed','LeafOverride','PaletteGesture','QuartetDelta',
           'GlobalVolume','PaletteSearch','PaletteOracle','VoxelFit','FrontProjection',
           'CloudProjection','DeltaCodebook'],
  },
  {
    key: 'grid-ui',
    mods: ['Lattice','Boundary','InfluenceField','CellFiber','CellGrid','CellShapes',
           'SevenSeg','GridLayout','MovableLayout','CellMechanics','WidgetDescriptor',
           'Ownership','Display','GridScript','GridAxis','AddressPicker','PlaybackClock'],
  },
  {
    key: 'atlas-export-look',
    mods: ['AtlasBoard','AtlasMove','AtlasState','AtlasOracle','AtlasCascade','DecisionLog',
           'PreferenceUpdate','Upscale256','Loom','Obfuscation','Export','ZoneProfile',
           'LookTransfer','RedFrontEnd','CubeLut'],
  },
  {
    key: 'codegen',
    mods: ['Codegen.Swift','Codegen.Shapes','Codegen.Burn','Codegen.CoreML','Codegen.MLX',
           'Codegen.Golden','Codegen.Collapse','Codegen.PairTree','Codegen.PaletteValue',
           'Codegen.Genome','Codegen.GenomeFixed','Codegen.CloudProjection','Codegen.GridAxis'],
  },
]

// ── Schemas ─────────────────────────────────────────────────────────────────
const MAP_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['family', 'modules'],
  properties: {
    family: { type: 'string' },
    modules: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['module','loc','libImporters','codegenImporters','testImporters',
                   'reachableFromCodegen','producesArtifact','classification','recommendation','evidence'],
        properties: {
          module: { type: 'string', description: 'e.g. SixFour.Spec.Bures' },
          loc: { type: 'integer' },
          libImporters: { type: 'integer', description: 'non-test, non-self library modules that import it' },
          codegenImporters: { type: 'integer', description: 'Codegen.* or app/ modules that import it' },
          testImporters: { type: 'integer', description: 'test/Properties.* modules that import it' },
          reachableFromCodegen: { type: 'boolean', description: 'transitively reachable from app/Spec.hs codegen entry' },
          producesArtifact: { type: 'boolean', description: 'its content reaches an emitted Swift/Zig/MLX/golden file' },
          classification: { type: 'string', enum: ['LIVE','TEST_ONLY','ORPHAN','SUPERSEDED','DUPLICATE'] },
          recommendation: { type: 'string', enum: ['KEEP','DELETE','CONSOLIDATE'] },
          consolidateInto: { type: 'string', description: 'target module if CONSOLIDATE, else empty' },
          evidence: { type: 'string', description: 'concrete: importer paths, grep hits, doc/memory supersession, what breaks if removed' },
        },
      },
    },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['module','stillNeeded','reason'],
  properties: {
    module: { type: 'string' },
    stillNeeded: { type: 'boolean', description: 'true if you found ANY real consumer — defaults TRUE when uncertain' },
    reason: { type: 'string', description: 'the consumer you found, or why nothing consumes it' },
    blastRadius: { type: 'string', description: 'what edits removal forces (cabal stanzas, test modules, downstream imports)' },
  },
}

// ── Baseline: establish the green floor the plan must preserve ───────────────
phase('Baseline')
const baseline = await agent(
  `You are establishing a SAFETY BASELINE for a Haskell cleanup. Working dir: ${SPEC}.
   Run, and report exact results (do NOT change any files):
   1. \`cabal build all 2>&1 | tail -20\` — does the whole project build?
   2. \`cabal test 2>&1 | tail -30\` — how many tests, all green?
   3. \`bash ${ROOT}/scripts/verify-doc-claims.sh 2>&1 | tail -20\` — does the doc-claims gate pass?
   4. \`git -C ${ROOT} rev-parse --abbrev-ref HEAD && git -C ${ROOT} status --porcelain | head\` — current branch + cleanliness.
   Return a concise prose report: build OK?, test count, gate OK?, branch, any pre-existing failures. This is the floor any cleanup must still satisfy.`,
  { label: 'baseline', phase: 'Baseline' }
)
log('Baseline recorded; mapping module families.')

// ── Map (per family) → Verify (per candidate), pipelined ────────────────────
const MAP_PROMPT = (fam) => `You are a Haskell dead-code analyst for the SixFour spec library. Working dir: ${SPEC}.

CONTEXT — the module graph has TWO roots:
  • the codegen exe: app/Spec.hs → SixFour.Codegen.* → SixFour.Spec.*  (produces real Swift/Zig/MLX/golden files)
  • the test suite: test/Properties.*  (only proves laws — produces NO artifact)
A module imported ONLY by its own Properties.X test is "proven but never deployed" — a common bloat shape here.
CRITICAL EXCEPTION — this is a HASKELL-VERIFIED repo: a module that proves a CORE theorem/invariant is
LOAD-BEARING even with no runtime importer. Before recommending DELETE on any TEST_ONLY module, grep
${ROOT}/CLAUDE.md and docs/ for the module name AND check Codegen/*.hs for emitted references to its
exported theorem names (e.g. a "...Theorem" function stamped into generated trainer/Swift contracts).
If CLAUDE.md cites it by name, or an emitter references its proof, classify it KEEP (a proven core
theorem is the POINT, not bloat). Reserve DELETE for UI/design specs and genuinely abandoned modules.
Known structural bloat: Fixed/float pairs (Color/ColorFixed, Quad4/Quad4Fixed, PairTree/PairTreeFixed, SigmaPair/SigmaPairFixed, Quant*, Significance/SignificanceFixed) where one side is canonical; and modules the project NOTES/docs mark as superseded/retired (e.g. Bures barycenter folded, Quad4Fit folded). Check docs/ and git log for "retired"/"superseded"/"deferred".

YOUR FAMILY: ${fam.key}. Analyze EACH of these modules (prefix SixFour.Spec. unless it already starts with Codegen.):
${fam.mods.map(m => '  - ' + (m.startsWith('Codegen.') ? 'SixFour.' + m : 'SixFour.Spec.' + m)).join('\n')}

For each module gather GROUND TRUTH with grep/wc (don't trust counts — verify):
  • loc (wc -l of its src file)
  • libImporters: non-test, non-self .hs files under src/ that import it
  • codegenImporters: importers under src/SixFour/Codegen or app/
  • testImporters: importers under test/
  • reachableFromCodegen: is it transitively pulled in by app/Spec.hs's codegen chain? (does any Codegen.* it feeds actually get called in app/Spec.hs?)
  • producesArtifact: does its output reach an emitted file? (trace to a Codegen emit* call wired in app/Spec.hs, or a golden the Zig/Native tests consume)
Then classify:
  LIVE = reachable from codegen AND produces an artifact (KEEP)
  TEST_ONLY = only its Properties test imports it; no artifact (candidate DELETE)
  ORPHAN = no importers at all besides cabal listing (DELETE)
  SUPERSEDED = docs/git/memory say retired/folded (DELETE)
  DUPLICATE = a Fixed/float twin where the other is canonical (CONSOLIDATE into the canonical twin)
recommendation: KEEP / DELETE / CONSOLIDATE (+ consolidateInto). Be CONSERVATIVE — if a module underpins a LIVE module, KEEP it. Evidence must be concrete grep/path facts. Return ALL modules in your family.`

const VERIFY_PROMPT = (m, evidence) => `You are a SKEPTIC trying to REFUTE a proposed removal. Working dir: ${SPEC}.
Claim under test: module ${m} is dead/redundant and can be removed or consolidated.
Prior evidence for removal: ${evidence}

Try HARD to prove it is STILL NEEDED. Check, with grep across the WHOLE repo (not just spec/):
  • any src/ importer that itself is LIVE (reachable from app/Spec.hs codegen)
  • any reference from the iOS Swift app (incl. SixFour/Kernels/), trainer/ python, or golden fixtures
  • any mention in scripts/ gate files (verify-doc-claims.sh, gate-order.txt, regenerate.sh, lint-grid.sh)
  • whether deleting it would break \`cabal build\` (re-exported types, instance modules)
  • re-exports / instance-only modules whose import looks unused but is load-bearing
Set stillNeeded=TRUE if you find ANY real consumer OR you are uncertain. Only stillNeeded=FALSE when you are CONFIDENT nothing depends on it. Give the specific consumer found (or confirm none) and the blast radius of removal.`

phase('Map')
const mapped = await pipeline(
  FAMILIES,
  // Stage 1 — map the family
  (fam) => agent(MAP_PROMPT(fam), { label: `map:${fam.key}`, phase: 'Map', schema: MAP_SCHEMA }),
  // Stage 2 — adversarially verify this family's DELETE/CONSOLIDATE candidates
  (mapResult, fam) => {
    const candidates = (mapResult?.modules ?? []).filter(x => x.recommendation !== 'KEEP')
    if (candidates.length === 0) return { family: fam.key, modules: mapResult?.modules ?? [], verdicts: [] }
    return parallel(candidates.map(c => () =>
      agent(VERIFY_PROMPT(c.module, c.evidence), { label: `verify:${c.module.replace('SixFour.','')}`, phase: 'Verify', schema: VERDICT_SCHEMA })
        .then(v => ({ ...c, verdict: v }))
    )).then(verified => ({ family: fam.key, modules: mapResult?.modules ?? [], verdicts: verified.filter(Boolean) }))
  }
)

// ── Assemble confirmed-dead set (survived the skeptic) ──────────────────────
const families = mapped.filter(Boolean)
const confirmedDead = families.flatMap(f => f.verdicts)
  .filter(v => v.verdict && v.verdict.stillNeeded === false)
const contested = families.flatMap(f => f.verdicts)
  .filter(v => v.verdict && v.verdict.stillNeeded === true)
log(`Mapping complete. ${confirmedDead.length} modules confirmed removable; ${contested.length} contested (skeptic kept them).`)

// ── Synthesize the remediation plan ─────────────────────────────────────────
phase('Synthesize')
const planInput = JSON.stringify({
  baseline,
  confirmedDead: confirmedDead.map(x => ({ module: x.module, loc: x.loc, classification: x.classification,
    recommendation: x.recommendation, consolidateInto: x.consolidateInto, blastRadius: x.verdict.blastRadius, reason: x.verdict.reason })),
  contested: contested.map(x => ({ module: x.module, classification: x.classification, reason: x.verdict.reason })),
}, null, 2)

const plan = await agent(
  `You are writing the SixFour Haskell bloat remediation plan. Working dir: ${ROOT}.
   Inputs (baseline + skeptic-confirmed removable modules + contested ones the skeptic spared):
   ${planInput}

   Write a markdown plan to ${ROOT}/docs/HASKELL-BLOAT-AUDIT.md with:
   1. ## Summary — current footprint (231 files / ~35K LOC), total LOC reclaimable, # modules to delete vs consolidate.
   2. ## Safety floor — the baseline (build/test/gate) every step must preserve.
   3. ## Remediation, tiered safest-first:
        Tier 1 ORPHANS — zero importers, delete outright.
        Tier 2 SUPERSEDED — docs/git confirm retired.
        Tier 3 TEST_ONLY — proven-but-undeployed; deleting drops the module + its Properties test.
        Tier 4 DUPLICATE — consolidate each Fixed/float twin into the canonical one (name the canonical, list call-sites to repoint).
      For EVERY item give: module, LOC, exact \`spec.cabal\` edits (which exposed-modules line + which test-suite other-modules line to remove), the .hs files to delete, and downstream import edits.
   4. ## Verification recipe — after each tier: \`cabal build all && cabal test && bash scripts/verify-doc-claims.sh\` must stay green; note the expected test-count delta.
   5. ## Contested / KEEP — modules the skeptic spared, with the consumer that saved them (do NOT touch).
   6. ## Suggested execution — recommend a worktree-isolated follow-up workflow, one branch per tier, gate after each.
   Be precise and conservative: never propose deleting anything in the contested list. After writing the file, return a 10-line executive summary (LOC reclaimable, counts per tier, top 5 biggest wins).`,
  { label: 'synthesize-plan', phase: 'Synthesize' }
)

return { baseline, confirmedDeadCount: confirmedDead.length, contestedCount: contested.length, planDoc: 'docs/HASKELL-BLOAT-AUDIT.md', summary: plan }
