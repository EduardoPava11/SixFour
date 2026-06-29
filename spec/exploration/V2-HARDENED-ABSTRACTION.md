# Hardening the SixFour Unification: GIF89a == (R,G,B,x,y,t) == (L,a,b,x,y,t)

A synthesis of four independent harden/skeptic passes (`gif-eq-6d`, `sixd-eq-opp`, `encoder-weave`, `dg-ant-unify`). The owner's three-way `==` is real, but it is not one isomorphism. It is a chain of three relations of three different strengths, and saying which is which is the whole point of hardening it.

---

## 1. The three-way structure (lead)

The data is a finite colour field on a discrete spatio-temporal box: a section

```
  s : Lambda_xyt  -->  Lambda_colour  subset  Z^3
      (octree lattice)   (RGB8 cube / opponent sublattice)
```

The owner's `==` decomposes into two arrows, each with its own honest strength label, plus LZW as a side channel that is not an arrow at all:

```
   [index map] + [per-frame palette] + [LZW]
            |
            |   ARROW 1:  gauge-quotiented factorization
            |   render = palette . index   (the B combinator)
            |   EXACT byte-for-byte on the (I, palettes) pair, up to the S_256 slot gauge.
            |   LZW sits OFF to the side: lossless re-coding of the index STREAM.
            v
       (R, G, B, x, y, t)
            |
            |   ARROW 2:  Z-module isomorphism onto an index-6 sublattice
            |   colour: M = [[1,1,1],[1,-1,0],[1,1,-2]],  det M = 6;  position: identity I_3
            |   EXACT byte-for-byte, invert-or-refuse on Lambda_colour.
            v
       (L, a, b, x, y, t)        L = R+G+B,  a = R-G,  b = R+G-2B
```

Per-arrow honesty labels:

| Arrow | Relation | Strength | Status |
|---|---|---|---|
| codec -> RGBxyt (SHAPE: `[index]+[LZW] -> (x,y,t)->slot`) | function, surjective-up-to-gauge | **EXACT, gated in production** | `decodedIndices dg == srcIdx` byte-for-byte, `GenTests.hs:122` |
| codec -> RGBxyt (COLOUR: `[palette] -> slot->RGB`) | function | **EXACT in sRGB8 store, LOSSY in old OKLab path** | `assembleGifRGB8` writes triples directly (GifWire.hs:122); `oklabToRGB8=round(x*255)` was the only lossy step (GifWire.hs:214) |
| LZW | bijection on `Slot*` | **LOSSLESS RECOMPUTE, not an axis** | `lawLzwRoundTrips` incl. KwKwK; `#codes <= #slots`; `P6` has 6 fields, not 7 |
| RGBxyt -> opponent (colour block) | `Z`-module monomorphism, index 6 | **EXACT, invert-or-refuse** | exhaustive 2^24 round-trip verified (5/5, ~55s fold over all 16,777,216 pixels) |
| RGBxyt -> opponent (position block) | identity `I_3` | **EXACT (trivial)** | `lawPositionIsIdentity` |
| field -> (I, palettes) | rank-<=256 restriction | **QUANTIZATION (the one real loss)** | palette cardinality: forcing a frame through <=256 colours; collapses to identity when the source is already a per-frame <=256-colour RGB8 field |

**The single honest statement.** Given a source that the V2 sRGB8-canonical contract *declares* to be a per-frame <=256-colour RGB8 field, the whole chain `decode . encode = id` is a **bijection with zero loss anywhere**. The "palette is lossy" caveat is a statement about embedding an arbitrary continuous field *into* that source type, not about the codec round-trip. Discipline to hold: the codec is a bijection on its own type; quantization is the separately-acknowledged coercion into that type. LZW never loses information and never adds a dimension; it changes the serialization length of `s`, never `s`.

**Where the `==` is weaker than "isomorphism".** Arrow 1 is observable-equivalence with a quotient: `(palette, index)` is defined only up to the `S_256` slot orbit (relabel index by sigma, palette by sigma^-1, `render` unchanged). Arrow 2 is a monomorphism of index 6, not a unimodular change of basis: the opponent coordinates do NOT range over all of `Z^3`, only the sublattice `Lambda = M(Z^3)`. So the faithful reading of the owner's `==` is: **three informationally equivalent presentations of one section, with a gauge quotient on the codec leg and a finite-index lattice embedding on the colour leg.** It is a representation-up-to-gauge, not an isomorphism of structures. Saying "isomorphism" out loud overclaims; saying "the same section in three coordinate systems" is exact.

