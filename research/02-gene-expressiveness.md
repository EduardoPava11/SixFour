# 02 — Expressiveness of the Gene / Genome Representation

*A cited literature review + design brief for SixFour's σ-pair genome over a bijective octree.*

**Abstract.** This brief surveys the PhD-level literature on how much a genetic encoding can *express* — from program-representation genetic programming through indirect/developmental encodings, the genotype–phenotype map and neutrality, hypernetworks and steerable latent codes, to invertible-representation and description-length theory — and maps each thread onto SixFour's shareable **384-DOF σ-pair genome** reconstructing a 256-leaf palette over a **bijective octree** code. The central finding: the literature strongly supports a *compositional, generator-based* encoding as the expressive sweet spot, but SixFour's non-negotiable golden-gate (Haskell-verified, byte-exact across Swift/Metal/Zig) rules out the *opaque* indirect encodings that buy the most compression — so the design target is a **verifiable indirect encoding**: expressiveness through algebra of generators and neutrality, not through an uninspectable developmental black box.

---

## 1. Framing for SixFour — what "expressive enough" means here

SixFour's encoding is unusual in the space of evolutionary/generative encodings because it carries a **hard verifiability constraint** that most of the literature never has to satisfy. Three structural facts frame the whole question:

1. **The genome is a generator set, not a phenotype.** The shareable object is 384 degrees of freedom (3×128 "σ-pair generators") that *reconstruct* a 256-colour palette living in a 768-real flat leaf space (256·3). This is already an *indirect* encoding in the Stanley–Miikkulainen sense (§2.2): the genotype (384) is smaller than the phenotype it specifies (768), and the map from one to the other is a fixed reconstruction rule. Expressiveness here is the question *"which of the 768-real palettes are reachable from the 384-DOF generator manifold, and how regular/blendable is that manifold?"*

2. **The substrate is a bijective octree code.** In `Spec.OctreeGenome`, a genome is the octant-ladder code `([Int],[[Detail]])` — a coarse value plus finest-first detail bands — with `lawGenomeRoundTrip` proving `octantSynthesize ∘ octantDistill = id`. Scale counts are *derived laws*, not free parameters: `octreeLeafCount d = 8^d`, `octreeNodeCount d = (8^d − 1)/7`. This is a *normalizing-flow-grade* property (§2.5): the lift/unlift are exact bijections, so no phenotype is unreachable *for representational reasons* — everything the leaf space can hold, the code can address. The `zeroGenome == floor` contract (`lawZeroGenomeIsFloor`) means the identity/empty genome is the deterministic Zig Q16 floor.

3. **The golden gate is the ceiling on expressiveness.** Any new axis of expressiveness must stay **Haskell-verifiable and byte-exact** across the Swift/Metal/Zig ports (golden-gated). "Expressive" must never collapse into "opaque." This is the constraint that flips the usual GP/neuroevolution cost-benefit: the field's most compressive encodings (CPPN/HyperNEAT, GRNs, L-systems — §2.2) achieve regularity precisely by being *developmental black boxes* whose genotype→phenotype map is a nonlinear simulation. SixFour cannot ship that map unless it is itself golden-gateable.

So **"expressive enough"** for SixFour has a precise operational meaning: *the 384-DOF generator manifold should cover the set of palettes that real 64-frame captures actually demand, its reachable set should be robust (neutral) enough to be evolvable in a swap economy, and its composition operations (blend/compose genes) must be closed under the octree bijection so byte-exactness survives.* The rest of this brief measures each literature thread against those three tests.

---

## 2. Literature survey

### 2.1 Program-representation genetic programming — expressiveness vs. searchability

The founding tension in the field is that **more expressive program representations enlarge the reachable phenotype set but degrade the searchability (locality) of the encoding.**

