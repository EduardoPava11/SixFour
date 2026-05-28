# Mathematical Design of the SixFour Look-Network

> **PIVOT (2026-05-27) — continuous-OKLab redesign. Read this first.**
> The look-net no longer routes through the **11 Berlin–Kay categories**. The 88-float
> category code, the hand-set `LAB_HIERARCHY = [4,2,1]` metric, and the category
> complement map were a *fidelity category-error* (Berlin–Kay/Zaslavsky is a colour-
> **naming** result, not a palette-**collapse** result; OKLab is already perceptual).
> They are **deleted**. The shipped contract is now:
> - **Substrate** = the continuous 256-component OKLab **Gaussian mixture** the device
>   already computes (`ClusterStatistics`) → `SixFour.Spec.GMM` (per-component token
>   width **10**, replacing the 88 code).
> - **Collapse** = the **Wasserstein-2 / Bures** barycenter (`SixFour.Spec.Bures`);
>   k-means stays as the free-support floor (Thm 9). Bures→Euclidean as Σ→0 is the law
>   tying the two together.
> - **Metric** = Euclidean OKLab (identity); learned PSD is the only sanctioned upgrade.
> - **Complement** = the continuous σ `(L,a,b)→(L,−a,−b)` (`PairTree.sigmaReflect`) — no
>   category lookup. The Haar pair-tree output (§ below, `Spec.PairTree`) is unchanged.
> - **Personalization** = continuous preference-GP + DPP gallery (`SixFour.Spec.Preference`),
>   replacing the deleted category-grid `Competition`.
> - **L7** (§8 table) is **global surjectivity** (⋃ₜ used = K), not per-frame completeness.
>
> The **Haskell `Spec.*` modules are the source of truth** (112 QuickCheck laws green);
> §§2–3, 5–8 below are retained for their transport/beauty math but their *categorical*
> framing is superseded by the modules named above.

This document is the **formal, citation-grounded design** of the SixFour
look-network — the model that collapses the 64 per-frame palettes of a capture
into one global palette of **128 complement-symmetric colour pairs** plus
per-frame index maps, producing the final global-palette GIF. It is written
*contract-first*: definitions and laws come first; the neural network is one
**inhabitant** of that contract (the pattern of `Spec.Look`). It is the blueprint
the Haskell spec modules will mirror; it commits no code surface beyond the
reference functions (the no-stubs rule).

It **continues `MATH.md`**: numbering resumes at Definition 21 / Theorem 6, and
it reuses Definition 11 (cyclic palette stack), Definition 20 (the 16-D
descriptor), and the two gauges $\mathbb{Z}_T\times S_K$ of Definition 12. All
distances are in OKLab (`Spec.Color`, Ottosson 2020). Empirical anchors are the
shipped `studio/FINDINGS.md` and `studio/CATEGORY_FINDINGS.md`.

> **Reading guide.** §1 fixes spaces and the metric. §2–§3 build the *category*
> and *pair* structure (the trainable, symmetric substrate). §4–§5 state the
> *objective* (a constrained Wasserstein barycenter regularised by beauty and
> diversity). §6 gives the *architecture* (the inhabitant). §7 the loss. §8 the
> ten contract **Laws** (each QuickCheck-able). §9 the on-device realisation.
> §10 the bibliography, cross-referenced to every construct.

---

## 1. Spaces, measures, and the importance-weighted metric

**Definition 21** (palette measure). The OKLab gamut is
$\mathcal{L} = [0,1]\times[-0.4,0.4]^2\subset\mathbb{R}^3$. A frame palette is a
discrete probability measure
$\mu_t=\sum_{k=1}^{K} w_{t,k}\,\delta_{c_{t,k}}$ with $K=256$, support
$c_{t,k}\in\mathcal{L}$, weights $w_t\in\Delta^{K-1}$ (the normalised cluster
populations of Definition 11). A **capture** is the cyclic tuple
$\boldsymbol\mu=(\mu_0,\dots,\mu_{T-1})$, $T=64$, taken modulo the gauge group
$\mathbb{Z}_T\times S_K$ (Definition 12). Typed `Cyclic.CyclicStack`.

