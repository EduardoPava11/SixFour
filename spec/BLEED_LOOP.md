# The Bleed Loop — Authoritative Mathematics of Obfuscation, Reveal, and Generative Incitement

> **Status of record: 2026-05-30.** This document turns the *obfuscate → prioritize → bleed → loop → incite* idea into rigorous mathematics ready to transcribe into `Spec/*.hs`. It **continues** `MATH.md` (Definitions 1–20, Theorems 1–5) and `LOOK_NN.md` (Definitions 21–38, Theorems 6–9): numbering resumes at **Definition 45 / Theorem 14**. It **extends, never reinvents**, four existing modules — `SigmaDecomp`, `AxisNet`, `PairTree`, `SigmaPairHead` — whose signatures are load-bearing throughout.
>
> Produced by the `lnn-obfuscation-bleed-math-spec` workflow (6 objects formalized → adversarially verified, all REVISE none CUT → integration pass → synthesis). Five independent derivations each self-corrected onto the same two-operator discipline below — that convergence is the evidence the system is coherent.
>
> **The one correction that runs through everything (read first).** There are **two distinct σ-splits** in this spec and the system needs both, kept apart by name:
>
> - **The obfuscation/reveal axis** lives on the **per-leaf OKLab palette** and is the **AxisNet `L ⊥ {a,b}` split** (`projectAxis AxisL` vs the chroma deviation of `toDeviation`). Its orthogonality is *coordinate* orthogonality — the grey L axis is perpendicular to the chroma plane — exact and **σ-independent**. This is "show tone, hide chroma."
> - **The σ-fold / scene-affordance axis** lives on the **4096-bin scene histogram** and is `SigmaDecomp.symPart/asymPart`, splitting by **chroma parity** under the bin permutation `σ_bin(iL,ia,ib) = (iL,15−ia,15−ib)`. Its sole role here is the *ceiling* `sigmaSymFraction(H_ref)` on reachable reveal, plus the σ-mirror-pair fold of Phase A/B.
>
> The discriminating test, which **adjudicates the whole architecture** and is the first law to transcribe: `projectAxis AxisL (OKLab l a b) = OKLab l 0 0` is achromatic (`a = b = 0`); `symPart` permutes bins by chroma parity and **does not zero chroma**. Using `symPart` as the obfuscation operator would make "show L hides a,b" *false*. The obfuscation operator is the **AxisL projector**, not the chroma-parity fold.

---

## 1. The idea, made precise

A SixFour capture is **full colour** $c=(L,a,b)\in\mathcal C$, but the deployed head shows only its lightness. We formalise this not as *discarding* chroma but as **losslessly obfuscating** it. Let $\Omega = (S,R)$ be the AxisNet coordinate split: $S\,c = (L,0,0)$ is the **shown grayscale view** (the σ-fixed grey axis) and $R\,c = (0,a,b)$ is the **retained chroma residual** (the σ-antisymmetric chroma plane), with $S\,c \perp R\,c$ and $\Omega^{-1}(S\,c,R\,c)=S\,c+R\,c=c$ exactly. The grayscale palette therefore **hides** chroma behind every shown $L$; it does not delete it — *each $L$ inherently has its $(a,b)$ because we capture in colour*, banked in the retained detail. **Prioritization** is then a rate–distortion allocation: the user spends a scalar **reveal budget** $\beta$ across the palette anchors, and the optimal spend reveals the largest hidden chroma first — tone is grounded before any colour is spent, *forced by orthogonality, not by policy*. **Colour bleed** is the one-parameter family $\beta_t\,c=(L,ta,tb)$ that monotonically un-hides the retained residual, $\beta_0=$ grayscale, $\beta_1=$ full colour. The **GIF feedback loop** drives the reveal: the user authors a per-frame GIF, its retained-chroma marginal conditions the next scaffold, the scaffold *proposes* but **commits nothing**, the user folds, and a new GIF is emitted — *more and more colour bleeds in as the user works*. Crucially the loop's **attractor is creation, not an MSE optimum**: it is a non-trivial invariant *shell* — bounded around the reference (coherence: tone preserved every step) yet fixed-point-avoiding while the user keeps folding (novelty: new chroma each step) — so the system is *seductive* (each iterate invites the next) rather than convergent onto a single answer. The only genuine fixed point is degenerate: full reveal **and** the user has stopped.

---

## 2. Spaces & notation (fixed once)