- **Cartesian Genetic Programming (CGP).** Miller & Thomson developed CGP from a method for evolving digital circuits (1997); the name appeared in 1999 and it was generalised in 2000 [1]. CGP encodes a program as a **directed graph over a 2-D grid of nodes** using a simple integer genotype. Its defining property for our purposes is a **highly redundant genotype–phenotype mapping** — genes can be *non-coding* — which is the source of its neutral drift and, per the ACM Computing Surveys review of CGP variants, a mechanism repeatedly linked to its search performance [1][2]. Self-modifying and modular CGP extend expressivity toward iteration/recursion [1].

- **Grammatical Evolution (GE).** Introduced by Ryan, Collins & O'Neill (1998) and booked by O'Neill & Ryan [3], GE maps a linear integer genome to a syntactically valid program through a **BNF grammar**, so "changing the grammar radically changes behaviour" — the grammar *is* the expressiveness dial. But GE's genotype–phenotype map is a documented cautionary tale: it is **strongly non-uniformly redundant** (some phenotypes have vastly more genotypes than others, with a bias toward small trees) and has **low locality** (small genotype changes cause large phenotype jumps), which hurts mutation-based search relative to standard GP [4]. Repairs — Position-Independent GE (πGE) and **Structured GE (SGE)**, which imposes a *one-to-one* genotype↔non-terminal mapping to remove redundancy and raise locality — are exactly the "make the map better-behaved" moves [4].

- **PushGP / Push.** Spector's Push language (2001) is the expressiveness extreme: **syntactically unconstrained** (the only rule is balanced parentheses), stack-per-type, able to express arbitrary control structures including conditionals, recursion, iteration, and even self-modifying/autoconstructive programs [5]. Push buys maximal expressive power at the cost of a wild, hard-to-verify phenotype space — the opposite pole from a golden-gated encoding.

**Lesson for SixFour.** The GE literature is the sharpest warning: an indirect map that is non-uniformly redundant and low-locality is *expressive but not evolvable*. SixFour's octree code is the anti-GE — its map is a **bijection** (uniform, zero redundancy, `lawGenomeRoundTrip`), so it has ideal locality *at the code level*. The σ-generator layer sits above that and is where redundancy/locality must be watched.

### 2.2 Indirect / generative / developmental encodings — buying regularity and compression

The canonical reference is **Stanley & Miikkulainen, "A Taxonomy for Artificial Embryogeny," *Artificial Life* 9(2):93–130, 2003** [6] (fetch blocked HTTP 403 at MIT Press; corroborated via the Neuroevolution and taxonomy secondary indexes [6a]). Its thesis: **indirect (developmental) encodings reuse the same genes many times when building a phenotype, and that gene reuse is what lets a compact genotype encode a very complex phenotype.** The taxonomy places any embryogenic system on ~five continuous dimensions (including cell fate and connection targeting) and splits the field along a *grammatical* vs. *cell-chemistry* axis.

The concrete instances:

- **CPPNs (Stanley, "Compositional Pattern Producing Networks: A Novel Abstraction of Development," *Genetic Programming and Evolvable Machines* 8:131–162, 2007)** [7]. A CPPN is a network *of composed functions* (sine, Gaussian, linear, sigmoid, …) queried at phenotype **coordinates** — it maps genotype directly to phenotype geometry *without local interaction* (each phenotype component is determined independently). Composition of these primitives natively encodes **symmetry** (a symmetric function), **repetition** (a periodic function like sine), and **repetition-with-variation** (periodic composed at multiple scales). A small CPPN thus generates a large, regular phenotype — the compression is the point [7].
- **HyperNEAT** evolves a CPPN to *paint the weights of a much larger ANN*, "compactly encoding large ANNs with small genomes" and letting the phenotype be re-sampled at higher resolution after training [8].
- **L-systems (Lindenmayer, 1968)** are parallel string-rewriting grammars — successively replacing symbols by productions to grow self-similar branching structures; the standard developmental/grammatical encoding, widely coupled to GAs for plants and (recently) scalable NN evolution [9].
- **Gene Regulatory Network (GRN) encodings** model development as a network of interacting "genes/proteins" whose dynamics produce the phenotype; linear genomes (e.g. GReaNs) impose no size restriction and have been used to grow multicellular creatures, ANNs and spiking nets, with recent *differentiable* GRNs making the regulatory map learnable [10].