---

## 2. The encoder role (the owner's H-JEPA question)

**The encoder is the field map `GIF89a -> P6`.** Pointwise its core already exists: `pixelP6 fr t (x,y) = let (r,g,b) = render fr (x,y) in P6 r g b x y t` (V2Gif89aAxes.hs:185) reads RGB off the palette-after-index composition, pairs it with `(x,y,t)`, and (under the corrected store) changes colour basis to the opponent triple. Per voxel it emits the 6D point `P6 (L,a,b,x,y,t)`: the higher-dimensional COLOUR (3 opponent DOF) carried at each SHAPE coordinate `(x,y,t)`. That is the "interwoven structure of shape and higher dimensions" made concrete.

**The phi6 weave.** `phi6` (Dim6.hs:48) is the involution `a<->x, b<->y, L<->t` (`lawPhi6PairsColourWithPosition`). It pairs each colour axis with its position axis, so a +/-1 nudge on search-colour `a` is the same lattice quantum as on position `x`. It is the order-2 `Z/2` automorphism that is the second factor of the gauge group `S_256 x Z/2`.

**What the encoder adds beyond the codec** (three things the GIF89a wire does not contain):

1. **A relational metric `d6`** (RelationalMemory.hs:44), the L1/taxicab norm on `Z^6`, a genuine metric (all four axioms `lawD6*`). The codec gives `render` pointwise but no way to compare two voxels; `d6` is what lets the predictor be conditioned on WHERE it predicts. `lawPositionDistinguishesSameColour` is the real I-JEPA content: force two voxels to the same colour, then `dColour == 0` (colour-only is blind) yet `d6 == 0` iff positions also match. Position carries information colour alone cannot. This is HARDENED and non-vacuous.

2. **The frozen, parameter-free lift that manufactures the target.** `encodeEmbedding = featuresB . liftOct`, `encoderParamCount == 0` (EncoderFrozen.hs). The SAME lift that defines the embedding carves a bit-exact held band (`JepaData.manufactureExample`), so `lawNoTargetEncoderNoEma` gives collapse-immunity **structurally** (nothing to EMA), not by an EMA schedule. Encoder and target are one object. The only learned thing rides ABOVE it (predictor `theta_B`, 63 params, growing to the ViT-scale `LargeJepaHead`), position-conditioned by a T5-style `d6Bias` whose base distance stays the proven integer `d6`.

3. **The phi6 symmetry of the woven metric.** `phi6` acting on the point is an exact `d6` isometry that *swaps the colour-distance summand with the position-distance summand*.

**The non-separability, stated honestly (this is where the skeptic bit hardest).** The original framing said the metric is "non-separable." That is FALSE and must be retracted: `d6 = dColour + dPosition` is additively separable (verified True over the cube). The genuine content of "interwoven" lives one level up, in the symmetry group: each summand `dColour`, `dPosition` is individually NOT phi6-invariant; only their sum is, because phi6 carries one summand exactly onto the other. A separable two-tower (colour features (+) position features) would throw the pairing away.

**The unresolved condition (do not overclaim).** The skeptic proved by counterexample that the proposed `lawWeaveIsNonSeparable` does NOT pin the *specific* pairing `a<->x, b<->y, L<->t`. Over all 531441 pairs, a WRONG pairing `phiW = a<->y, b<->x, L<->t` ALSO passes both conjuncts, because flat L1 does not care which colour axis routed to which position axis. The full isometry group of flat L1 on `Z^6` is the hyperoctahedral group `B_6 = (Z/2)^6 rtimes S_6`, which contains EVERY block-transposing signed permutation; phi6 is one undistinguished element of it. The keystone certifies "a block swap exists," not "this pairing matters." The same defect hits `lawBiasIsPhi6Consistent`: with equal weights every axis nudge is distance 1, so `1 == 1` for any pairing.

**Condition to make the pairing load-bearing:** introduce an asymmetric weight or a genuine `a`-with-`x` cross term that breaks the intra-block `S_3` symmetry. That is the same open question as the det-6 quadratic form (section 4/6). Until then, the pairing is a chosen convention sitting inside `B_6`, honest as a convention, not yet a theorem.