| Symbol | Space | Meaning | Module anchor |
|---|---|---|---|
| $\mathcal C=\mathcal L$ | $[0,1]\times[-0.4,0.4]^2$ | the OKLab gamut (one colour) | `Color.OKLab`, `PairTree.inGamut` |
| $V_+$ | $\{(L,0,0)\}\subset\mathcal C$ | **shown** grey axis (σ-fixed, `axisSigmaSign AxisL = +1`) | `AxisNet.projectAxis AxisL` |
| $V_-$ | $\{(0,a,b)\}\subset\mathbb R^3$ | **retained** chroma plane (σ-antisym, sign $-1$) | `AxisNet.toDeviation (adA,adB)` |
| $\mathcal P$ | $\mathcal C^{256}$ | a palette (256 leaves), in σ-pair-interleaved order | `SigmaPairHead.reconstructPaired` |
| $P=[\,m_i\pm\beta_i\delta_i\,]$ | $\mathcal P$ | revealed palette: anchors $m_i=(L_i,0,0)\in V_+$, spreads $\delta_i=(0,a_i,b_i)\in V_-$ | `SigmaPairHead`, $i\in\{0..127\}$ |
| $E$ | $\mathbb R^{768}\cong$ `HaarPalette` | the Haar coefficient space of a palette | `PairTree.analyze/reconstruct` |
| $\Gamma$ | $\{0,1,\dots,15\}^2$ (16×16) | the **loom**: the 256 cells the user folds | `PALETTE-LOOM §1` |
| $\mathcal G$ | $64^3$ voxel GIF | the emitted output (always a GIF) | the loop output |
| $H_{\mathrm{ref}}$ | `Histogram4096` (simplex) | the user-authored reference GIF's pooled histogram | `Bottleneck16.Histogram4096` |
| $\beta$ | $[0,1]^{128}$ (or $[0,1]$) | the **bleed/reveal field** (per σ-pair, or scalar) | new |
| $\chi_p=\lVert\delta_p\rVert^2$ | $\mathbb R_{\ge0}$ | hidden-chroma energy of pair $p$ | derived from $\delta_p$ |
| $\sigma$ | $\mathcal C\to\mathcal C$ | $\sigma(L,a,b)=(L,-a,-b)$ (chroma involution) | `PairTree.sigmaReflect` |
| $\sigma_{\mathrm{bin}}$ | $\mathbb Z_{4096}\to\mathbb Z_{4096}$ | the *histogram* parity permutation (**distinct** from $\sigma$) | `SigmaDecomp.sigmaBinPerm` |

**Convention.** $S,R$ act on $\mathcal C$ and lift coordinatewise to $\mathcal P$. $\Pi_{\mathrm{sym}}=$ `symPart`, $\Pi_{\mathrm{asym}}=$ `asymPart` act **only** on `Histogram4096`. We **never** write $\Omega=\Pi_{\mathrm{sym}}$.

---

## 3. Operators (definitions)

### 3.1 The obfuscation projection $\Omega$

> **Definition 45** (the obfuscation operator $\Omega$ and its inverse). On $\mathcal C$ define
> $$S\,c \;:=\; \mathrm{projectAxis\;AxisL}\;c \;=\;(L,0,0)\in V_+, \qquad R\,c \;:=\; c - S\,c \;=\;(0,a,b)\in V_-,$$
> $$\Omega\,c \;=\;(S\,c,\,R\,c)\in V_+\times V_-, \qquad \Omega^{-1}(s,r)=s+r .$$
> $S$ is the **shown** grayscale view; $R$ is the **retained** chroma residual (`AxisNet.toDeviation` $\mapsto (\mathrm{adA},\mathrm{adB})$). The split is *coordinate*-orthogonal: the L axis $\perp$ the $(a,b)$ plane, so $\langle S\,c,R\,c\rangle=0$ and $\lVert c\rVert^2=\lVert S\,c\rVert^2+\lVert R\,c\rVert^2$ hold **for the right reason** (geometry of OKLab), independently of $\sigma$. σ-structure is **inherited** as a theorem (§4 L45.8), not built in: $\sigma(S\,c)=S\,c$, $\sigma(R\,c)=-R\,c$.
>
> **Domain/codomain.** $S:\mathcal C\to V_+$, $R:\mathcal C\to V_-$, $\Omega:\mathcal C\to V_+\times V_-$, lifted leafwise to $\mathcal P$. $\Omega^{-1}\circ\Omega=\mathrm{id}$.

> **Definition 46** (obfuscation depth). $\mathrm{obfDepth}(P) := \dfrac{\sum_i\lVert R\,c_i\rVert^2}{\sum_i\lVert c_i\rVert^2}=\dfrac{\sum_i(a_i^2+b_i^2)}{\sum_i(L_i^2+a_i^2+b_i^2)}\in[0,1]$ — the fraction of palette energy currently hidden behind the grey view. **This measures chroma, not σ-parity.** ($\mathrm{obfDepth}$ is the AxisNet/$V_-$ analogue; `SigmaDecomp.sigmaSymFraction` is re-roled as the *scene ceiling*, §3.6.)

> **Definition 47** (the σ-fold $\Phi$, a *separate* operator, kept distinct). On `Histogram4096`, $\Phi_{\mathrm{show}}=\Pi_{\mathrm{sym}}=$ `symPart`, $\Phi_{\mathrm{retain}}=\Pi_{\mathrm{asym}}=$ `asymPart`. This is the **complement-merge** of Phase A/B (merge a colour with its complement), sound on σ-mirror pairs only. **Do not conflate** $\Phi$ (chroma-parity fold) with $\Omega$ (chroma projection). They coincide only on already-grey inputs.

### 3.2 The colour-bleed operator $\beta_t$ and its field $B_\tau$

> **Definition 48** (pointwise bleed, **primary** — renders the GIF). For $t\in[0,1]$,
> $$\beta_t(L,a,b)\;=\;(L,\,ta,\,tb)\;=\;S\,c + t\,R\,c.$$
> $\beta_0=\mathrm{projectAxis\;AxisL}$ (pure grayscale), $\beta_1=\mathrm{id}$. In `AchromaticDeviation` terms: keep $\mathrm{adGrey}$, scale $(\mathrm{adA},\mathrm{adB})$ by $t$. **Domain/codomain** $\beta_t:\mathcal C\to\mathcal C$, lifted leafwise to $\mathcal P$.

