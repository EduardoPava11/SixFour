# REVIEW: The Latent Storage Basis Decision

## 1. The verdict

**Store the perceptual opponent basis as the latent: L = R+G+B, a = R-G, b = R+G-2B. Decode with /6 on R and G, /3 on B, guarded by the refuse test (L-b) ≡ 0 (mod 3) AND a+b even. Do not store G-B.**

If the owner prefers a container with no chroma chart baked in at all, the equivalent-or-cleaner fallback is **RGB-direct storage** (det 1, zero refusal) with the opponent decomposition as the canonical surfaced view. Both options put zero green-blue on disk and make red-green / yellow-blue the basis the model reasons in and the user sees. The choice between them is the only thing left for the owner to decide, and I lay it out in section 6.

What I am explicitly **not** recommending: keeping (R-B, G-B) as the stored latent. Position B headlines "keep Eisenstein as storage," which is the exact G-B byte the owner has rejected twice, and its own advocate concedes the only Eisenstein-exclusive asset (the integer hue-rotation operator) has no wired caller and that byte-exactness does not discriminate. With both pillars gone there is no surviving reason to keep G-B on disk. Position B is dismissed.

The reason the verdict is clean: byte-exactness, the one hard constraint that could have forced a retreat to Eisenstein, **does not distinguish the bases**. All 16,777,216 real sRGB8 pixels round-trip integer-exact through opponent storage, verified exhaustively, not sampled. The forward map is integer and injective (det 6 != 0), so byte-exactness is structural, not a lucky property of the divisor. The owner's stated priority therefore has no counterweight.

## 2. The real tension, resolved

The owner named the tension precisely and it is real: opponent colour is a **2-fold Cartesian** structure (luma PERP red-green PERP yellow-blue, the shape CIELab encodes), while Eisenstein ℤ[ω] is a **3-fold hexagonal** structure (R, G, B symmetric at 120 degrees). These are genuinely exclusive on exactly one point, confirmed by exact-fraction computation, not assertion:

- The opponent axes are provably orthogonal: L·a = 0, L·b = 0, a·b = 0. A rectangular unit cell **cannot carry order-6 symmetry**. So the 60-degree hue-rotation operator cannot be an integer matrix in the opponent chart. In opponent coordinates the ℤ[ω] unit (the RGB channel cycle) is [[-1/2, 1/2], [-3/2, -1/2]]: it carries halves. In the Eisenstein chart it is [[-1, 1], [-1, 0]], integer.

That is the whole of the exclusivity. It is narrower than "perceptual vs hue algebra," and three verified facts shrink it to nearly nothing in practice:

1. **Hue rotation of real data stays byte-exact in opponent coordinates anyway.** Every chroma point from integer RGB satisfies a+b even (a+b = 2·Cr). On those points the half-integer operator returns exact integers (tested, zero non-integer outputs). The halves bite only on odd-parity triples that are not reachable chroma. What is non-integer is the operator *matrix as written*, not its result on data.
2. **The trainer hot path never invokes it.** lattice_loss and closest_lambda use only vector add (eadd), the quadratic norm (enorm), and decode. The integer ring-multiply (emul) appears only in law-checks and GaussianChroma.rotateChroma. The training runtime does not depend on an integer ω-matrix.
3. **Eisenstein is not perceptually opponent.** (R-B)·(G-B) = 1, a 60-degree hexagonal frame. The prior defence of Eisenstein "on perceptual grounds" does not survive the arithmetic: it is the one of the two bases that is *not* opponent.

So the model serves opponent colour, which is what the owner perceives and surfaces, and pays for it only in an integer operator matrix that no wired path calls and that is unnecessary for exact hue rotation of actual data. The exclusivity is real; its cost is not load-bearing.

## 3. The corrected three-layer architecture

**Layer 1 - Boundary (unchanged): sRGB 8-bit.** Encode in, decode/export out, at 16^3 and 256^3. Not in dispute.

**Layer 2 - Latent storage (corrected): opponent (L = R+G+B, a = R-G, b = R+G-2B), det 6.**

Byte-exact decode, integer adjugate over divisor:

- R = (2L + 3a + b) / 6
- G = (2L - 3a + b) / 6
- B = (L - b) / 3   (note: B reduces to /3; the kernel should use the /3 path for blue and /6 only for R, G)

Refuse predicate for an arbitrary integer triple not produced by a real pixel: valid iff (L - b) ≡ 0 (mod 3) AND a+b even (a ≡ b mod 2). This refuses 5/6 of arbitrary integer triples versus Eisenstein's 2/3. It never fires on a captured pixel. It governs only direct latent edits (e.g. nudge deltas) that land off-lattice, which snap-or-reject through the same machinery Eisenstein already ships, just with a denser predicate.

Sign convention to confirm before wiring: positive b = yellowward (yellow = R+G), negative b = blueward; positive a = redward, negative a = greenward.

**Layer 3 - Views.** The opponent axes ARE the storage, so red-green and yellow-blue are read straight off the bytes with no derivation. The Eisenstein / ℤ[ω] hexagonal lattice, if kept at all, is demoted to an on-demand analysis lens computed from the store for the rare case a literal integer order-6 operator is wanted. It is delete-by-default: retain it only if a specific wired path is shown to need an integer ω-matrix at storage time. The grep is the gate. If emul has no caller outside law-checks and rotateChroma, drop the lens; if rotateChroma is wired, route its rotation through the RGB round-trip (exact on the a+b-even parity).