**The buy and the bill.** Every one of these buys compression + regularity + resolution-independence through a *nonlinear, iterated genotype→phenotype simulation*. That is precisely the thing SixFour cannot ship as an opaque map. But note the CPPN sub-case: a CPPN's map is *feed-forward and functional* (no iteration, no local interaction) — which makes it the **most golden-gateable** of the developmental encodings and the obvious candidate to study for SixFour (§4).

### 2.3 Genotype–phenotype map, evolvability & neutrality

The biology-of-encodings thread explains *why* redundancy (which §2.1 flagged as a searchability hazard) is also the engine of evolvability — provided it is the *right kind* of redundancy (neutral, high-connectivity).

- **RNA neutral networks (Schuster, Fontana et al., 1994; Fontana & Schuster, 1998).** The RNA sequence→secondary-structure map is **many-to-one**: many sequences fold to the same shape, and the set of all sequences with a given phenotype forms a **neutral network** threaded through sequence space [11]. Evolution proceeds as *diffusion along a neutral network* punctuated by rapid phenotypic innovation when the drifting population reaches a boundary to a new shape [11]. Neutrality is what makes far-apart phenotypes mutually reachable.
- **Wagner, "Robustness, evolvability, and neutrality," *FEBS Letters* 579(8):1772–1778, 2005** (verified via the Santa Fe Institute working-paper 2004-12-030, identical text) [12]. Wagner's argument resolves the apparent paradox: *the more robust a system, the more of its mutations are neutral* — and neutral change is "a key to future evolutionary innovation," because a once-neutral mutation becomes phenotypically visible in a changed environment or genetic background. He distinguishes **evolvability-as-heritable-variation** from the deeper **evolvability-as-innovation**, and argues robustness (via abundant neutral variation) enhances the latter [12]. Computational analyses of neutral networks confirm that robustness *enhances* rather than blocks evolvability — the resolution of the robustness/evolvability paradox [12].

**Lesson for SixFour.** A perfectly bijective code (§1) has, by construction, *zero* neutrality — every genome is a distinct phenotype. That is ideal for byte-exactness but *hostile to a swap economy*, where you want many equivalent genes to drift and recombine. The σ-generator layer (384→768, a *reduction*) is where controlled, verifiable neutrality can be reintroduced: the 384→768 map is many-fewer-to-more only if generators overlap, but a *384→(subset of 768)* generator manifold means the *complement* directions are neutral (§4.4).

### 2.4 Hypernetworks & compositional / steerable generation

- **Hypernetworks (Ha, Dai & Le, "HyperNetworks," ICLR 2017)** [13]. A small "hypernetwork" generates the weights of a larger "main network"; the authors frame it explicitly as *"a relaxed form of weight-sharing"* and note the lineage to HyperNEAT and to Koutník et al.'s **Compressed Weight Search** (evolving the DCT coefficients of a weight matrix) [13]. The learnable parameters live only in the small generator — the exact structure SixFour already has (384 generator DOF producing 768 leaf reals). This validates the σ-genome as a *bona fide* hypernetwork-style weight/parameter generator.
- **Steerable / disentangled latent directions.** GANSpace (Härkönen et al., NeurIPS 2020) finds interpretable, largely-disentangled edit directions by **PCA in a generative model's latent/feature space** — no retraining, no supervision — turning an opaque latent into a set of nameable, blendable knobs (lighting, viewpoint, …) [14]. Jahanian et al. ("On the 'steerability' of GANs," ICLR 2020) show latent spaces support linear "walks" for high-level concept control [15]. The disentanglement-by-construction lineage (β-VAE and successors) targets latent axes that vary one factor at a time.