> **Definition 49** (the bleed field). $B_\tau:\big([0,1]^{\mathrm{Index}}\big)\times\mathcal P\to\mathcal P$, $(B_\tau P)_i=\beta_{\tau_i}(c_i)$, with $\mathrm{Index}\in\{$ pair $\{0..127\}$, leaf $\{0..255\}\}$. On the σ-pair view, $B_\beta$ scales each spread $\delta_p$ by $\beta_p$:
> $$\bigl(B_\beta\,P\bigr)_{\text{pair }p}=\bigl[\,m_p+\beta_p\delta_p,\; m_p-\beta_p\delta_p\,\bigr].$$
> Constant field $\tau\equiv t$ recovers $\beta_t$.

> **Definition 50** (reveal-via-Haar / merge synthesis). For a σ-mirror pair with parent $s=m(c)=\tfrac12(c+\sigma c)=(L,0,0)$ and detail $\delta=d(c)=\tfrac12(c-\sigma c)=(0,a,b)$,
> $$\mathrm{reveal}_t(s,\delta)\;=\;s+t\,\delta\;=\;\beta_t(c).$$
> This is `PairTree`-style synthesis with the detail scaled by $t$; $t=1$ gives the exact `reconstruct`/`analyze` round-trip (`lawReconstructAnalyzeRoundTrip`). **The user's MERGE gesture is $\Omega$ at $t{=}0$; SPLIT is $\Omega^{-1}$; partial reveal is $\beta_t$.** Per `PALETTE-LOOM §2`, in Phase L the detail $d=(\tfrac12\Delta L,0,0)$ is an honest *lightness* deviation (no chroma); in Phase A/B the complement-merge detail $d=(0,a,b)$ is pure chroma.

> **Definition 50b** (spectral bleed — **bookkeeping only, not rendered**). On histogram space, $T_t:=\Pi_{\mathrm{sym}}+t\,\Pi_{\mathrm{asym}}$ (built from `sigmaApply`) is self-adjoint with spectrum $\{1^{2048},\,t^{2048}\}$ (multiplicities `dimSigmaSym`/`dimSigmaAsym`). It is the σ-**energy accountant** only. **Explicit non-identity:** $T_t\neq$ `histogramFromOKLabs` of $\beta_t$-pushed leaves — the pushforward is a *nonlinear rebinning*. $T_t$ is never the rendered distribution.

### 3.3 Rate allocation / prioritization

> **Definition 51** (latent-chroma measure on σ-pairs). For pair $p$ of `reconstructPaired`, $m_p=\tfrac12(c_p+\sigma c_p)=(L_p,0,0)\in V_+$, $\delta_p=\tfrac12(c_p-\sigma c_p)=(0,a_p,b_p)\in V_-$ **exactly** (L-component identically zero by the σ-involution — *no `PairTree.pairOffsets` is invoked*, which would carry L-leakage). $\chi_p:=\lVert\delta_p\rVert^2=a_p^2+b_p^2$, and $\sum_p\chi_p$ is exactly the palette's $V_-$ energy.

> **Definition 52** (reveal rate, distortion, and the waterfilling allocation). With a Gaussian/Bures chroma model (reusing `MATH.md` Def 16, `gaussianColorEntropy`) and scale $\lambda$:
> $$r(\beta_p;\chi_p)=\tfrac12\log\!\Big(1+\tfrac{\beta_p^2\chi_p}{\lambda^2}\Big),\quad \mathcal R(\beta)=\sum_p r(\beta_p;\chi_p),\quad \mathcal D(\beta)=\sum_p(1-\beta_p^2)\,\chi_p .$$
> The **reverse-waterfilling** optimum for a reveal budget $\beta^{\mathrm{budget}}$ is $\big(\beta^*_p\big)^2=\max\!\big(0,\,1-\lambda^2\nu/\chi_p\big)$ ($\nu$ the water level); it reveals anchors in **strictly descending $\chi_p$ order**. $\mathrm{Index\;set}\;P=\{0,\dots,127\}$ are the 128 σ-pairs (**not** `PairTree` binary nodes).

### 3.4 The merge as Haar synthesis carrying latent chroma

This is Definition 50 read as the loom mechanic. On the loom $\Gamma$, a user **fold** of cells $c_0,c_1$ writes the parent $m=\tfrac12(c_0+c_1)$ to the shown loom and **banks** the detail $d=\tfrac12(c_0-c_1)$. For a colour capture $d$ carries the latent chroma into the retained bank $\mathfrak d=\{\delta_p\}$; $\mathrm{split}(m,d)=\{c_0,c_1\}$ recovers it losslessly. *Merging obfuscates chroma into the retained detail; splitting/revealing un-hides it.* The Phase-L loom is a **lightness**-Haar tree (folds are pure-L, `lawReconstructAnalyzeRoundTrip` exact); the chroma reservoir $\mathfrak d$ is the AxisNet deviation carried alongside, indexed by which cells were fused.

### 3.5 $B(A(L))$ as a conditional reveal generator $\Gamma_\psi$