**Definition 22** (LAB importance metric). For a symmetric positive-definite
$M\in\mathbb{R}^{3\times3}$ define the Mahalanobis form
$$
d_M(x,y)^2 \;=\; (x-y)^\top M\,(x-y).
$$
The **L > a > b hierarchy** is the diagonal instance
$M_\star=\operatorname{diag}(w_L,w_a,w_b)$ with $w_L>w_a>w_b>0$ (shipped
`wcs::LAB_HIERARCHY` $=(4,2,1)$). $M_\star$ is the fixed, diagonal special case
of the learnable PSD metric $M=LL^\top$ ($L$ lower-triangular) of Weinberger &
Saul (2009), already the parameterisation in `trainer/train_metric.py`.

**Theorem 6** (metric well-formedness). For any $M\succeq 0$, $d_M$ is a
pseudometric (symmetry, triangle inequality, $d_M(x,x)=0$); for $M\succ0$ it is
a metric. For $M_\star$ diagonal with strictly decreasing entries, the per-axis
contribution is strictly ordered: a displacement $\epsilon$ along $L$ costs
$w_L\epsilon^2 > w_a\epsilon^2 > w_b\epsilon^2$. *Proof.* $M=LL^\top$ gives
$d_M(x,y)=\|L^\top(x-y)\|_2$, a seminorm; positivity of eigenvalues upgrades it
to a norm. The ordering is immediate from the diagonal. $\square$ (`Spec.OKLabMetric`;
mirrors `color::dist_sq_weighted`, test `hierarchy_orders_axes`.)

---

## 2. The category layer — an information-bottleneck-optimal code

The look-network does **not** train on the $T\cdot K = 16{,}384$ raw colours of a
capture (per-capture, unlabelled, variable). It trains on a fixed-size code over
colour **categories**, which are taken from research, never invented.

**Definition 23** (Berlin–Kay categories and foci). The category set
$\mathcal{C}=\{$red, orange, yellow, green, blue, purple, pink, brown, black,
white, gray$\}$, $|\mathcal{C}|=11$ (Berlin & Kay 1969). Each $c\in\mathcal{C}$
has an OKLab **focus** $f_c\in\mathcal{L}$, taken as the Sturges & Whitfield
(1995, Table II) fastest-consensus Munsell chip, resolved against the 330 World
Color Survey chips (Kay et al.) and mapped to OKLab through
`color::cie_lab_c_to_oklab` (CIE L\*a\*b\* under Illuminant C → Bradford C→D65 →
linear sRGB → M1/M2). Typed `wcs::BasicTerm`, `wcs::focal_color`.

**Definition 24** (category quantiser). Hard assignment
$\kappa(x)=\arg\min_{c\in\mathcal{C}}\|x-f_c\|_2^2$ (`wcs::category_of`); soft
assignment, with inverse-temperature $\beta>0$,
$$
q(c\mid x)\;=\;\frac{\exp(-\,d_M(x,f_c)^2/\beta)}{\sum_{c'}\exp(-\,d_M(x,f_{c'})^2/\beta)} .
$$

**Definition 25** (category descriptor). For a capture $\boldsymbol\mu$ pooled
into weighted candidates $\{(x_i,\omega_i)\}$, the **descriptor** is the fixed
$11\times d$ array whose $c$-th row is
$\big(\rho_c,\ \bar x_c,\ \Sigma_c,\ \mathrm{pr}(\Sigma_c)\big)$:
population share $\rho_c=\tfrac{1}{\Omega}\sum_{i:\kappa(x_i)=c}\omega_i$
($\Omega=\sum_i\omega_i$), weighted mean $\bar x_c$, OKLab covariance $\Sigma_c$,
and participation ratio $\mathrm{pr}(\Sigma_c)=(\sum\lambda)^2/\sum\lambda^2\in[1,3]$.
Capture-invariant by construction. Typed `category::CategoryDescriptor`;
occupancy $\rho=(\rho_c)_c$ is `category::category_occupancy`.