**Lesson for SixFour.** The σ-pair genome is *already* a set of generators that blend — i.e. a latent basis. The steerable-directions literature says the valuable property is not just coverage but **a basis whose directions are semantically separable and linearly combinable**. If the 128 σ-pairs per channel behave like GANSpace's PCA directions (near-orthogonal, individually meaningful), the genome is far more expressive-in-practice (and more shareable/remixable) than raw DOF count suggests.

### 2.5 Representation-capacity / expressivity & invertibility theory

- **Expressive encodings, formally (Meyerson, Qiu & Miikkulainen, "Simple Genetic Operators are Universal Approximators of Probability Distributions," GECCO 2022, best-paper)** [16]. An encoding is **expressive** iff *crossover of two parents can sample child phenotypes from an arbitrary distribution*. The theorem: with an expressive encoding, simple genetic operators are **universal approximators of probability distributions over phenotypes**, and expressive encodings achieve *up to super-exponential* convergence speedups over direct encoding — *even for static structures like binary vectors*, not only when the phenotype is a function [16]. Universal function approximators (GP, neural nets) are the substrates that make an encoding expressive.
- **Normalizing flows (Papamakarios, Nalisnick, Rezende, Mohamed & Lakshminarayanan, "Normalizing Flows for Probabilistic Modeling and Inference," JMLR 2021 / arXiv 1912.02762)** [17]. A flow composes **invertible transformations with tractable Jacobians**; under mild conditions a flow can represent *any* target distribution (universal representation via a triangular/CDF construction) — but the review is emphatic that **representational capacity ≠ learnability** ("makes no guarantees about behaviour in practice"), and that expressive power trades off against the cost of computing the inverse and Jacobian [17]. This is the exact intuition behind SixFour's bijective octree: an invertible code guarantees *reachability* (nothing is representationally excluded) at the price of designing the transform so both directions stay cheap and exact.
- **Minimum Description Length (Rissanen, 1978).** MDL operationalises Occam's razor: choose the model minimising `L(M) + L(D|M)` — model codelength plus data-given-model codelength — a computable, statistically-grounded approximation to Kolmogorov complexity [18]. MDL gives SixFour a principled *parsimony* axis: the "right" genome size is the one that minimises total description length of the captures it must reconstruct — a way to *ask whether 384 is too few or too many* rather than assert it.

---

## 3. Comparative analysis: direct vs. indirect, expressiveness vs. verifiability

**Direct encoding** = genotype specifies each phenotype element (roughly) one-to-one; large genotype, transparent map, poor scaling/regularity, easy to verify. **Indirect encoding** = genotype specifies a *rule/generator* reused to build the phenotype; small genotype, buys compression/regularity/resolution-independence, but the genotype→phenotype map is typically a nonlinear (often iterated) simulation that is hard to verify [6][7].

SixFour is a **hybrid**: an indirect *generator* layer (384 σ-pairs → 768 leaves, hypernetwork-style [13]) riding on a *bijective, transparent* substrate (octree code, flow-grade invertibility [17]). This is unusual and advantageous — it aims to buy indirect-encoding compression while keeping direct-encoding verifiability.

