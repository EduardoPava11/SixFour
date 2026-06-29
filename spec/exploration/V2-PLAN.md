# SixFour V2 — the hard pivot (direction + grounded plan)

2026-06-29. V2 is a SEPARATE model from V1 (the production OKLab H-JEPA). This doc consolidates the
pivot decision and the ordered build plan. Everything in `spec/exploration/` is EXPLORATION (base-only,
GHCi-verified, NOT in cabal/Map/gate) until a step is promoted into the production spec.

## The decision (one line)
**Drop OKLab. Work on raw GIF89a 8-bit R,G,B. Keep both lenses (discrete geometry + algebraic number
theory), with chroma in the EISENSTEIN integers ℤ[ω] (hexagonal A₂) instead of Gaussian ℤ[i].**

## What the exploration proved (the grounding — workflows wtf63akky/wrthoxpdl/w28r21avf/wpbym1x7n)
- **Eisenstein ℤ[ω] is genuine, not forced** (skeptic-confirmed): R→1,G→ω,B→ω², gray collapses to zero
  chroma (1+ω+ω²=0), the algebraic norm a²−ab+b² IS the geometric chroma length, 6 units = exact 60° hue
  rotations. More natural for 3 symmetric primaries than ℤ[i] was for OKLab's 2 axes.
- **GET:** byte-exact GIF-NATIVE — working space = storage space, no okLab↔sRGB crossing; the whole
  `Spec.CaptureFormat` Q16-vs-sRGB8 tension VANISHES. Cleaner chroma algebra. All-integer (delete colour science).
- **GIVE UP:** perceptual uniformity (the dominant cost — RGB distance ≠ perceived; loss optimises pixel
  not perceived error); honest luma vs the (1,1,1) balance axis (~39.6° apart; A₂ symmetry & true luma are
  mutually exclusive).
- **φ6 is V1-ONLY and BREAKS:** square ℤ² and hexagonal A₂ are NOT isometric (aut groups D₄ order8 vs D₆
  order12; order(i)=4 ≠ 6=order(−ω²)). The meaningful φ6 ring-exchange / "no privileged carrier" die.
  Proof: `V2DualityTest.hs` (8/8).
- **The load-bearing asset is COLOUR-RING-INVARIANT:** the reversible integer Haar lift (`RGBTLift`/`liftOct`)
  + the recursion-scheme spine (ana/cata/hylo) port to RGB byte-for-byte. Proof: `V2Hylo.hs` (3/3),
  `V2RgbEisenstein.hs` lawBalanceSearchSplitPortsToRGB.
- **SKI is notation, not power** (honest negative): GIF89a's true structure is rank-1 separability (outer
  product) + Cartesian completeness, not term rewriting. The SKI reducer (`GifSki.hs`, 7/7) is kept as the
  point-free witness, not a structural claim.
- **Downgrade flagged:** XYTLabDuality's "Balance⊣adjunction" is really a reversible iso `Quad ≅ Coarse⊕Detail`
  (no functors/counit/triangles exhibited) — rename per the anti-forced-jargon rule when V2-specifying.

## Ported into SixFour V2 (from OneSix, the colour-ring-invariant spine)
- `V2Hylo.hs` — recursion-scheme spine (ported from `OneSix.Spec.Hylo`); ana/cata/hylo + fusion/closed-form/conserve laws.
- `GifSki.hs` — SKI reducer + the (honest) GIF89a reading (ported from OneSix exploration). OneSix is NOT a
  git repo, so these are file-level ports, not a submodule.

## The proven training asset to carry over
V1's 5-hour run LEARNED (step 22k): cell +100%, value +99.8%, **detail +59.6%** (the frontier crossed
positive — real super-res invention), no collapse, on the coherent scene corpus (`scene_corpus.py`). The
scene-corpus + trainer (`train_loop.py train_persistent`) are colour-representation-agnostic at the integer
level and carry over to V2 (retarget the (L,a,b) palette target to RGB/Eisenstein).

## Ordered V2 build plan (spec-first; each step promoted from exploration only when blessed)
1. **Eisenstein colour substrate** — a production `Spec` module: ℤ[ω] as an `RModule`/`CommutativeRing`
   instance (the V2 twin of `GaussianChroma`), R→1/G→ω/B→ω², norm a²−ab+b², 6 hue units. RESOLVE the
   open ÷3 byte-exactness question (luma/chroma inverse divisibility — the real V2 risk, NOT φ6): candidate
   substrates ℤ[ω][1/2] vs scaled coords vs an explicit divisibility guard.
2. **RGB-native capture** — the palette IS RGB; ties to the just-landed `Spec.CaptureFormat` and RESOLVES its
   Q16 tension (no okLab↔sRGB crossing). Byte-exact GIF round-trip at the working-space level.
3. **Reuse the Haar lift unchanged** — `RGBTLift`/`liftOct` is colour-agnostic; the invariant spine.
4. **Relational structure = ONE-WAY conditioning** (drop φ6 bidirectional ring-exchange; keep the Balance/Search
   split as a reversible iso, renamed). Direction (colour↝position vs position↝colour) is an OPEN design choice.
5. **Per-ring metric** — ℓ¹ on the luma balance axis; ℤ[ω] hexagonal norm on chroma.
6. **Retarget the trainer** — RGB/Eisenstein palette targets; reuse `train_persistent` + `scene_corpus`.

## Next step (proposed, awaiting blessing)
Promote step 1 (the Eisenstein ℤ[ω] colour substrate + the ÷3 resolution) into the production spec as the
first V2 module. Everything else is mechanical once the colour substrate + its byte-exactness rule are pinned.