**Theorem 7** (IB-optimality of the code; Zaslavsky–Kemp–Regier–Tishby 2018).
Let $X$ be a colour, $U$ its perceptual referent, and $C$ the category. Among all
stochastic encoders $q(c\mid x)$ the Berlin–Kay partition lies near the optimal
frontier of the **information bottleneck** (Tishby–Pereira–Bialek 1999)
$$
\min_{q(c\mid x)} \; I(X;C)\;-\;\beta\,I(C;U),
$$
trading lexicon **complexity** $I(X;C)$ against **accuracy** $I(C;U)$. *Proof.*
Empirical; Zaslavsky et al. show measured colour-naming systems achieve
near-optimal IB compression across 110+ languages. $\square$ **Consequence.** The
descriptor of Definition 25 is a *principled lossy code* of the capture's colour
content — the rigorous warrant for "categories are what we can train on": the
input is the IB-compressed sufficient statistic, not arbitrary binning.
(Cross-checks the optimal-partition result of Regier–Kay–Khetarpal 2007.)

---

## 3. The symmetric pair structure (the 128 : 128 palette)

**Definition 26** (chroma reflection). $\sigma:\mathcal{L}\to\mathcal{L}$,
$\sigma(L,a,b)=(L,-a,-b)$. $\sigma$ is an isometry of $d_M$ for any diagonal $M$,
an **involution** ($\sigma^2=\mathrm{id}$), and generates a $\mathbb{Z}_2$ point
group acting on $\mathcal{L}$ and (via $f$) on $\mathcal{C}$.

**Definition 27** (pairing operator). The **complement** of a category is the
category of its reflected focus, matched under the hierarchy metric:
$$
\pi(c)\;=\;\arg\min_{c'\in\mathcal{C}} d_{M_\star}\!\big(\sigma(f_c),\,f_{c'}\big)
\qquad (\texttt{wcs::complement\_category}).
$$
Lightness dominates the match ($w_L$ largest), so a light colour pairs with a
light one — the intended rule (user decision, 2026-05-25).

**Theorem 8** (measured complement structure). Under $M_\star=(4,2,1)$ the map
$\pi$ is: red$\leftrightarrow$blue, orange$\to$green, yellow$\to$white,
green$\to$pink, purple$\to$blue, pink$\to$green, brown$\to$brown, and
black/white/gray fixed. Hence $\pi$ has **7 of 11** terms with a distinct
opponent and is **not** a global involution, but $\sigma$ (Definition 26) *is*,
and $\pi\circ\pi=\mathrm{id}$ on the subset $\mathcal{C}_\circ=\{$red, blue$\}$
of mutually-paired chromatic terms and trivially on the four self-fixed terms.
*Proof.* By computation (`category-explore`, `CATEGORY_FINDINGS.md §1`); the
self-fixity of neutrals follows from $a,b\approx 0\Rightarrow\sigma\approx\mathrm{id}$.
$\square$ This is why **L5 is a conditional law** (§8).

**Definition 28** (paired global palette). The global palette $G\in\mathcal{L}^{256}$
is organised as 128 ordered pairs $G=\{(a_i,b_i)\}_{i=1}^{128}$: $a_i$ a
**faithful anchor** (a scene colour, possibly user-pinned), $b_i$ its **partner**
(a symmetric mate per §6). A pair doubles as a *dither axis*: spatial/temporal
dithering of $(a_i,b_i)$ realises the intermediate tones between them.

> **Aesthetic basis.** Symmetry is processed more fluently and judged more
> beautiful (Reber–Schwarz–Winkielman 2004); $\sigma$ makes "symmetric" an exact
> OKLab operation rather than a heuristic.

---

## 4. The collapse as a constrained Wasserstein barycenter