---

## 3. The DG + ANT unification

**The single algebraic object: a free graded `Z`-module presented as a lattice-valued section over the spatial octree, with two finite symmetry actions on top.** Let `R = Z` be the Q16 substrate ring (the `CommutativeRing` of `RefinementSystem`, deliberately NOT a field). A voxel is a point of the free rank-6 module

```
  P6  =  M_colour (+) M_pos  =  Z^3 (+) Z^3
```

and the clip is the section `s : Lambda_xyt -> Lambda_colour`. The three representations are three presentations of this one object:

- **GIF89a codec** = the factorization of `s` through a finite K=256-point set: `render = palette . index`, with the `S_256` slot relabel as gauge; LZW the lossless coder on the serialization.
- **(R,G,B,x,y,t)** = the standard basis of `P6`.
- **opponent + position** = the same module in the sublattice basis `M (+) I_3`.

**Discrete geometry (the shape).**
- `Lambda_xyt` is the octree / Morton lattice. `liftOct` realizes the reversible grading "1 coarse + 7 detail = A_7 root lattice" (`unliftOct . liftOct = id`); over the non-field ring `Z[1/2]` this is module theory (the lift never divides by the non-unit 2). The scale spine `16 -> 64 -> 256 = 2^4 -> 2^6 -> 2^8` is a descending sublattice chain carrying the only genuinely non-archimedean metric in the system (the s-adic valuation = common-prefix depth), distinct from the archimedean `d6`.
- `d6` is the L1 metric on `Z^6`; its unit ball is the cross-polytope (orthoplex); `lawUnitQuantumIsOneStep` pins the +/-1 nudge as the lattice generator.

**Algebraic number theory (the colour).**
- `Lambda_colour = M(Z^3)` is an index-6 (det 6) orthogonal sublattice of `Z^3`. The opponent axes `L=(1,1,1)`, `a=(1,-1,0)`, `b=(1,1,-2)` are mutually orthogonal in raw RGB (`L.a=L.b=a.b=0`), a genuine 2-fold Cartesian opponent frame, but NOT orthonormal (squared norms 3, 2, 6; true norms `sqrt 3, sqrt 2, sqrt 6` whose product is `6 = |det|`). The quotient `Z^3 / Lambda ~= Z/3 x Z/2` is exactly the two membership congruences `(L-b) = 0 mod 3` (the blue inverse) and `(a+b) = 0 mod 2` (the R/G parity inverse), `6 = 3 . 2`. Decode `R=(2L+3a+b)/6, G=(2L-3a+b)/6, B=(L-b)/3` is exact ONLY on `Lambda`; `6, 3, 2` are non-units of `Z` so `M^-1` is not an integer matrix, and decode is invert-or-refuse, the fundamental-domain / lattice-membership check made into code (`lawDecodeRefusesOffLattice`, teeth on both guards). This is the same "not a field" content as `RefinementSystem.lawNonUnitsHaveNoInverse`, instantiated for colour.

**Group theory (the index/palette), not Galois.** The palette is a finite set of lattice points; the index map is the lattice-valued selector. Their relabelling freedom is the NON-ABELIAN `S_256` gauge (`lawPaletteGaugeIsNonAbelian`), whose orbit invariant is the rendered image. This is invariant theory (the quotient `X/G`), explicitly NOT the cyclic Frobenius `Gal(F_256/F_2)`. It is the same sigma/sigma^-1 transport already in `Upscale256.alignSlots` / `TransportGroup`. phi6 is the order-2 second factor of the gauge group `S_256 x Z/2`.