## 4. What changes in the corpus

The headline: **the ANT does not live in the coordinates, it lives in the lattice.** The opponent chart and the Eisenstein chart are the same hexagonal A2 plane, an index-2 relabelling of one lattice (a = Cr-Cg, b = Cr+Cg, the map M = [[1,-1],[1,1]], det 2). So the intrinsic facts survive in any chart: norm-multiplicativity, positive-definiteness and hue-invariance of the loss, the 6 hue rotations as geometric isometries, and the hexagonal packing.

Re-coordinatizing, file by file:

- **trainer/mlx/eisenstein.py** survives nearly intact. The hot path (lattice_loss, closest_lambda) calls only eadd + enorm + decode. enorm rewrites in opponent coords as (3a^2 + y^2)/4: diagonalized (the perceptual-orthogonality bonus, no cross term), anisotropic 3:1, same geometry up to scale, so training behaviour is identical, only the arithmetic differs. Decode picks up the /6 and /2 alongside /3. emul is not on this path.
- **V2EncodeDecodeBoundary.hs**: re-coordinatize encode/decode to the /6 forward and the two-part refuse guard. Byte-exactness holds (verified exhaustively).
- **V2EisensteinPrime.hs**: the single-ramified-prime narrative changes. Index 3 = the one ramified ideal (1-w), N(1-w)=3, byteExact = F_3 reduction, **splits** into index 6 = ramified-3 × inert-2 (the extra factor 2 is exactly the prime that is inert in ℤ[ω], N=4). The clean one-prime story muddies. This is a derived-analysis fact now, not a storage guard.
- **V2A2ClosestPoint.hs**: the global-minimum exhaustiveness proof **breaks outright** at index 6. lawClosestIsMinimal rests on "a single luma ±1 step always re-enters Lambda," true at index 3. At index 6, opponent chroma (1,0) never re-enters Lambda by any pure-luma move (the /3 and the parity congruence are independent), so a chroma move is forced and the "min cost <= 1" guarantee collapses. If closest-point is run on an Eisenstein lens computed from the store, this is a non-issue; if it must run on stored opponent coords, it is a genuine loss.
- **V2TrainingLattice.hs**: units survive as a vector list {(1,1), (-1,1), (0,-2), ...}, all integer in opponent coords (all in the a+y-even sublattice). What does not survive is emul-as-integer: applying a unit as a hue rotation carries halves.
- **GaussianChroma.hs (rotateChroma)**: the only spec path that applies an integer ω-matrix. Either route it through the RGB round-trip or keep a thin Eisenstein analysis lens solely for it.

**Net on the ANT:** the lattice/ring structure survives as a **derived analysis layer** computed from the opponent store. What is retired as a *storage-primary* guarantee is the integer-clean writing: the /3 byte-exact guard (becomes /6-with-parity), the single-ramified-prime story (becomes ramified-3 × inert-2), and the closestLambda global-min proof. These were proofs about the storage *chart*, not about capture, store, loss, or decode correctness, and not about the colour the owner sees.

## 5. Honest note

The technical error: the prior position defended (R-B, G-B) "on perceptual grounds" after the owner corrected it twice, but (R-B)·(G-B) = 1, so Eisenstein is a 60-degree hexagonal frame and is not perceptually opponent. The defence was arithmetically false. The fix: opponent (R-G, R+G-2B) is the only one of the two bases with mutually orthogonal luma / red-green / yellow-blue axes, it is fully byte-exact over all 16.7M sRGB8 pixels, and it makes the green-blue axis the owner rejected disappear from the representation entirely. It becomes the stored latent.

## 6. Open questions for the owner

1. **Storage literal vs container.** Do you want the bytes on disk to literally be (L, R-G, R+G-2B) (opponent storage, det 6, the verdict above), or a neutral RGB-direct container (det 1, zero refusal, integer channel-cycle hue op) with opponent as the canonical surfaced view? Both eliminate G-B and make opponent primary. Opponent-literal is the strict reading of your request; RGB-direct is engineering-cleaner (no refuse path, no apparatus loss) if you accept "opponent is the primary view" rather than "opponent is the bytes."
2. **Off-lattice refusal density.** Opponent refuses 5/6 of arbitrary integer (L,a,b) triples vs Eisenstein's 2/3. This matters only if the nudge UI proposes raw integer (L,a,b) deltas rather than re-projecting edits through RGB. Do nudges move in integer opponent steps, and is the denser snap-or-reject acceptable? (RGB-direct storage makes this question vanish: zero refusal.)
3. **The integer 60-degree hue operator.** Does any current or planned kernel apply hue rotation as an integer latent matrix at storage time? If the grep over emul comes back clean outside law-checks and rotateChroma, the Eisenstein lens has no caller and should be deleted, leaving zero Eisenstein in the build. Name the call site if one exists; that is the only place opponent storage costs you, and even there the RGB round-trip recovers exactness.
4. **Retiring the ANT proofs as storage guards.** Storing opponent retires the single-ramified-prime (1-w) narrative and the closestLambda global-min guarantee in favour of index 6 = ramified-3 × inert-2. They survive as a derived analysis layer on an Eisenstein lens. Confirm that is acceptable, or confirm closest-point may be computed on the lens rather than on stored coordinates.
5. **Luma and sign polarity.** Keep L = R+G+B unweighted (any perceptual weighting breaks the integer orthogonality and the byte-exact lattice), and confirm positive b = yellowward / negative = blueward, positive a = redward / negative = greenward, before wiring.