**Definition 29** ($M$-Wasserstein-2). For measures $\mu,\nu$ on $\mathcal{L}$
with ground cost $d_M^2$,
$W_2^M(\mu,\nu)^2=\min_{\gamma\in\Pi(\mu,\nu)}\int d_M(x,y)^2\,\mathrm{d}\gamma(x,y)$,
$\Pi$ the couplings with marginals $\mu,\nu$. The **entropic** form adds
$+\theta\,\mathrm{KL}(\gamma\,\|\,\mu\otimes\nu)$, solved by Sinkhorn iteration
(Cuturi 2013; the same kernel as `Cyclic.transitionPlan`, Definition 13).

**Definition 30** (the collapse). Let $\nu_G$ be the measure induced on $G$ by
nearest-$d_M$ assignment of the candidates. The global palette is the
weighted **free-support Wasserstein barycenter** (Agueh–Carlier 2011) of the 64
frame measures:
$$
G^\star \;=\; \arg\min_{G\in\mathcal{L}^{256}} \;\sum_{t=0}^{T-1}\lambda_t\,
W_2^M(\mu_t,\nu_G)^2,\qquad \textstyle\sum_t\lambda_t=1.
$$

**Theorem 9** (k-means is the fidelity floor). The unregularised, free-support
minimiser of Definition 30 under $M=I$ coincides with the fixed points of
population-weighted Lloyd $k$-means on the pooled candidates
($\texttt{collapse::weighted\_kmeans}$). *Proof.* For squared cost the
free-support barycenter of empirical measures is the $k$-means objective on the
union of supports weighted by $\lambda_t w_{t,k}$ (Cuturi–Doucet 2014, §3).
$\square$ Empirically this floor is $1\!\times\!10^{-4}\!-\!9\!\times\!10^{-4}$
OKLab² (`FINDINGS.md`); the *learned* look is a controlled deviation **from**
this floor, not an escape of it. A network may amortise $G^\star$ directly
(Korotin et al. 2022, Wasserstein iterative barycenter networks).

---

## 5. Beauty and diversity functionals

**Definition 31** (pair harmony — Ou & Luo 2006). In OKLCh
($C=\sqrt{a^2+b^2}$, $h=\operatorname{atan2}(b,a)$) the two-colour harmony of a
pair is the additive
$$
\mathrm{CH}(a_i,b_i)=H_C+H_L+H_H,
$$
with chromatic $H_C$, lightness $H_L=H_{L\text{sum}}+H_{\Delta L}$, and hue $H_H$
terms, each a $\tanh$-saturating function of the OKLCh differences (coefficients
transcribed from Ou & Luo 2006). Total palette beauty
$B(G)=\sum_{i=1}^{128}\mathrm{CH}(a_i,b_i)$. Pair harmony is **relational** — it
is not the sum of single-colour preferences (Schloss & Palmer 2011) — which is
why the output primitive is the pair, not the point.

**Definition 32** (coverage / diversity). Let $K_G\in\mathbb{R}^{256\times256}$,
$(K_G)_{ij}=\exp(-d_M(g_i,g_j)^2/\ell^2)$, be a PSD similarity kernel. The
**diversity** is the determinantal-point-process log-volume
$\mathrm{Cov}(G)=\log\det(K_G+\varepsilon I)$ (Kulesza–Taskar 2012): large when
$G$ spans a large OKLab volume. (Equivalent headline metric: the shipped
gamut-ellipsoid volume / occupied-bin coverage, `Spec.Coverage`.)

---

## 6. The architecture (the contract inhabitant)

The look-network $\Phi$ maps (category descriptor, user controls) to a paired
palette $G$. It factors $\Phi = D\circ R\circ E$ with a differentiable
assignment $A$.