| Encoding family | Expressiveness / compression | Regularity (symmetry, repetition) | Searchability / locality | Verifiability (golden-gateable?) | Neutrality (evolvability fuel) |
|---|---|---|---|---|---|
| Direct (per-leaf palette, 768 reals) | Low (no reuse) | None built-in | High locality, uniform | **Yes** — trivial | Low |
| CGP (integer graph) [1][2] | Medium; iteration via SM-CGP | Some via node reuse | Good; neutral drift helps | Partial — integer graph inspectable, semantics not | **High** (non-coding genes) |
| Grammatical Evolution [3][4] | High (any grammar) | Grammar-dependent | **Poor** (non-uniform redundancy, low locality) | Hard (opaque BNF map) | High but *badly structured* |
| PushGP / Push [5] | **Maximal** (arbitrary control) | Emergent | Rugged | **No** (unconstrained) | High |
| CPPN / HyperNEAT [7][8] | High; resolution-independent | **Native** (function composition) | Good; NEAT complexification | **Partly** — CPPN is feed-forward & functional → *most* gateable dev-encoding | Moderate |
| L-systems / GRNs [9][10] | High (developmental) | Native (rewriting/regulation) | Variable | **No** (iterated simulation) | High |
| Hypernetwork generator [13] | High (compression by weight-gen) | Learned | Gradient-friendly | **Partly** — small generator gateable | Depends on generator |
| Normalizing flow (bijective) [17] | Universal *in principle*; learnability ≠ capacity | Depends on coupling design | Good if Jacobian cheap | **Yes** if transform is exact/cheap both ways | Zero (bijection has no neutral set) |
| **SixFour σ-genome over octree** | Medium-high (384→768 generator + invertible substrate) | σ-pair symmetry + 9-ch ChannelProduct outer product | High at code level (bijection); TBD at generator level | **Yes** (this is the design requirement) | **~Zero today** (needs deliberate injection) |

The table's punchline: **the two columns SixFour can't have both maxed are "expressiveness" and "verifiability," and the octree-hybrid is the design bet that lets you keep verifiability at ≈100% while pushing expressiveness up through the *generator* layer rather than the *map*.** The empty cell to fill is neutrality — a bijection is verifiable *because* it has no neutral set, but the neutral-networks literature [11][12] says you *want* neutrality for a swap economy.

---

## 4. Design implications for SixFour

### 4.1 Is 384 DOF of σ-generators enough?

**Probably yes for per-frame palettes, and the right question is not raw DOF but reachable-manifold coverage measured by MDL.** Three grounded arguments:

- **The hypernetwork precedent.** Ha et al. [13] and Compressed Weight Search show that a *small* generator routinely paints a *much larger* weight/parameter space with negligible loss when the target has regularity — 384→768 is a mild 2× expansion, far gentler than the 100–1000× ratios those methods sustain. If natural-image palettes are as regular as image weights (they are: colours cluster, chroma is low-rank), 384 σ-generators have ample headroom.
- **The identifiability guarantee already earned.** SixFour's own "rank-3 cell aggregate + full-matrix loss" fix that broke the L-anchor symmetry, plus the identifiability theorem giving a *unique, visible* optimum with `w_value>0`, is exactly the property §2.1/§2.3 say a good encoding needs: a well-posed, high-locality map with no degenerate flat directions. That is worth more than extra DOF.
- **Decide it empirically with MDL [18], not by assertion.** Fit the two-part codelength `L(genome) + L(captures | genome)` across a corpus of real 64-frame bursts at 256, 384, 512 generators. If codelength is still falling at 384, add generators; if flat, 384 is parsimonious. This turns "is 384 enough?" into a measurement, which is the honest answer.

### 4.2 Would an indirect/developmental encoding raise expressiveness while staying invertible & golden-gateable?

**The CPPN sub-family — and *only* it among developmental encodings — is a live candidate; L-systems and GRNs are not.** Reasoning from the survey:

- L-systems and GRNs [9][10] are *iterated simulations*; their genotype→phenotype map has no cheap inverse and would be a golden-gate nightmare. Rule them out.
- A **CPPN is feed-forward and functional** [7]: query phenotype coordinates `(L,a,b,x,y,t)` — which SixFour *already has as its 6-axis alphabet* — through a fixed composition of primitives (sine/Gaussian/linear). That map is (a) inspectable, (b) cheap both ways for the low-dimensional leaf lattice, and (c) natively encodes the **symmetry / repetition / repetition-with-variation** regularities [7] that a 64³ GIF's palette is full of. A **golden-gateable CPPN** = a *fixed, hand-written* composition of a small primitive set, with the σ-generators as its *coefficients*, verified against Haskell golden vectors exactly like `MaskedBandForward.swift`. This would raise expressiveness (regularity-for-free) while keeping the octree bijection as the substrate the CPPN paints *into*.
- Crucially, the CPPN would be the *generator*, not a replacement for the invertible code. The octree stays the tokenizer/substrate (mirroring the project's own "frozen reversible lift stays the tokenizer, the large learned object rides on top" architecture). Invertibility is preserved because the CPPN produces leaf values that still round-trip through `octantDistill/Synthesize`.

**Recommendation:** prototype a *fixed-topology, hand-writable* CPPN-style generator whose inputs are the existing 6 axes and the 9-channel ChannelProduct, coefficients = σ-pairs. Verify it under `Properties.*` before shipping. This is the single highest-leverage expressiveness upgrade compatible with the golden gate.

### 4.3 A compositional "gene algebra" (blend/compose genes) without breaking byte-exactness

The steerable-latent literature [14][15] says the payoff of a generator basis is *linear combinability*. SixFour can get a **closed gene algebra** if — and only if — the composition operations commute with the octree bijection. Concrete, byte-exact operators:

- **Blend (convex combination).** `blend(g1, g2, α)` in the *384-DOF generator space* (not the 768 leaf space), with `α` a fixed-point Q16 scalar. Because the octant synthesize is deterministic, `paletteOf(blend(...))` is byte-exact iff the blend arithmetic is done in the Zig Q16 floor. This is the GANSpace "walk along a direction" [14] made exact.
- **Compose / graft by octant band.** The octree is *band-structured* (`[[Detail]]`, finest-first). Define `graft(g_coarse, g_detail)` = take the coarse value(s) from one gene and the fine detail bands from another. This is closed under the bijection by construction (you are swapping independent sub-codes), and it is a *natural crossover operator* — the octree gives you a free, structure-respecting recombination that GE had to fight for [4].
- **σ-pair generator crossover.** Because generators are a set (3×128), single-generator swap/mutation is a local, high-locality operator in the sense §2.1 wants — the antidote to GE's low-locality problem.

The rule that keeps all three byte-exact: **do the algebra in the generator / Q16-floor domain, then synthesize once.** Never compose in float leaf space and hope it round-trips.

### 4.4 How neutrality makes the gene space more evolvable in the swap economy

The bijection gives SixFour zero neutrality (§2.3) — good for verification, bad for a trading population that wants many equivalent-but-remixable genes [11][12]. Inject *controlled, verifiable* neutrality:

- **Generator-space neutral directions.** If the 384→768 map is not full-rank onto the 768 leaves — i.e. the generator manifold is a *subset* of leaf space — then directions in generator space that leave the reconstructed palette unchanged (to Q16 precision) are **exact neutral moves**. A population can drift along them without changing the phenotype, then innovate when a swap pushes it to a manifold boundary — Schuster/Fontana diffusion [11], now byte-exact.
- **Neutrality as robustness → evolvability.** Wagner's argument [12] applied to the swap economy: a gene with a large neutral set is *robust* (survives recombination without visible damage) and therefore a better *trade good* — it can be blended/grafted (§4.3) into many contexts and still work, then reveal new behaviour in a new capture context. Design the σ-basis so common palettes sit in *high-neutrality* regions.
- **Verifiability is preserved** because neutrality here is *defined by the golden gate*: two genes are neutral-equivalent iff their synthesized palettes are byte-identical. Neutrality becomes a *checkable* equivalence relation, not a soft one — the opposite of GE's uncontrolled non-uniform redundancy [4].

This is the design's most elegant reconciliation: the same bijection that seems to forbid neutrality actually lets you define neutrality *exactly*, which is what a verifiable swap economy needs.

---

## 5. Open questions

1. **What is the intrinsic dimension of real capture palettes?** Until the MDL sweep (§4.1) is run on a corpus of 64-frame bursts, "384 is enough" is a hypothesis, not a result.
2. **Is the σ-basis actually disentangled/steerable?** Does PCA-in-generator-space (à la GANSpace [14]) recover near-orthogonal, semantically-nameable colour directions, or are the 128 σ-pairs entangled? This governs whether the gene algebra (§4.3) yields *meaningful* blends.
3. **Can a hand-written CPPN-style generator (§4.2) beat the current linear σ-reconstruction on reconstruction fidelity while staying golden-gateable?** Requires a prototype + golden-vector regression.
4. **What fraction of generator space is neutral, and can the basis be re-parameterised to enlarge the neutral set for common palettes** without hurting the identifiability theorem's unique-optimum guarantee?
5. **Does the dual-cube (L,a,b)↔(x,y,t) involution constrain expressiveness or extend it?** The symmetry is a strong prior (like CPPN symmetry [7]) — is it *the right* prior for temporal palettes, and does it forbid any palettes captures actually need?
6. **Learnability ≠ capacity, per the flow review [17].** Even if the octree/CPPN *can* represent a target palette, can the on-device 21-param V3 detail predictor and MLX base trainer *find* it? The gap between reachable and trainable is unmeasured.

---

## 6. References

All URLs below were fetched or verified during this review; claims are cited to the source actually consulted.

1. Julian F. Miller & Peter Thomson, *Cartesian Genetic Programming* (origins 1997; term 1999; general form 2000). Overview + variants. Wikipedia summary of the CGP method and self-modifying/modular extensions. https://en.wikipedia.org/wiki/Cartesian_genetic_programming
2. *Recent Developments in Cartesian Genetic Programming and its Variants*, ACM Computing Surveys (2018/2019). https://dl.acm.org/doi/abs/10.1145/3275518
3. Michael O'Neill & Conor Ryan, *Grammatical Evolution: Evolutionary Automatic Programming in an Arbitrary Language*, Springer (Genetic Programming series). https://link.springer.com/book/10.1007/978-1-4615-0447-4 (book record via https://books.google.com/books/about/Grammatical_Evolution.html?id=GmSlNzFvQiAC)
4. Redundancy & locality of the GE genotype–phenotype map; SGE/πGE repairs. *On the Locality of Grammatical Evolution* and *On the Non-uniform Redundancy in Grammatical Evolution*, Springer. https://link.springer.com/chapter/10.1007/11729976_29 ; https://link.springer.com/chapter/10.1007/978-3-319-45823-6_27
5. Lee Spector, *Expressive Genetic Programming: Concepts and Applications* (Push/PushGP), GECCO 2015 companion tutorial. https://us1.discourse-cdn.com/flex016/uploads/pushlanguage/original/1X/9e842187d2fbd9220ee28ae356a8638066c92995.pdf ; Push language reference: http://faculty.hampshire.edu/lspector/push.html
6. Kenneth O. Stanley & Risto Miikkulainen, "A Taxonomy for Artificial Embryogeny," *Artificial Life* 9(2):93–130, 2003. https://direct.mit.edu/artl/article/9/2/93/2433/A-Taxonomy-for-Artificial-Embryogeny (publisher page returned HTTP 403; DOI record: https://dl.acm.org/doi/abs/10.1162/106454603322221487)
   - 6a. Corroborating index (indirect encoding, gene reuse, grammatical vs cell-chemistry axis): Neuroevolution overview. https://en.wikipedia.org/wiki/Neuroevolution
7. Kenneth O. Stanley, "Compositional Pattern Producing Networks: A Novel Abstraction of Development," *Genetic Programming and Evolvable Machines* 8:131–162, 2007. https://link.springer.com/article/10.1007/s10710-007-9028-8 (full text fetched: https://gwern.net/doc/ai/nn/fully-connected/2007-stanley.pdf)
8. Kenneth O. Stanley, David D'Ambrosio & Jason Gauci, HyperNEAT / *A Hypercube-Based Encoding for Evolving Large-Scale Neural Networks*, *Artificial Life* 2009; "HyperNEAT: The First Five Years." https://link.springer.com/chapter/10.1007/978-3-642-55337-0_5
9. Aristid Lindenmayer, L-systems (1968), parallel string-rewriting developmental grammars; GA-coupled evolution of L-systems. https://link.springer.com/chapter/10.1007/978-1-4020-2393-4_9
10. Gene Regulatory Network encodings for artificial development; GReaNs; differentiable GRNs. *Evolving Differentiable Gene Regulatory Networks* (arXiv 1807.05948, https://arxiv.org/pdf/1807.05948) ; *From evolving artificial gene regulatory networks to evolving spiking neural networks* (PMC3704679, https://pmc.ncbi.nlm.nih.gov/articles/PMC3704679/)
11. Peter Schuster, Walter Fontana et al., "From sequences to shapes and back: a case study in RNA secondary structures" (1994) and Fontana & Schuster, "Shaping Space" / neutral networks (1998); RNA genotype–phenotype map is many-to-one, evolution diffuses along neutral networks. https://pubmed.ncbi.nlm.nih.gov/22028856/ (topology of RNA neutral networks)
12. Andreas Wagner, "Robustness, evolvability, and neutrality," *FEBS Letters* 579(8):1772–1778, 2005. Fetched via identical Santa Fe Institute Working Paper 2004-12-030: https://sfi-edu.s3.amazonaws.com/sfi-edu/production/uploads/sfi-com/dev/uploads/filer/fd/6f/fd6ffcec-b1ba-4027-811c-03241effdb27/04-12-030.pdf ; journal record: https://febs.onlinelibrary.wiley.com/doi/10.1016/j.febslet.2005.01.063
13. David Ha, Andrew M. Dai & Quoc V. Le, "HyperNetworks," ICLR 2017. Full text fetched: https://openreview.net/pdf?id=rkpACe1lx (arXiv 1609.09106)
14. Erik Härkönen, Aaron Hertzmann, Jaakko Lehtinen & Sylvain Paris, "GANSpace: Discovering Interpretable GAN Controls," NeurIPS 2020. https://proceedings.neurips.cc/paper/2020/file/6fe43269967adbb64ec6149852b5cc3e-Review.html
15. Ali Jahanian, Lucy Chai & Phillip Isola, "On the 'steerability' of Generative Adversarial Networks," ICLR 2020. https://openreview.net/pdf?id=HylsTT4FvB
16. Elliot Meyerson, Xin Qiu & Risto Miikkulainen, "Simple Genetic Operators are Universal Approximators of Probability Distributions (and other Advantages of Expressive Encodings)," GECCO 2022 (best-paper). https://arxiv.org/abs/2202.09679 (full text: https://arxiv.org/pdf/2202.09679 ; ACM: https://dl.acm.org/doi/10.1145/3512290.3528746)
17. George Papamakarios, Eric Nalisnick, Danilo J. Rezende, Shakir Mohamed & Balaji Lakshminarayanan, "Normalizing Flows for Probabilistic Modeling and Inference," *JMLR* 22 (2021) / arXiv 1912.02762. Full text fetched: https://ar5iv.labs.arxiv.org/html/1912.02762
18. Jorma Rissanen, MDL principle (1978); two-part codelength `L(M)+L(D|M)`, computable approximation to Kolmogorov complexity. Survey verified: *The Minimum Description Length Principle for Pattern Mining: A Survey* (arXiv 2007.14009, https://arxiv.org/pdf/2007.14009)

---

*Cross-links:* [[01-transferable-genes-genealogy]] · [[03-distributed-biological-models]] · [[04-swap-economy-governance]]