> **Definition 53** (the scaffold as a conditional chroma generator). The cascade $B\circ A\circ L$ is recast as
> $$L:\text{Tokens}\to V_+^{128}\ (\text{the anchors }m_i),\qquad \Gamma_\psi:V_+^{128}\times U\times \mathcal R\to\mathscr P\!\big(V_-^{128}\big),$$
> where $A,B$ are the heads of $\Gamma_\psi$ emitting the chroma spreads $\delta_i=(0,a_i,b_i)$ at the anchor's **own** $L_i$ (i.e. $c_i=m_i+\beta_i\delta_i$, written via the pointwise asym residual $R$, **not** `projectAxis AxisA` which would reset $L$ to $0.5$). $U$ is the user fold-program, $\mathcal R$ the reference (Def 54). $L$ writes $V_+$ only; $A,B$ write $V_-$ only; `axisSigmaSign` ($+1$ for L, $-1$ for $a,b$) types the equivariance.

> **Definition 54** (reference conditioning). The reference object is $\mathrm{ref}=\Pi_{\mathrm{asym}}(H_{\mathrm{ref}})=$ `asymPart` of the authored GIF's pooled histogram — the σ-antisymmetric (hidden-chroma) marginal of what the user made. $\Gamma_\psi$ reads only $(\text{anchors},U,\mathrm{ref})$; it **never** reads $\beta$ or $\mathfrak d$ directly. The only channel from reveal-history into the net is the re-rendered reference GIF.

### 3.6 The scene-affordance ceiling (the *only* role of `symPart` here)

> **Definition 55** (reveal ceiling). $\overline r(H_{\mathrm{ref}}) := 1-\mathrm{sigmaSymFraction}(H_{\mathrm{ref}})=\dfrac{\mathrm{sigmaAsymNormSquared}(H_{\mathrm{ref}})}{\lVert H_{\mathrm{ref}}\rVert^2}\in[0,1]$ — an upper bound on how much σ-antisymmetric chroma a σ-pair palette can ever reveal for *this* capture. This is a diagnostic on the reference, **not** the reveal operator.

---

## 3b. The feedback loop (dynamical system)