**Definition 33** (set encoder $E$). $E$ is permutation-invariant over the 11
category tokens. Reference form is Deep Sets (Zaheer et al. 2017),
$E(X)=\rho\big(\sum_{c}\rho_c\,\phi(x_c)\big)$, optionally Set-Transformer
ISAB+PMA (Lee et al. 2019), which is a **universal approximator of
permutation-invariant maps**. $E$ is additionally **$\mathbb{Z}_2$-equivariant**
under the colour reflection: $E(\sigma\!\cdot\!X)=\sigma\!\cdot\!E(X)$
(Cohen–Welling 2016) — a structural prior, not a learned regularity.

**Definition 34** (adaptive-compute core $R$ — PonderNet over a recursive block).
A shared block is iterated, $s_n=f_\theta(s_{n-1},E(X))$ (Mixture-of-Recursions,
Bae et al. 2025; lineage: Universal Transformer, Dehghani et al. 2019;
Mixture-of-Depths, Raposo et al. 2024). A halting unit emits Bernoulli
$\lambda_n=\Lambda_\theta(s_n)\in[0,1]$; the **halting distribution** is
$$
p_n=\lambda_n\prod_{j=1}^{n-1}(1-\lambda_j),\qquad \sum_{n\ge1}p_n=1,
$$
and the core output is the mixture $\hat y=\sum_n p_n\,\hat y_n$ (PonderNet,
Banino et al. 2021; unbiased, low-variance gradients, unlike ACT/Graves 2016).
The **expected ponder cost** $\mathbb{E}[N]=\sum_n n\,p_n$ is the user
**compute/quality dial** and the on-device latency knob.

**Definition 35** (residual pair decoder $D$). With conditioning
$z=(E\text{-context},\ \texttt{LookCode}\in[-1,1]^4,\ \text{ponder state})$ injected
by FiLM (Perez et al. 2018, per-feature affine $\gamma(z)\odot h+\beta(z)$), the
partner of anchor $a_i$ is
$$
b_i \;=\; \operatorname{clamp}_{\mathcal{L}}\!\Big(\,\sigma(a_i)\;+\;s\cdot\tanh\big(\delta_i(z)\big)\Big),
$$
a bounded residual on the **exact symmetry** $\sigma$ of Definition 26. Anchors
$\{a_i\}$ are the constrained barycenter of Definition 30 (user pins frozen).

**Definition 36** (differentiable assignment $A$). Training uses the soft
assignment $A_{t,k}=\operatorname{softmax}_j(-d_M(c_{t,k},g_j)/\tau)$ with
Gumbel-softmax sampling (Jang et al. 2017; Maddison et al. 2017) annealing
$\tau\!\downarrow\!0$; inference uses hard $\arg\min$ with straight-through
gradients (Bengio et al. 2013; VQ-VAE, van den Oord et al. 2017). $A$ yields the
per-frame $\texttt{u8}$ index maps that, with $G$, rebuild the GIF.

---

## 7. The loss functional

**Definition 37** (objective). The network is trained self-supervised (no labels
for v1) on
$$
\mathcal{L}_\Phi \;=\; \alpha\,\underbrace{\mathrm{S}_\theta(\nu_G,\textstyle\frac1T\sum_t\mu_t)}_{\text{fidelity}}
\;-\;\beta\,\underbrace{B(G)}_{\text{beauty}}
\;-\;\gamma\,\underbrace{\mathrm{Cov}(G)}_{\text{diversity}}
\;+\;\delta\,\underbrace{\textstyle\sum_t C_t}_{\text{flicker}}
\;+\;\zeta\,\underbrace{\mathrm{KL}\!\big(p\,\|\,\mathrm{Geom}(\lambda_p)\big)}_{\text{ponder}}
\;+\;\eta\,\underbrace{\big\|D(\sigma\!\cdot\!z)-\sigma\!\cdot\!D(z)\big\|^2}_{\text{equivariance}} .
$$
Here $\mathrm{S}_\theta$ is the **debiased Sinkhorn divergence** (Feydy et al.
2019), which is symmetric, **positive-definite**, and metrises weak convergence
— so "stay near the barycenter" is a genuine metric, not a proxy; the flicker
term $\sum_t C_t$ is the cyclic transport cost of Definition 17 (`Cyclic`); the
ponder KL is the PonderNet regulariser with geometric prior $\lambda_p$.