**The honest line between structure and analogy.**
- **Genuine algebra:** "module over a ring" (`P6 = Z^6` free `R`-module).
- **Genuine shape:** "product of lattices" (`Lambda_xyt x Lambda_colour`, the graph of `s`).
- **Loose analogy, downgraded:** "fibre bundle with colour fibres." The colour module is identical over every spatial point, no transition functions, no twist, so it is the TRIVIAL bundle = product. Calling it a bundle implies absent structure.
- **Derived lens, never the store:** the Eisenstein A_2 ring `Z[omega]` (`omega^2 = -1-omega`, `1+omega+omega^2 = 0`). The hexagonal chroma `(R-B, G-B)` is recovered from the store as `Cr=(a+b)/2, Cg=(b-a)/2` (exact because `a+b = 2(R-B)` is always even, `lawEisensteinIsDerivedLens`). It is withdrawn as the store because `(R-B).(G-B) = 1 != 0`, hexagonal, NOT perceptually opponent. The gray axis `(k,k,k)` is exactly the kernel of the chroma map (the syzygy `1+omega+omega^2 = 0`, `lawGrayIsEisensteinKernel`). Its units (60-degree hue rotations) survive as analysis over the store, never as the store.

---

## 4. The keystone laws (runghc-checkable)

Four laws harden the unification. Two are verified green today; two carry explicit conditions from the skeptics.

**K1 - GIF triple reconstructs the full field (the first equivalence as ONE gated theorem).** Status: **author it.** Today the SHAPE half is gated in production (OKLab path) and the COLOUR typing is in ungated exploration; no single law states full `(R,G,B,x,y,t)` reconstruction in the sRGB8 basis. Fuse them over `assembleGifRGB8`:

```haskell
lawGifTripleReconstructsRGBxyt :: Bool
-- bytes = assembleGifRGB8 w h fps Nothing [ (flatten I_t, P_t) | t <- frames ]
-- dg    = either error id (decodeGif bytes)
--   (1) SHAPE exact:  decodedIndices dg == concat [ flatten I_t | t <- frames ]
--   (2) COLOUR exact: [ dfPalette fr | fr <- dgFrames dg ] == [ P_t | t <- frames ]
--   (3) FIELD:        and [ (dfPalette (dgFrames dg !! t)) !! (I_t (x,y)) == src (x,y,t) | (x,y,t) <- allVoxels ]
-- TEETH: clause (3) IS render = P_t . I lifted to round-tripped bytes; corrupt ONE palette
--        entry or ONE index and (3) breaks (cf. lawRenderIsBComposition, lawSixAxesFactor).
```
Condition the skeptic attached: this must run over the `assembleGifRGB8` (sRGB8) path, not the OKLab `encodeVolume` path, and a `decodeGif . assembleGifRGB8 == id` gen-test must exist (today `assembleGifRGB8`'s only callers, app/Fixtures.hs, build bytes but never decode-check them).

**K2 - opponent round-trip + xyt passthrough (the second equivalence).** Status: **VERIFIED GREEN (5/5).** This is the strongest leg.

```haskell
lawSixDRoundTrip      = all (\p -> fromOpp (toOpp p) == Just p) cube      -- full 6D point
lawPositionIsIdentity = all (\p -> let o = toOpp p in (oX o,oY o,oT o) == (cX p,cY p,cT p)) cube
lawColourBijectionExhaustive =                                            -- the 2^24 witness
  foldl' (\n px -> if decodeC (encodeC px) == Just px then n+1 else n) 0 allPx == 256*256*256
lawDetSix              = det3 [[1,1,1],[1,-1,0],[1,1,-2]] == 6
lawOrthogonalRgbNative = dot l a == 0 && dot l b == 0 && dot a b == 0
```
`toOpp = M (+) I_3`, `fromOpp = M^-1 (+) I_3` (invert-or-refuse). The exhaustive leg genuinely folds over all 16,777,216 pixels (not sampled); injectivity on the full cube upgrades "round-trips on a sample" to "is a bijection onto its image." The 6D claim follows by the direct sum: colour bijective + position identity => 6D bijective.

**K3 - the phi6 weave (the encoder interweaving).** Status: **NEEDS-CONDITION.** The metric symmetry is real and verified; it does NOT yet pin the specific pairing.

```haskell
permute6 :: P6 -> P6                              -- phi6 ACTING on the point
permute6 p = P6 (av DimL)(av DimA)(av DimB)(av DimX)(av DimY)(av DimT) where av ax = axisVal (phi6 ax) p

lawWeaveIsMetricSymmetry p q =
     d6 p q == d6 (permute6 p) (permute6 q)                 -- (1) phi6 is a d6 ISOMETRY
  && dColour   (permute6 p)(permute6 q) == dPosition p q     -- (2) swaps colour-dist onto position-dist
  && dPosition (permute6 p)(permute6 q) == dColour   p q     --     and back, exactly
  && d6 p q == dColour p q + dPosition p q                   -- HONESTY GUARD: metric IS additively separable
```
Honest weaker statement to commit beside it: *phi6 is one block-transposing element of the `B_6 = (Z/2)^6 rtimes S_6` isometry group of flat L1; the specific `a<->x, b<->y, L<->t` correspondence is not distinguished by `d6` or any present law.* Do NOT ship the false teeth claim that a wrong pairing fails conjunct (2); it does not. Condition to graduate: add an asymmetric/coupled weight breaking intra-block `S_3` symmetry, then re-test.

**K4 - the unified lattice law (all legs on one section).** Status: **NEEDS-CONDITION** (two conjuncts must be de-tautologized). The intent: render the codec, re-base to opponent, decode, recover `(R,G,B,x,y,t)` byte-exact, on the index-6 lattice, gauge-invariant under any slot permutation, and spatially reversible under the octree lift, ALL on the same field.

```haskell
lawThreeWayModuleUnification f sigma =
     codecOk   -- (1) render (palette f) (index f) == rgbField           [bites]
  && oppOk      -- (2) all (\c -> onLambda (mOpp c) && mDec (mOpp c) == c) -- ! mOpp tautologizes onLambda
  && gaugeOk    -- (3) render (permPal sigma pal) (permIdx sigma idx) == rgbField  [bites; skip iff sigma not a perm]
  && spaceOk    -- (4) octree lift round-trips every position address     -- ! singleton [x] makes liftC trivial
```
The skeptic's two patches (required before this is HARDENED): (2) `onLambda (mOpp c)` is a tautology for every integer RGB (`L-b = 3B`, `a+b = 2(R-B)`), so replace it with an off-lattice `onLambda`/refuse pair mirroring the live `V2EncodeDecodeBoundary` teeth `(1,0,0)` / `(6000,0,0)`; (4) feed a multi-voxel scanline (>=3 colinear addresses) through `liftC`/`unliftC` so the prefix-difference lift actually bites. As written, clauses (1) and (3) bite (codec + gauge fusion is real); (2) and (4) are decorative. Patch both, re-run, and if it still prints `True` the four-way fusion is genuine.

---

## 5. The unifying spec to build

One exploration file, base-only, runghc, in the V2 style (mirrors `V2EncodeDecodeBoundary` and `V2Gif89aAxes`, NOT yet in cabal/Map/gate). Trainer untouched.

**`spec/exploration/V2UnifiedField.hs`** holding the section `s : Lambda_xyt -> Lambda_colour` and all four keystones:
- `lawGifTripleReconstructsRGBxyt` (K1) over the `assembleGifRGB8` path. This is the file's headline: it is the standing OPEN item from every survey leg, and discharging it replaces "two adjacent theorems in two tiers over two colour paths" with one statement.
- `lawSixDRoundTrip`, `lawPositionIsIdentity`, `lawColourBijectionExhaustive`, `lawDetSix`, `lawOrthogonalRgbNative` (K2), ported from the verified scratchpad `V2SixDIso.hs`.
- `lawWeaveIsMetricSymmetry` + the honest weaker statement (K3), with the additivity honesty-guard baked in so the module cannot drift into falsely claiming metric non-separability.
- `lawThreeWayModuleUnification` (K4) with the two skeptic patches applied (off-lattice refuse test + multi-voxel scanline lift).

**Promotion path.** K2 is green and exhaustive: it is the first candidate to promote into a gated `Spec.*` module (e.g. `Spec.OpponentBasis`) so the second equivalence is gated rather than exploration-only. K1, once authored over `assembleGifRGB8` and backed by a `decodeGif . assembleGifRGB8 == id` gen-test, promotes the first equivalence into the production tier alongside the existing `GenTests.roundTripTests`. K3 and K4 stay in exploration until their conditions discharge (the asymmetric-weight question for K3, the two de-tautologizing patches for K4). Add a `lawLzwIsComputeNotDimension` naming LZW as compute-over-the-index-stream to forbid any future 7th-axis drift.

---

## 6. Honest gaps

**Genuinely hardened (theorems, axioms checked):**
- LZW is an exact bijection on `Slot*`, lossless, gated in production (`roundTripTests`), KwKwK pinned as the exact failure boundary. Compute, not a 7th axis. (HARDENED.)
- The opponent change of basis `M (+) I_3` is a byte-exact `Z`-module monomorphism of index 6 onto `Lambda_colour`, verified exhaustively over all 2^24 colours, invert-or-refuse off the lattice. `det M = 6`, mutually orthogonal axes, `Z^3/Lambda ~= Z/3 x Z/2`. (HARDENED, with the caveat that it is a monomorphism, not an iso of `Z^3`.)
- `render = palette . index` is genuine B-composition with non-commutativity teeth; the `S_256` slot relabel is a real non-abelian gauge with the rendered image as orbit invariant. (HARDENED.)
- `P6 = Z^6` free module; `d6` satisfies all four metric axioms; `liftOct` is a reversible module bijection (A_7 grading); `encoderParamCount == 0` with structural collapse-immunity. (HARDENED.)
- `lawPositionDistinguishesSameColour`: the real I-JEPA position-conditioning content, non-vacuous. (HARDENED.)

**Stays a loose analogy (claimed only suggestively, never as a homomorphism):**
- The S/K combinator gloss on palette = K / index = S / LZW back-reference = S-contraction. No typed homomorphism `LZW-stream -> SKI-reduction` exists; LZW sharing is data-level substring reuse, S is term-level argument duplication. The only combinator claim that IS a theorem is `render = B`.
- The "fibre bundle with colour fibres" reading. Downgrade to trivial product `Lambda_xyt x Lambda_colour` (no transition functions, no twist).
- The Eisenstein `Z[omega]` ring as "the colour ring." It is a derived analysis lens recovered as `(a+b)/2, (b-a)/2`, hexagonal `(R-B).(G-B) = 1 != 0`, never the store.
- The LZW "dictionary = latent" reading, suggestive only; not connected to the H-JEPA relational latent.

**Genuinely open (conditions, not theorems):**
- **The phi6 pairing is not yet load-bearing.** Flat L1 makes the isometry group the full `B_6`; phi6 is one undistinguished block-transposing element, and a wrong pairing passes the same law. Fix requires an asymmetric weight or a real cross term.
- **`d6` commensurability by fiat.** Equal L1 weights pin one colour LSB == one position unit with no justification; the colour factor's intrinsic form is the det-6 quadratic form, not flat L1. The basis change `M (+) I_3` is an iso of lattice POINTS, NOT an isometry (squared norms 3, 2, 6 vs position 1), so the `==` is exact as point-identity and data-bijection, FALSE as distance-equality. This is the single seam shared by the phi6 gap above.
- **The encoder as one realized arrow.** No single typed function emits the interwoven `(L,a,b,x,y,t)` latent: `pixelP6` stores raw RGB, the opponent change-of-basis lives in a separate exploration, and `encodeEmbedding = featuresB . liftOct` operates on the octree `V8 Int`, not on `P6`. The field map is a story across three files. The weave lives in the LEARNED head (phi6 + `d6` attention), by design of asymmetric I-JEPA, NOT in the frozen tokenizer, which is colour-channel-local and position-blind.
- **The P6 relabel is unhardened.** Field names and docstrings still say `(L,a,b)` / Lab; the creed's opponent reinterpretation (`L=R+G+B, a=R-G, b=R+G-2B`) is not yet reflected in `RelationalResidual.hs` / `Dim6.hs`.
- **K1 and K4 are unwritten / partly tautological.** K1 (`lawGifTripleReconstructsRGBxyt`) does not exist in the tree, and the RGB8 wire path (`decodeGif . assembleGifRGB8 == id`) is never round-trip-tested. K4 has a tautological lattice conjunct and a singleton-only spatial conjunct.

**Bottom line.** The owner's `==` is a faithful chain of three presentations of one `Z^6`-module section: a gauge-quotiented codec factorization (EXACT up to `S_256`), an index-6 lattice embedding (EXACT, invert-or-refuse), with LZW the lossless coder on the serialization and palette cardinality the one quantization. The colour and shape legs are hardened. The remaining work is structural, not mathematical: author K1 over the sRGB8 path, promote K2 (already green and exhaustive) into the gated tier, and either earn or honestly demote the phi6 pairing and the `d6` commensurability, which are one and the same open seam.