> **Definition 56** (loop state). $\mathcal S=(P,\beta,\mathfrak d,\mathrm{ref},\theta,U)$: palette $P$ (σ-pair form), reveal field $\beta\in[0,1]^{128}$, retained chroma bank $\mathfrak d=\{\delta_i\}$, reference $\mathrm{ref}=\Pi_{\mathrm{asym}}(H_{\mathrm{ref}})$, frozen scaffold weights $\theta$, recorded fold-program $U$ (the user's labor).

> **Definition 57** (the update map $T$). One user iteration is the composition
> $$T \;=\; G\circ R_\beta\circ F_U\circ S_\theta,$$
> with named sub-operators:
> 1. **$S_\theta$ (scaffold, commits nothing).** $\Gamma_\psi$ proposes $p_\psi(\delta\mid \text{anchors},U,\mathrm{ref})$ with MAP hint $\hat\delta_i$; it is a *section* — $\pi_{\mathcal S}\circ S_\theta=\mathrm{id}$ on the committed coordinates.
> 2. **$F_U$ (user actuator, the only writer).** A loom fold/disc-steer updates $U$, hence $\mathfrak d$ and the shown anchors. Built from `reconstruct`/`analyze`.
> 3. **$R_\beta$ (reveal gate).** $(R_\beta P)_p=[m_p+\beta_p\delta_p,\;m_p-\beta_p\delta_p]$.
> 4. **$G$ (emit).** Render the $64^3$ GIF from $P$; recompute $\mathrm{ref}\leftarrow\Pi_{\mathrm{asym}}(H_{\mathrm{GIF}})$.
>
> The orbit $\{\mathcal S_k\}=\{T^k\mathcal S_0\}$ is the seductive loop. The schedule $\beta_k$ escalates monotonically along `goldenDecay` (coarse harmonies bleed first); conditioning flows **only through the emitted GIF** (Def 54).

---

## 4. Laws & theorems (QuickCheck-able predicates)

Each law below is a checkable predicate; the named ties make them transcribable directly. **Per-operator laws** first, then the **four system theorems**.

### 4.1 Obfuscation $\Omega$ (lands in `Spec/Obfuscation.hs`)

- **L45.1 — GRAYSCALE-TRUTH (the discriminating test).** `∀c. let OKLab _ a b = projectAxis AxisL c in a == 0 && b == 0`. *Passes for `projectAxis AxisL`, FAILS for `symPart` — this law decides the architecture.*
- **L45.2 — RETENTION (lossless).** $\Omega^{-1}(\Omega\,c)=S\,c+R\,c=c$ for all $c$. `fromDeviation (toDeviation c) == c`.
- **L45.3 — ORTHOGONALITY.** $\langle S\,c,\,R\,c\rangle=0$ (L axis $\perp$ ab plane; exact, σ-independent).
- **L45.4 — PARSEVAL (per leaf).** $\lVert c\rVert^2=\lVert S\,c\rVert^2+\lVert R\,c\rVert^2$.
- **L45.5 — IDEMPOTENCE / NILPOTENCE.** $S(S\,c)=S\,c$, $R(R\,c)=R\,c$, $S(R\,c)=0$, $R(S\,c)=0$.
- **L45.6 — GREY VACUITY (Phase-L gate).** $a=b=0\Rightarrow S\,c=c \wedge R\,c=0$ (a grey is its own complement; nothing to obfuscate).
- **L45.7 — CAPTURE-IN-COLOUR.** $R\,c\neq 0 \Leftrightarrow (a,b)\neq 0$; $\mathrm{obfDepth}(P)>0\Leftrightarrow$ the palette is chromatic.
- **L45.8 — σ INHERITED.** $\sigma(S\,c)=S\,c$, $\sigma(R\,c)=-R\,c$ (from `axisSigmaSign`; a *theorem about* $\Omega$, not its definition).

### 4.2 Colour bleed $\beta_t$ / $B_\tau$ (`Spec/ColorBleed.hs`)

- **L48.1 — ENDPOINTS.** $\beta_0=\mathrm{projectAxis\;AxisL}$; $\beta_1=\mathrm{id}$.
- **L48.2 — TONE-INVARIANCE.** $S(\beta_t\,c)=S\,c$ for all $t$ (the grey skeleton is untouched).
- **L48.3 — MONOTONICITY.** $0\le s\le t\le 1\Rightarrow \lVert R(\beta_s c)\rVert=s\lVert R\,c\rVert\le t\lVert R\,c\rVert=\lVert R(\beta_t c)\rVert$.
- **L48.4 — SEMIGROUP.** $\beta_s\circ\beta_t=\beta_{s\cdot t}$ (commutative multiplicative monoid on the chroma channel; $\beta_1$ identity, $\beta_0$ absorbing).
- **L48.5 — CONTINUITY/LINEARITY (corrected).** $t\mapsto\beta_t(c)$ is **affine** with derivative $R\,c$, hence Lipschitz in $t$ with constant $\lVert R\,c\rVert$ ($\le\sqrt{0.32}\approx0.566$ in-gamut). $\beta_t$ is linear in $c$ with **operator norm 1**. *(Do not claim "1-Lipschitz in $t$".)*
- **L48.6 — σ-EQUIVARIANCE.** $\beta_t(\sigma\,c)=\sigma(\beta_t\,c)=(L,-ta,-tb)$.
- **L48.7 — GAMUT NONEXPANSION.** `inGamut c ⇒ inGamut (β_t c)` (chroma contracts toward the grey axis for $t\in[0,1]$).
- **L48.8 — MERGE-COMMUTATION.** $\mathrm{reveal}_t(s,\delta)=s+t\delta=\beta_t(c)$; bleed-then-merge $=$ merge-then-reveal: $\tfrac12(\beta_t c+\beta_t\sigma c)=s$ (parent invariant), $t=1\Rightarrow\mathrm{split}(s,\delta)=\{c,\sigma c\}$.
- **L48.9 — PARSEVAL-UNDER-BLEED (bookkeeping $T_t$).** $\lVert T_t H\rVert^2=\lVert H_{\mathrm{sym}}\rVert^2+t^2\lVert H_{\mathrm{asym}}\rVert^2$; spectrum $\{1^{2048},t^{2048}\}$. *(Energy accountant only; not the rendered histogram — see Def 50b.)*
- **L48.10 — FIELD REDUCTION.** $B_{\tau\equiv t}=\beta_t$; $B_\tau$ is leaf-diagonal and commutes with σ when $\tau$ is σ-coherent ($\tau_i=\tau_{\sigma(i)}$).

### 4.3 Rate allocation $\mathcal R,\mathcal D,\beta^*$ (`Spec/ChromaAllocation.hs`, consumes **SigmaPairHead**)

- **L52.1 — REVEAL ENDPOINTS.** $\mathcal R_{\beta\equiv0}(P)=$ all leaves grey; $\mathcal R_{\beta\equiv1}(P)=P$.
- **L52.2 — REVEAL ORTHOGONALITY.** $S(B_\beta P)=S(P)$ and $R(B_\beta P)=\beta\odot R(P)$ (reveal touches $V_-$ only; **true by typing** since $\delta_p\in V_-$ exactly).
- **L52.3 — NO CHROMA DISCARDED.** $\mathfrak d$ stored at all $\beta$; recovering $\beta=1$ from any $\beta_p>0$ anchor is exact (`lawReconstructAnalyzeRoundTrip`).
- **L52.4 — DISTORTION MONOTONE.** $\mathcal D(\beta)$ nonincreasing in $\beta$; $\mathcal D(0)=\sum\chi_p$, $\mathcal D(1)=0$.
- **L52.5 — BUDGET FEASIBILITY.** $D^*(\beta^{\mathrm{budget}})=\min_{\mathcal R(\beta)\le\beta^{\mathrm{budget}}}\mathcal D(\beta)$ is nonincreasing and convex (a rate–distortion curve).
- **L52.6 — WATERFILLING ORDER.** $\beta^*$ reveals anchors in strictly descending $\chi_p$; the active set grows monotonically with budget.
- **L52.7 — BLEED MONOTONE (iteration).** $\beta^{\mathrm{budget}}_{k+1}\ge\beta^{\mathrm{budget}}_k\Rightarrow\beta^*_p(k{+}1)\ge\beta^*_p(k)\ \forall p$.
- **L52.8 — TONAL SEPARABILITY.** $V_+\perp V_-$ ⇒ tonal rate $r_L$ and chroma rate $\mathcal R$ decouple; **L is filled to dynamic-range capacity before any chroma is spent** (forced, not policy). Ties `AxisNet.dynamicRangeOf`/`greyOf`.
- **L52.9 — σ-EQUIVARIANCE OF REVEAL (corrected operator).** `sigmaSwapAndReflect (B_β P) == B_β P` — each revealed pair is an exact σ-mirror at every budget. *(Use `sigmaSwapAndReflect`, the `SigmaPairHead` invariant — **not** plain pointwise σ.)*
- **L52.10 — SCAFFOLD-NOT-AUTOMATOR (corrected quantifier).** For every $0<\beta^{\mathrm{budget}}<\mathcal R(1)$ with $|P|\ge2$, the admissible set $\{\beta:\mathcal R(\beta)\le\beta^{\mathrm{budget}}\}$ has nonempty interior, so an authored $\beta_{\mathrm{user}}\ne\beta^*$ exists on a positive-measure set; the spec returns only the predicate $\mathrm{admissible}(\beta_{\mathrm{user}})$ and the dismissible suggestion $\beta^*$, never $\beta_{\mathrm{user}}$. *(At $\beta^{\mathrm{budget}}=0$ the field is forced to $0$ — the no-freedom Phase-L endpoint.)*

### 4.4 The conditional generator $\Gamma_\psi$ (`Spec/Bleed.hs` + `Spec/Reference.hs`)

- **L53.1 — L-PURITY.** $R(m_i)=0$: anchors $m_i=(L_i,0,0)$ are σ-symmetric; `sigmaPairResidual` $=0$ on the $\beta{=}0$ grey palette.
- **L53.2 — OBFUSCATION-CONSISTENCY.** $\forall\beta,\hat\delta:\ \tfrac12\big((m_i+\beta_i\hat\delta_i)+(m_i-\beta_i\hat\delta_i)\big)=m_i$ — A,B cannot move the grey skeleton.
- **L53.3 — Γ σ-EQUIVARIANCE IN LAW.** $p_\psi(\cdot\mid L,\sigma{\cdot}u,\Pi_{\mathrm{asym}}(\sigma{\cdot}\mathrm{ref}))=(\delta\mapsto-\delta)_\#\,p_\psi(\cdot\mid L,u,\Pi_{\mathrm{asym}}(\mathrm{ref}))$. *(A distributional law with its own witness; the deterministic MAP read-out keeps the existing `SigmaEquivariant` instance.)*
- **L53.4 — REFERENCE FIDELITY.** At full reveal the sliced-Wasserstein distance between $\{\beta_i\hat\delta_i\}$ and $\Pi_{\mathrm{asym}}(H_{\mathrm{ref}})$ is minimised; $\mathbb E_\Gamma[\delta_i]\to r_i$ as $\mathrm{ref}\to$ capture (`Loss.fidelityLoss` restricted to $H_{\mathrm{asym}}$).
- **L53.5 — GAN-BY-SCALE LEGALITY.** No adversary on $H_{\mathrm{sym}}$ (L has the Lloyd–Max single-right-answer ceiling); any adversary acts only on $\Pi_{\mathrm{asym}}$ of the rendered image; the L-objective is independent of $\hat\delta$, the A/B-objective independent of $m$.

### 4.5 System theorems

> **Theorem 14 — OBFUSCATION IS LOSSLESS (retention).** $\Omega^{-1}\circ\Omega=\mathrm{id}$ on $\mathcal C$ (and leafwise on $\mathcal P$), with the **discriminating sub-law** that $S\,c$ is achromatic (L45.1). Chroma is banked in $\mathfrak d$, never deleted.
> *Predicate:* `∀c. fromDeviation (toDeviation c) == c` ∧ `∀c. let OKLab _ a b = projectAxis AxisL c in a==0 && b==0`.
> *Proof:* AxisNet coordinate-orthogonality (L45.3–L45.4) + `toDeviation`/`fromDeviation` iso. ∎

> **Theorem 15 — BLEED IS MONOTONE WITH GREY-INVARIANT ENDPOINTS.** For the σ-pair palette, $\lVert\Pi_{\mathrm{chroma}}(B_\beta P)\rVert^2=\sum_i\beta_i^2\lVert\delta_i\rVert^2$ is nondecreasing in each $\beta_i$ and across iterations, while the shown grey energy $\sum_i\lVert m_i\rVert^2$ is **$\beta$-invariant**; $\beta\equiv0\Rightarrow$ pure grayscale, $\beta\equiv1\Rightarrow$ full colour. The revealed-GIF sequence is a chroma-increasing chain **bounded above by the scene ceiling** $\overline r(H_{\mathrm{ref}})$ (Def 55).
> *Predicate:* monotone in $\beta$ and $k$; chroma energy $\le\overline r(H_{\mathrm{ref}})\cdot\lVert P\rVert^2$; grey energy constant.
> *Proof:* L48.2–L48.3 (tone-invariance + monotone chroma) + L52.6 waterfilling descent + golden schedule; ceiling from `sigmaSymFraction`. ∎

> **Theorem 16 — TONE-INVARIANCE ACROSS THE LOOP (the user does the work).** The authored grayscale skeleton is a fixed point of *everything the NN and the reveal gate do*:
> $$\Pi_{\mathrm{grey}}(T\,\mathcal S)\;=\;\Pi_{\mathrm{grey}}(F_U\,\mathcal S)\qquad\forall\beta,\;\forall\hat\delta,\;\forall k,$$
> i.e. only the user's own fold $F_U$ moves the authored grayscale skeleton; $S_\theta$ (scaffold) and $R_\beta$ (reveal) never do.
> *Predicate:* `∀β δ̂. Π_grey (R_β (S_θ S)) == Π_grey S` (anchors fixed).
> *Proof:* $\tfrac12\big((m+\beta\delta)+(m-\beta\delta)\big)=m$ + $V_+\perp V_-$ + `axisSigmaSign AxisL = +1`. ∎

> **Theorem 17 — ENGAGEMENT ATTRACTOR, NOT MSE FIXED POINT.** The loop is **not** a contraction onto an argmin. Its invariant set is an **annular shell**: bounded (the orbit stays in a $\mathcal W$-ball of radius $R_0$ around $\mathrm{ref}$ — *coherence*: tone preserved by Thm 16) yet **fixed-point-avoiding** while the user keeps folding ($\mathcal W(\mathcal S_{k+1},\mathcal S_k)\ge\varepsilon$ whenever $U$ updates — *novelty*: new chroma by Thm 15). The **only** genuine fixed point is degenerate:
> $$T\,\mathcal S^\star=\mathcal S^\star\;\Longleftrightarrow\;(\beta=1)\;\wedge\;(U=\varnothing).$$
> **Novelty-vs-coherence IS the $V_-/V_+$ split:** each iterate differs in the antisymmetric (chroma) part and agrees in the symmetric (tone) part.
> *Predicate:* `T S⋆ == S⋆ ⟺ (β==1 && U==∅)`; off-fixed-point, `𝒲(S_{k+1},S_k) ≥ ε` and `S_{k+1} ∈ Ball R₀ ref`.
> *Proof:* boundedness from the band $\mathcal A$ (Incitement); non-collapse from the band excluding the $\varepsilon$-ball around $\mathcal S_k$; tone-coherence from Thm 16; chroma-novelty from Thm 15. **Trajectory/orbit semantics, not Banach** — and *deliberately so*: contraction onto a point is exactly the MSE automation the spec forbids. ∎

### 4.6 The index-map law (corrected: stability, not invariance)

> **Theorem 18 — TONAL-GROUNDING STABILITY (replaces the false "index invariance").** The deployed index $\mu_{\mathrm{full}}(P)=\arg\min_i\lVert\text{pixel}-c_i\rVert^2$ (`LookNet.nearestIdx`/`Significance.nearestCentroid`, full OKLab distance) is **not** $\beta$-invariant. The honest law: with leaf displacement $\lVert c_i(\beta)-m_i\rVert=\beta_i\lVert\delta_i\rVert$ and per-pixel Voronoi margin $\gamma_{\mathrm{pix}}$ (gap nearest vs 2nd-nearest),
> $$2\cdot\max_i\beta_i\lVert\delta_i\rVert<\gamma_{\mathrm{pix}}\;\Longrightarrow\;\mu_{\mathrm{full}}(B_\beta P)(\text{pix})=\mu_L(\text{pix}),$$
> and there **exist** $\beta,\delta,\text{pix}$ with re-indexing (so strict invariance is provably false). Tone grounds the index *up to a quantified bleed budget*; chroma only re-indexes at near-ties. At $\beta=0$, $\mu_{\mathrm{full}}(P_0)=\mu_L$ (the 256 leaves collapse to 128 grey anchors). ∎

---

## 5. Module map

| Definitions / Laws | Module | Status | Anchors reused |
|---|---|---|---|
| Def 45–47, L45.1–L45.8, Thm 14 | **`Spec/Obfuscation.hs`** (new) | Phase-L, shippable | `AxisNet.projectAxis/toDeviation/fromDeviation`, `axisSigmaSign` |
| Def 48–50b, L48.1–L48.10, Thm 15 | **`Spec/ColorBleed.hs`** (new) | Phase-A/B (inert until chroma) | `AxisNet.AchromaticDeviation`, `PairTree.reconstruct/analyze`, `SigmaDecomp` for $T_t$ bookkeeping |
| Def 51–52, L52.1–L52.10, Thm 18 | **`Spec/ChromaAllocation.hs`** (new) | Phase-A/B | `SigmaPairHead.reconstructPaired/sigmaSwapAndReflect` (**not** `PairTree.pairOffsets`), `MATH.md` Def 16 |
| Def 53, L53.1–L53.5 | **`Spec/Bleed.hs`** (new) + `Spec/Reference.hs` (new) | Phase-A/B | `SigmaPairHead`, `Loss.fidelityLoss`, `AxisNet.axisSigmaSign` |
| Def 54–55 | **`Spec/Reference.hs`** (new) | shippable contract | `SigmaDecomp.asymPart/sigmaSymFraction`, `Bottleneck16.Histogram4096` |
| Def 56–57, Thm 16–17 | **`Spec/BleedLoop.hs`** (new) | contract-first | all four above + `PairTree.goldenDecay` for $\beta_k$ |
| band $\mathcal A$, gallery $\mathcal G$, Thm 17 detail | **`Spec/Incitement.hs`** (new) | heuristic scalars | `Preference.greedyGallery/dppLogDet/btProbability`, `Bures.buresDistanceSq` |

**Unchanged.** `SigmaDecomp.symPart/asymPart` stay exactly as-is — used **only** as the scene-affordance diagnostic (Def 55) and the σ-fold $\Phi$ (Def 47). `AxisNet`, `PairTree`, `SigmaPairHead` are extended-by-import, never modified.

**Properties.** Each new module gets a `Properties.<Name>` test holding its laws (the existing pattern: `Properties.AxisNet`, `Properties.SigmaDecomp`, …). **First law to transcribe, in `Properties.Obfuscation`:** L45.1 + its failing twin on `symPart` — it adjudicates the architecture.

**Codegen + golden-vector implications.** $\Omega$, $\beta_t$, and $B_\beta$ are scalar/field multiplies over existing Haar/eigenspace kernels — **no new numerics**. They are codegen-pinnable like the rest (`spec-codegen`): the bleed gate is a per-pair multiply of $\delta_p$ by $\beta_p$; golden vectors are emitted at $\beta\in\{0,\tfrac12,1\}$ to pin the endpoints + a mid-reveal. $T_t$ (Def 50b) is **bookkeeping only** and must be *excluded* from any "rendered histogram" golden — golden vectors for the rendered GIF come from `histogramFromOKLabs` of the $\beta_t$-pushed leaves, which is the nonlinear path, not $T_t$. Lemma to pin before leaning on resolution-mixing: the commuting square $\Pi_{\mathrm{grey}}\circ\text{leaves}=\text{leaves}\circ(\text{per-pair anchor})$ (palette 128-split ↔ histogram 4096-split are the same eigenspaces at different resolution).

---

## 6. Honest gaps

**Now rigorous (transcribable to `Spec/*.hs` with QuickCheck laws):**

- $\Omega$ as the AxisL obfuscation; **T14** retention + the achromatic-truth discriminator (L45.1). *This is the keystone and it is sound against the source.*
- **T16** tone-invariance across the whole loop — the formal content of "the user does the work."
- $\beta_t$ reveal operator: semigroup $\beta_s\circ\beta_t=\beta_{st}$, σ-equivariance, gamut-nonexpansion, merge-commutation; **T15** monotone bleed with grey-invariant endpoints and scene ceiling.
- Reverse-waterfilling reveal order, the rate–distortion curve $D^*$, tonal separability (L spent before chroma, forced by orthogonality).
- **T18** tonal-grounding *stability* with the margin $\gamma_{\mathrm{pix}}$ (corrects the false "index invariance").
- **T17** non-point engagement attractor — *topologically* (bounded shell, fixed-point-avoiding).

**Still heuristic / just-an-idea (each gap + the minimal thing it needs):**

1. **The conditioning functional $\mathrm{ref}\mapsto\beta_{k+1}$** (G1). Specified only as a monotone partial order ($\beta_{k+1}\succeq\beta_k$) + "waterfilling reveals largest $\chi_p$ first." The concrete map from $\Pi_{\mathrm{asym}}(H_{\mathrm{ref}})$ to the next budget is undefined. *Minimal need:* capture **real loop telemetry first** (per `feedback_dither_abstraction` — do **not** theorize the functional before data exists).
2. **Generative incitement / seduction band width** (G4, the softest). "Each iterate incites the next" is currently topological (T17) plus "novelty in $V_-$, coherence in $V_+$." The band parameters $\varepsilon,\tau,R_0$ that humans actually find seductive are **psychophysical**, not derivable; the only research anchor is processing-fluency (Reber–Schwarz–Winkielman), which is qualitative. *Minimal need:* an empirical novelty-vs-coherence fit on retention data; until then keep the band as a free, law-bounded shape, not a fitted constant.
3. **A ⊥ B (the $V_-$ sub-split)** (G3). Whether the two chroma reveal channels (AxisA, AxisB) are independent opponent projectors (WCS) or coupled (Ou–Luo harmony) is unadjudicated — it decides whether $\Gamma_\psi$'s $V_-$ covariance is block-diagonal. *Minimal need:* a single research-grounded decision (opponent vs harmony), per `feedback_categories_from_research`.
4. **The form of $p_\psi$** (Gaussian-in-$V_-$ with mean $r_i$? flow? MoR-conditioned?) — only its first two σ-antisymmetric moments are law-pinned. *Minimal need:* the GMM/Bures bridge wired so $r(\beta;\chi)$ is well-typed (currently $\chi_p=\lVert\delta_p\rVert^2$ is the $\Sigma\to0$ free-support floor).
5. **$\beta$ semantics** — single scalar vs per-σ-pair vs per-Haar-level, and whether $\beta$ is user-authored, halt-head-emitted (`goldenDecay` prior), or rate-distortion-**knee**-derived. *Minimal need:* the knee target pinned to a law (`L-NN-RESEARCH §3.4`), or a product decision.
6. **Ergodicity on the attractor** — T17 proves a non-point invariant *set* exists, not that the orbit is space-filling on it, nor a measured engagement/retention rate. *Minimal need:* a behavioural metric (candidate: MAP-Elites diversity axis over $\lVert\Pi_{\mathrm{chroma}}\rVert$) and real-user orbit data.
7. **Phase gate** (G5). All of $\beta>0$ is **Phase A/B, not yet shipped**: today's depth-8 grey head has $\delta\equiv0$, so $\beta_t=\mathrm{id}$ and the reveal axis is **inert**. The `SigmaPairHead` 384-DOF head must be wired (un-wired per `NOTES.md`) before any $\beta>0$ ships. The math is shippable contract-first; the behaviour is dormant. *Minimal need:* reconcile the depth-8/256 grey head with the depth-7/128-anchor σ-pair head, then deploy $\Gamma_\psi$.

**No contradiction remains between the operators** once the two-operator discipline ($\Omega$ = AxisL chroma projector; $\Phi=\Pi_{\mathrm{sym}}$ = scene/fold diagnostic) holds — and the fact that five independent derivations each self-corrected onto exactly this discipline is the evidence the system is coherent.