---

## 8. The contract (ten laws → QuickCheck properties)

Each law is stated for the Haskell spec as (inputs; predicate; tolerance). The
decoder satisfies L1–L4, L6 **by construction** (residual ⇒ L1; $\tanh$ ⇒ L2;
$\operatorname{clamp}$ ⇒ L3; spectral-norm-bounded layers ⇒ L4; $\sigma$-built
partner + equivariant $E$ ⇒ L6), so they hold for *any* weights.

| # | Law | Statement | Mirrors |
|---|---|---|---|
| **L1** | Neutral identity | $D(G_0,\mathbf{0},\cdot)=G_0$ (LookCode $0$ ⇒ faithful collapse, the reset) | `Look` neutral=identity |
| **L2** | Boundedness | $\|b_i-a_i\|\le s_{\max}$ for all $i$ | `Look` boundedness |
| **L3** | Gamut closure | $G\subset\mathcal{L}$ | `Look` gamut closure |
| **L4** | Lipschitz | $\|D(z)-D(z')\|\le \mathrm{Lip}\cdot\|z-z'\|$ | `Look` continuity |
| **L5** | Conditional pairing involution | $\pi(\pi(c))=c$ for $c\in\mathcal{C}_\circ$; $\pi(c)=c$ for neutrals (Thm 8) | new `Spec.Pair` |
| **L6** | Colour equivariance | $D(\sigma\!\cdot\!z)=\sigma\!\cdot\!D(z)$ | new `Spec.Pair` |
| **L7** | Completeness/surjectivity | every frame uses all 256 indices (`CompleteVoxelVolume`) | `Significance` |
| **L8** | Halting normalisation | $\sum_{n}p_n=1$ and $p_n\ge0$ (Def 34) | new `Spec.Halting` |
| **L9** | Barycenter Fréchet-mean | $G^\star$ minimises $\sum_t\lambda_t W_2^M(\mu_t,\nu_G)^2$ (Def 30, Thm 9) | new `Spec.Barycenter` |
| **L10** | Metric PSD | $M\succeq0$; $M_\star$ axis-ordered (Thm 6) | new `Spec.OKLabMetric` |

---

## 9. On-device realisation (placement is part of the contract)

**Definition 38** (engine split). The dynamic look-net $\Phi$ (encoder +
MoR/PonderNet core + pair decoder; batch-1, data-dependent control flow) runs on
**CPU-SIMD** (`burn-ndarray` + Accelerate/AMX, NEON hot loops); the dense
per-pixel assignment/dither (Def 36 over $T\!\times\!4096$ pixels) runs on
**GPU-Metal**; the **ANE is excluded**. *Justification.* The ANE requires static
graphs and is bandwidth-bound on short sequences (Apple ML 2022); GPUs negate
early-exit savings and underutilise at batch-1 (dynamic-network literature);
adaptive control flow is free on CPU, and on a live-camera app the GPU is already
committed to preview + Liquid-Glass rendering. The boundary is exact: everything
at palette/category scale ($\le 330$) is CPU, only the $4096\!\times\!64$
per-pixel stage is GPU. The interactive loop (re-run on every pin / slider /
ponder change) never touches the GPU.

---

## 10. Bibliography (cross-referenced to constructs)

*Colour space & metric.* Ottosson, B. (2020). *A perceptual color space for image
processing.* (Def 21.) — Weinberger, K. & Saul, L. (2009). *Distance Metric
Learning for Large Margin Nearest Neighbor Classification.* JMLR 10:207–244.
(Def 22, L10.)

*Categories.* Berlin, B. & Kay, P. (1969). *Basic Color Terms.* — Kay, P. et al.
*The World Color Survey.* CSLI. — Sturges, J. & Whitfield, T. W. A. (1995).
*Locating basic colours in the Munsell space.* Color Res. Appl. 20(6):364–376.
(Def 23.) — Regier, T., Kay, P. & Khetarpal, N. (2007). *Color naming reflects
optimal partitions of color space.* PNAS 104(4):1436–1441. — Zaslavsky, N., Kemp,
C., Regier, T. & Tishby, N. (2018). *Efficient compression in color naming and its
evolution.* PNAS 115(31):7937–7942. — Tishby, N., Pereira, F. & Bialek, W. (1999).
*The information bottleneck method.* (Thm 7.)

*Optimal transport / barycenters.* Agueh, M. & Carlier, G. (2011). *Barycenters
in the Wasserstein space.* SIAM J. Math. Anal. 43(2):904–924. — Cuturi, M. (2013).
*Sinkhorn distances.* NeurIPS 26. — Cuturi, M. & Doucet, A. (2014). *Fast
computation of Wasserstein barycenters.* ICML 32. (Def 30, Thm 9.) — Feydy, J.
et al. (2019). *Interpolating between Optimal Transport and MMD using Sinkhorn
Divergences.* AISTATS 22. (Def 37.) — Korotin, A. et al. (2022). *Wasserstein
Iterative Networks for Barycenter Estimation.* NeurIPS. (Def 30.)

*Beauty & diversity.* Ou, L.-C. & Luo, M. R. (2006). *A colour harmony model for
two-colour combinations.* Color Res. Appl. 31(3):191–204. (Def 31.) — Schloss, K.
& Palmer, S. (2011). *Aesthetic response to color combinations.* Atten. Percept.
Psychophys. 73:551–571. — O'Donovan, P., Agarwala, A. & Hertzmann, A. (2011).
*Color compatibility from large datasets.* ACM TOG 30(4). — Kulesza, A. & Taskar,
B. (2012). *Determinantal point processes for machine learning.* Found. Trends
ML 5(2–3). (Def 32.) — Reber, R., Schwarz, N. & Winkielman, P. (2004).
*Processing fluency and aesthetic pleasure.* PSPR 8(4):364–382. (Def 28.)

*Architecture.* Zaheer, M. et al. (2017). *Deep Sets.* NeurIPS. — Lee, J. et al.
(2019). *Set Transformer.* ICML. (Def 33.) — Cohen, T. & Welling, M. (2016).
*Group equivariant convolutional networks.* ICML. (Def 33, L6.) — Graves, A.
(2016). *Adaptive Computation Time for RNNs.* arXiv:1603.08983. — Dehghani, M. et
al. (2019). *Universal Transformers.* ICLR. — Raposo, D. et al. (2024).
*Mixture-of-Depths.* arXiv:2404.02258. — Bae, S. et al. (2025).
*Mixture-of-Recursions.* arXiv:2507.10524. — Banino, A., Balaguer, J. & Blundell,
C. (2021). *PonderNet: Learning to Ponder.* arXiv:2107.05407. (Def 34, L8.) —
Perez, E. et al. (2018). *FiLM: Visual Reasoning with a General Conditioning
Layer.* AAAI. (Def 35.) — van den Oord, A. et al. (2017). *Neural Discrete
Representation Learning (VQ-VAE).* NeurIPS. — Jang, E., Gu, S. & Poole, B. (2017).
*Categorical Reparameterization with Gumbel-Softmax.* ICLR. — Maddison, C., Mnih,
A. & Teh, Y. W. (2017). *The Concrete Distribution.* ICLR. — Bengio, Y., Léonard,
N. & Courville, A. (2013). *Estimating or propagating gradients through stochastic
neurons.* arXiv:1308.3432. (Def 36.)

*On-device.* Apple Machine Learning Research (2022). *Deploying Transformers on
the Apple Neural Engine.* (Def 38.)

*Inherited from `MATH.md`:* Fahmy (2017); Sinkhorn & Knopp (1967); Cover & Thomas
(1991).
