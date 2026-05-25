# Mathematical Foundations of SixFour

This document specifies the SixFour pipeline using the framework of

> **Hany Fahmy** (2017). *Mathematics of Statistical Modelling: Abstract to
> Specific*. HF Consulting, Waterloo. ISBN 978-0-9917975-8-5.

cited throughout as **Fahmy §X.Y**. We follow Fahmy's notational conventions
strictly: capital letters for random variables, lower-case for realizations,
**boldface** for vectors and matrices, hat (̂) for estimators and empirical
quantities, and the **Abstract-to-Specific** progression — start from the
random process, end at the executable code.

The goal of this document is not to design a model; it is to establish the
**mathematical vocabulary** the codebase commits to, so every future
extension (including the planned semi-parametric estimator) plugs into a
named slot of the framework rather than inventing its own.

---

## 1. The Process and the Sample Space — Fahmy §1.1

**Definition 1** (the process **W**). A *SixFour capture* is the random
process **W** whose execution consists of:

1. Locking AE / AWB / Focus on a back-camera AVCaptureDevice;
2. Recording **T** = 64 video frames at 20 fps in 10-bit YCbCr (or 8-bit
   BGRA fallback);
3. For each frame, cropping the largest centered square that is a
   multiple of **H** = **W** = 64 px, downsampling to 64×64, linearising
   sRGB, converting to OKLab, applying an unsharp-mask on the L channel.

Each execution of **W** generates one **outcome** ω ∈ Ω in the sense of
Fahmy §1.1 — a single sample from the unknown scene-and-sensor
distribution. The codebase records ω as `result.tiles` of type
`[OKLabTile]` (`SixFour/Capture/CaptureSession.swift:41`).

**Definition 2** (the sample space Ω). The sample space of **W** is the set
of all possible 64×64×64 OKLab tile bursts:

$$
\Omega \;=\; \bigl(\mathrm{OKLab}\bigr)^{T \cdot H \cdot W}
\;=\; \bigl([0,1] \times [-0.4,\,0.4]^2 \bigr)^{262\,144}.
$$

Following the convention of Fahmy §1.1, Ω is **continuous** and
uncountable. The codebase realises one ω ∈ Ω in `OKLabTile` arrays of
length T whose `pixels` field has H·W = 4 096 SIMD3-of-Float OKLab triples
each (`SixFour/Metal/Pipeline.swift:7`).

**Definition 3** (the data random variable). Following Fahmy Definition 5
(p. 5), let

$$
\mathbf{X} \;:\; \Omega \;\longrightarrow\; \mathbb{R}^{T \cdot H \cdot W \cdot 3}
$$

be the **OKLab data tensor**, the multivariate random variable obtained by
stacking every pixel of every frame as a 262 144 × 3 array. **X** is a
*function* on Ω (Fahmy emphasises this on p. 5); it is *not* itself a
number. The codebase passes **X** by reference, never by value: it lives
in GPU memory and on-host only as `[OKLabTile]`.

**Remark 1.** Because **X** is uniformly bounded in OKLab, **X** ∈ L²
in Fahmy's hierarchy 𝔚 ⊂ L² ⊂ L¹ ⊂ ℜ (p. 94). Every estimator we build
below is a transformation of **X** that stays inside L².

---

## 2. The Structural Parameters — Fahmy §3.2 (semi-parametric)

A SixFour GIF is *fully determined* by two structural quantities computed
from one realisation of **X**:

**Definition 4** (palette stack). The palette stack

$$
\mathbf{P} \;\in\; (\mathbb{R}^3)^{T \times K},
\qquad K = 256,
$$

is a 3-axis tensor whose entry $\mathbf{P}_{t,k}$ is the k-th OKLab triple
of the t-th palette. When all T rows agree we call $\mathbf{P}$
**rank-1**; when all T rows are independent we call it **full row rank
T**. The codebase types this as `[[SIMD3<Float>]]` of length T, each of
length K (`Palette/PaletteGenerator.swift:33-35` field `perFramePalettes`).

**Definition 5** (index tensor). The index tensor

$$
\mathbf{I} \;\in\; \{0, 1, \dots, K-1\}^{T \cdot H \cdot W}
$$

records, for every pixel of every frame, which palette slot of
$\mathbf{P}_t$ that pixel is quantised to. The codebase types this as
`[[UInt8]]` of length T, each of length H·W (same struct, field
`frameIndices`).

**Definition 6** (reconstruction). Given $(\mathbf{P}, \mathbf{I})$, the
**estimated data tensor** in the sense of Fahmy §3.3 (p. 85, eq. 3.11) is

$$
\hat{\mathbf{X}}_{t,h,w} \;=\; \mathbf{P}_{t,\, \mathbf{I}_{t,h,w}}.
$$

This is a deterministic function of $(\mathbf{P}, \mathbf{I})$, exactly as
Fahmy's $\hat{Y} = \hat{\beta}_0 + \hat{\beta}_1 X$ is deterministic given
the estimated parameters.

**Definition 7** (the residual). Following Fahmy §3.3 (p. 86, eq. 3.12),
the **residual tensor** is the *observed* difference

$$
\hat{\boldsymbol{\epsilon}} \;=\; \mathbf{X} - \hat{\mathbf{X}},
\qquad \hat{\boldsymbol{\epsilon}} \in \mathbb{R}^{T \cdot H \cdot W \cdot 3}.
$$

Fahmy insists (p. 86) on the distinction between the unobserved **error
term** ε (the scene's unmodelled variation: noise, lens MTF, sensor
quantisation) and the **residual** $\hat{\boldsymbol{\epsilon}}$, which is
*computable* from any realised $\hat{\mathbf{X}}$. We use $\hat{\boldsymbol{\epsilon}}$
exclusively; the unobserved ε is acknowledged but never written.

**Definition 8** (the residual sum of squares). Following Fahmy
§3.3 (p. 87, eq. 3.13), the OKLab **RSS** of a candidate
$(\mathbf{P}, \mathbf{I})$ is

$$
\mathrm{RSS}(\mathbf{P}, \mathbf{I})
\;=\;
\sum_{t=1}^{T}\sum_{h=1}^{H}\sum_{w=1}^{W}
\bigl\| \mathbf{X}_{t,h,w} \;-\; \mathbf{P}_{t,\,\mathbf{I}_{t,h,w}} \bigr\|^2_{\mathrm{OKLab}}.
$$

The Euclidean norm $\|\cdot\|^2$ is exactly the one Fahmy constructs in
§2.2 (p. 50–51) by iterating Pythagoras on the 3-axis OKLab inner
product. The codebase computes $\|\cdot\|^2_{\mathrm{OKLab}}$ pointwise in
`okLabDistanceSquared` (`Color/ColorScience.swift:91`).

---

## 3. The Parameter Space and Its Two Endpoints

The SixFour model is **semi-parametric** in the precise sense of
Fahmy §3.2 (p. 84, Figure 1): the parameter space decomposes as

$$
\Theta \;=\; \Theta_1 \times \Theta_2,
$$

where

- $\Theta_1 \;=\; [0, +\infty]$ is **finite-dimensional** (the
  *tying parameter* θ), and
- $\Theta_2 \;=\; (\mathbb{R}^3)^{T \cdot K}$ is the
  **infinite-dimensional** space of admissible palette stacks.

θ controls how strongly the T per-frame palettes are tied to a single
shared mean. The two SixFour output modes the user can currently choose
are *the two endpoints of $\Theta_1$*:

**Theorem 1** (per-frame is the lower endpoint). Let
$\mathbf{P}^{\mathrm{A}}_t$ be the Stage-A output (variance-cut seed +
Lloyd k-means + Atkinson dither) for frame $t$. Then

$$
\lim_{\theta \to 0^{+}}\; \mathbf{P}(\theta) \;=\; \mathbf{P}^{\mathrm{A}}.
$$

*Proof sketch.* The Sinkhorn-balanced k-means merger
(`Palette/StageBSinkhorn.swift`) builds a transport plan
$\mathbf{T}(\theta) \in \mathbb{R}^{n_C \times K}_{\ge 0}$ with kernel
$\mathbf{K}_{ij} = \exp\!\bigl(-\|x_i - \mu_j\|^2 / \theta\bigr)$. As
$\theta \to 0^{+}$, $\mathbf{K}$ becomes a one-hot indicator at each row's
arg-min, so $\mathbf{T}$ degenerates to a Monge plan, and each centroid
$\mu_k$ reduces to the candidate it was nearest to. Since the candidates
are themselves the Stage-A entries, the merger reduces to the identity on
$\mathbf{P}^{\mathrm{A}}$. ∎

**Theorem 2** (global is the upper endpoint, realised in log-domain).
For all sufficiently large θ, the palette stack $\mathbf{P}(\theta)$
produced by `logDomainSinkhornReference` satisfies

$$
\mathrm{rank}_{\text{row}}\bigl(\mathbf{P}(\theta)\bigr) \;=\; 1,
$$

i.e. every per-frame palette equals one common 256-entry palette.

*Proof sketch.* As $\theta \to \infty$, the log-kernel entries
$\log\mathbf{K}_{ij} = -\|x_i - \mu_j\|^2/\theta \to 0$ uniformly,
so the kernel approaches the uniform matrix. Sinkhorn scaling then
enforces uniform column mass with uniform row mass, which collapses
every centroid to the unweighted mean of all candidates.

**Numerical note.** The *direct-exp* Sinkhorn (`sinkhornReference`)
cannot realise this limit on a finite machine — at θ ≳ 1, $\exp(-C/\theta)$
becomes indistinguishable from $\mathbf{1}$ in IEEE-754, so the
$v[k]=1/\sum_i u_i K_{ik}$ update loses all geometric signal in
catastrophic cancellation. SixFour therefore implements *two*
Sinkhorn variants in `Palette/StageBSinkhorn.swift`:

  * `Params.shared` (θ = 0.05) — direct-exp path, used by `Mode.shared`.
  * `Params.global` (θ = 50)   — log-domain path via `logSumExp`, used
    by `Mode.global`. This is the only path that realises the
    Theorem-2 limit faithfully.

The QuickCheck suite (`spec/test/Properties/Sinkhorn.hs`) verifies
log-domain ≈ direct-exp at θ ∈ {0.05, 0.5} and that θ = 50 collapses
the palette to a tight OKLab ball. ∎

### §3.bis. The middle endpoint, *Shared*

Between the two extremes Theorem 1 and Theorem 2 specify, the user
experiences a *third* practical endpoint that is neither of them:

**Definition 9.bis** (the Shared endpoint). The finite-θ point
θ = 0.05 at which the soft column mass is uniform enough that the
nearest-neighbour hardening collapses to a *shared* (not literally
row-rank-1) palette — every frame's index tensor resolves through one
256-entry global palette, but the centroids are not the global mean.
This is the practical "one shared palette" the user perceives when
they pick the middle mode in `ModeSelector`, and corresponds to
`PaletteGenerator.Mode.shared` with `StageBSinkhorn.Params.shared`.

θ = 0.05 was chosen empirically as the smallest θ for which the
nearest-neighbour remap is dense (low rate of Surjective256 rescue)
and the resulting palette still discriminates highlights from
shadows. It is a *finite-dimensional* parameter of the same
semi-parametric family of Definition 9, not a separate model.

**Definition 9** (the spectrum). The **SixFour spectrum** is the curve

$$
\Theta_1 \;=\; \{\theta : 0 \le \theta \le \infty\},
\qquad \theta \mapsto \bigl(\mathbf{P}(\theta),\,\mathbf{I}(\theta)\bigr).
$$

Its two endpoints are the two GIF modes the device currently ships; its
interior is the continuous family of partial-tying solutions.

**Remark 2** (what changes monotonically with θ). The interior of the
spectrum is monotone in a *soft-rank* sense, not in literal integer row
rank. The continuous monotone is the **transport entropy**

$$
H\bigl(\mathbf{T}(\theta)\bigr) \;=\; - \sum_{i,j} T_{ij}\, \log T_{ij},
$$

which is *strictly increasing* in θ on $(0, \infty)$. Equivalently the
**Sinkhorn divergence** $\mathrm{KL}(\mathbf{T}(\theta) \,\|\,
\mathbf{T}_{\text{uniform}})$ is strictly decreasing in θ. So the
spectrum is *continuously* and *monotonically* parametrised by θ via
either of these scalars; the integer row-rank of $\mathbf{P}$ falls
through the discrete sequence $T, T-1, \dots, 2, 1$ as θ traverses
$[0, \infty]$.

---

## 4. Estimator and Estimate — Fahmy §3.5

For a fixed θ ∈ Θ₁, the pipeline computes the **estimator**

$$
\bigl(\hat{\mathbf{P}}(\cdot;\theta),\,\hat{\mathbf{I}}(\cdot;\theta)\bigr)
\;:\; \Omega \;\longrightarrow\; \Theta_2 \times \{0,\dots,K-1\}^{T \cdot H \cdot W}
$$

defined by Stage A followed by Stage B at tying parameter θ. The
**estimate** for a specific observed $\mathbf{x} = \mathbf{X}(\omega)$ is
the value $\bigl(\hat{\mathbf{P}}(\mathbf{x};\theta),\,
\hat{\mathbf{I}}(\mathbf{x};\theta)\bigr) \in \Theta_2 \times \{0,\dots,K-1\}^{T H W}$.

Fahmy's distinction (p. 88, footnote 2) is preserved:

| Fahmy | SixFour |
|-------|---------|
| $\hat{\beta}$ — the estimator (a formula in $\mathbf{X}, \mathbf{Y}$) | `StageBSinkhorn.merge(perFramePalettes:perFrameIndices:)` as a function |
| $\hat{\beta}$ evaluated on a sample — the estimate (a number) | the returned tuple `(globalPalette, witness)` |

**Theorem 3** (the surjectivity witness — runtime, not theoretical).
For every θ > 0, the Stage-B estimator *attempts* to produce an
index tensor whose image contains every value $\{0, 1, \dots, K-1\}$.
*No theorem* guarantees this: Sinkhorn-Knopp balance (Sinkhorn &
Knopp 1967; Cuturi 2013; Peyré & Cuturi 2018) only gives equal soft
column-mass on the transport plan $\mathbf{T}(\theta)$ — the hard
nearest-neighbour assignment that follows can still skip a centroid.

Soundness here is therefore a *runtime* mechanism with three states:

  1. **Witness held.** `Surjective256(checking:)`
     (`SixFour/Generated/StageContract.swift`) succeeds in O(K).
     Downstream code may trust the invariant for free.
  2. **Rescued.** `Surjective256(checking:)` fails. `forceSurjective`
     reassigns single pixels from oversubscribed slots to fill
     missing ones (O(K + THW)). The reissued witness is genuine.
  3. **Fallback.** The rescue itself cannot complete (no donor slot
     has count > 1 for some missing slot). Stage B returns
     `Result.failure(.surjectivityRescueFailed)`, the renderer falls
     back to per-frame mode (Theorem 1), and the UI banner reports
     `"Sinkhorn merge degenerate — rendered as per-frame instead."`

The Haskell reference returns `sbWitness :: Maybe (Surjective256 ...)`
to make the optionality structural in the spec; the Swift port returns
`Result<MergeResult, StageBError>` to surface the three states
through the renderer. The QuickCheck suite
(`spec/test/Properties/Sinkhorn.hs`) demonstrates that
$\mathit{witness} = \mathit{Nothing}$ is reachable on randomly-sampled
inputs, formally refuting the prior "Sinkhorn guarantees surjectivity"
claim.

**Remark 3** (RSS is the OLS analog). Choosing θ to minimise
$\mathrm{RSS}\bigl(\hat{\mathbf{P}}(\theta), \hat{\mathbf{I}}(\theta)\bigr)$
over $\Theta_1$ is exactly an OLS-style minimisation
(Fahmy §3.5, p. 92, eq. 3.32) — the only differences are that the
"design matrix" $\hat{\mathbf{P}}$ is itself estimated from
$\mathbf{X}$, and the optimisation over the discrete index tensor
$\hat{\mathbf{I}}$ is solved by hard nearest-neighbour assignment rather
than the closed-form normal equation. The Sinkhorn relaxation softens
*only* the assignment, not the OLS principle.

---

## 5. The Spectrum and the Future Estimator (deferred — no code surface)

The deferred neural network has a well-specified type signature inside
this framework but **no code surface** in the current build, per the
project rule "no stubs — fully working and tested code only."

**Definition 10** (the spectrum estimator — purely documentary).
The eventual neural network is a **semi-parametric estimator** in the
exact sense of Fahmy §3.2 (p. 84, lines 1–9). It will map

$$
\hat{\theta} \;:\; \Omega \;\longrightarrow\; \Theta_1 \;=\; [0, \infty]
$$

so that $\hat{\theta}(\mathbf{X})$ is a finite-dimensional estimate of
the best tying parameter for the realised burst. The
infinite-dimensional component $\Theta_2$ is then determined by a
**second-stage** estimator (the existing Stage A + Stage B pipeline)
evaluated at $\hat{\theta}$. This is Fahmy's "we are interested in
estimating $\theta$. So [the infinite-dimensional component] is just an
input to a second-stage estimation problem" verbatim.

When such a trainer ships in `trainer/`, the pipeline's contract will
add a `NetSlot.theta` entry to `Net.hs` and a corresponding mode to
`PaletteGenerator.Mode`. Until then, the three user-facing modes are:

| Mode | θ | Theorem / Definition |
|------|---|----------------------|
| `Mode.perFrame` | 0 | Theorem 1 |
| `Mode.shared`   | 0.05 (direct-exp) | §3.bis Definition 9.bis |
| `Mode.global`   | 50 (log-domain) | Theorem 2 |

Each is realised by *executable, tested code*; the interior
$\theta \in (0, 0.05) \cup (0.05, 50)$ is reachable from
`StageBSinkhorn.Params` programmatically but not from the UI.

---

## 6. Code-Level Correspondences

Every abstract object in this document has *exactly one* runtime
representative. The table is intended to be exhaustive — if a new symbol
appears in future analysis, a matching code object should be added
rather than the document silently extended.

| Abstract object | Type / function | File and line |
|-----------------|-----------------|---------------|
| Process **W** | `CaptureSession.captureBurst` | `Capture/CaptureSession.swift:236` |
| Outcome ω | `CaptureSession.BurstResult` | `Capture/CaptureSession.swift:40` |
| Sample space Ω | the inhabited values of `[OKLabTile]` of length 64 with `side = 64` | `Metal/Pipeline.swift:7` |
| Data tensor **X** | `result.tiles` | `Capture/CaptureSession.swift:41` |
| Palette stack **P** | `PaletteGenerator.Output.perFramePalettes` | `Palette/PaletteGenerator.swift:48` |
| Index tensor **I** | `PaletteGenerator.Output.frameIndices` | `Palette/PaletteGenerator.swift:49` |
| Reconstruction $\hat{\mathbf{X}}$ | implicit in `GIFEncoder.encode` — not materialised on host | `Encoder/GIFEncoder.swift` |
| OKLab norm $\|\cdot\|^2$ | `okLabDistanceSquared` | `Color/ColorScience.swift:91` |
| Parameter space Θ | `(PaletteGenerator.Mode, [[SIMD3<Float>]])` | `Palette/PaletteGenerator.swift:36` |
| Tying parameter θ ∈ Θ₁ | `StageBSinkhorn.Params.theta` | `Palette/StageBSinkhorn.swift:23` |
| Per-frame estimator (Theorem 1) | `Mode.perFrame` (θ = 0) | `Palette/PaletteGenerator.swift` |
| Shared endpoint (§3.bis Definition 9.bis) | `Mode.shared` (θ = 0.05) | `Palette/PaletteGenerator.swift`; `StageBSinkhorn.Params.shared` |
| Global estimator (Theorem 2) | `Mode.global` (θ = 50, log-domain) | `Palette/PaletteGenerator.swift`; `StageBSinkhorn.Params.global` + `logSumExp` path |
| Surjectivity witness | `Surjective256(checking:)` | `Generated/StageContract.swift` |
| Semi-parametric estimator (deferred NN) | not implemented; no slot exists in `NetContract` until a trainer ships | — |
| Cyclic palette stack (§8) | `Cyclic.CyclicStack` | `spec/.../Spec/Cyclic.hs` |
| Transition transport plan $\mathbf{\Gamma}_t$ (§8 Def 13) | `Cyclic.transitionPlan` | `spec/.../Spec/Cyclic.hs` |
| Delta field $\mathbf{\Delta}$ (§8 Def 14) | `Cyclic.alignedDelta` | `spec/.../Spec/Cyclic.hs` |
| Palette / Gaussian entropy (§8 Def 15–16) | `Cyclic.paletteEntropy`, `Cyclic.gaussianColorEntropy` | `spec/.../Spec/Cyclic.hs` |
| Spectral entropy / rate (§8 Def 18–19) | `Cyclic.spectralEntropy`, `Cyclic.entropyRate` | `spec/.../Spec/Cyclic.hs` |
| Holonomy defect (§8 Thm 4) | `Cyclic.holonomyDefect` | `spec/.../Spec/Cyclic.hs` |
| Invariant descriptor $\mathbf{D}$ (§8 Def 20) | `Cyclic.descriptor` | `spec/.../Spec/Cyclic.hs` |

---

## 7. What is and is not in scope

**In scope.** Every transformation that turns ω ∈ Ω into a GIF on
disk. The pipeline holds responsibility for: data acquisition (W),
representation (**X**), parameter estimation
($\hat{\mathbf{P}}, \hat{\mathbf{I}}$), and reconstruction
($\hat{\mathbf{X}}$).

**Out of scope.** The unknown distribution $F_\theta$ of **X**
(the scene-and-sensor distribution); the unobserved error term ε; and
the *choice* of the tying parameter θ when the NN is absent (the user
makes this choice manually through `ComposeView`'s Picker).

**Deferred.** The estimator $\hat{\theta}(\cdot)$ of Definition 10.
The pipeline already exposes the slot it will plug into; building it is
a separate workstream that the math here intentionally constrains
without specifying.

---

## 8. The Cyclic Palette Environment and Its Entropy — Fahmy §9 + App C

§§1–7 treat one realisation $\mathbf{X}(\omega)$ as 64 frames estimated
into a palette stack $\mathbf{P}$. This section reads the *same*
$\mathbf{P}$ as a **looping process**: a GIF repeats, so frame $T-1$
transitions back to frame $0$, and the object of study becomes the
$256$ per-colour trajectories and their cyclic deltas. We import Shannon
entropy and KL exactly as Remark 2 already does (transport entropy); the
*backbone* is Fahmy's time-series chapter (§9: covariance stationarity
Def 38, the difference operator $\Delta X_t$) and his multivariate-normal
covariance (App C, eq. C.8).

### §8.1 The cyclic structure and its two gauges

**Definition 11** (cyclic palette stack). The palette stack
$\mathbf{P} \in (\mathbb{R}^3)^{T\times K}$ of Definition 4, re-indexed by
$t \in \mathbb{Z}_T = \mathbb{Z}/64\mathbb{Z}$, equipped with per-frame
**population weights** $\mathbf{w}_t \in \Delta^{K-1}$ (the normalised
cluster counts; a pmf in the sense of Fahmy Definition 6). As a sequence
in $t$ it is a **stochastic process** (Fahmy §9.1). Typed as
`Cyclic.CyclicStack` of `(Palette k, Weights)`.

**Definition 12** (the two gauges). Two groups act without changing the
decoded loop:

- the **cyclic shift** $\sigma : t \mapsto t+1 \bmod T$, generating
  $\mathbb{Z}_T$ (a GIF has no canonical start frame); and
- the **palette gauge** $S_K$ of §`Spec.Gauge`, relabelling the $K$
  slots per frame (no canonical colour order).

The *environment* is the orbit of $\mathbf{P}$ under
$\mathbb{Z}_T \times S_K$. **Every quantity below is invariant under
this group** — the design constraint that forces transport-defined
deltas (§8.2) over naïve per-index differences.

### §8.2 The delta field — Fahmy §9 difference operator

**Definition 13** (transition transport plan). For consecutive frames
the **plan** $\mathbf{\Gamma}_t \in \mathbb{R}^{K\times K}_{\ge 0}$ is the
entropic-OT (Sinkhorn) coupling of $(\mathbf{P}_t,\mathbf{w}_t)$ and
$(\mathbf{P}_{t+1},\mathbf{w}_{t+1})$ at regularisation $\theta$ — the
same kernel $\mathbf{K}_{ij}=\exp(-\|\cdot\|^2/\theta)$ as Remark 2,
scaled to the weight marginals (`Cyclic.transitionPlan`). $\mathbf{\Gamma}_t$
is $S_K$-equivariant, so all scalars built from it are $S_K$-invariant.

**Definition 14** (delta field). The **delta field** is the cyclic first
difference (Fahmy §9 $\Delta X_t$): under the correspondence induced by
$\mathbf{\Gamma}_t$,

$$
\mathbf{\Delta}_{t,k} \;=\; \mathbf{P}_{t+1,\,k} - \mathbf{P}_{t,k}
\qquad (t \in \mathbb{Z}_T),
$$

the $256$ closed per-colour trajectories of the loop
(`Cyclic.alignedDelta` gives the identity-correspondence case).

**Theorem 4** (closedness ⇔ trivial holonomy). Let
$\mathbf{M}_t = \mathrm{diag}(\mathbf{w}_t)^{-1}\mathbf{\Gamma}_t$ be the
row-stochastic transport map and
$\mathbf{M} = \mathbf{M}_{T-1}\cdots\mathbf{M}_0$ the **holonomy**.
Under a consistent correspondence the per-colour deltas telescope,
$\sum_{t\in\mathbb{Z}_T}\mathbf{\Delta}_{t,k}=0$ for all $k$, **iff**
$\mathbf{M}=\mathbf{I}$. *Proof sketch.* A telescoping sum on a cycle
closes exactly when each colour returns to itself, i.e. the composed
correspondence is the identity. ∎ The **holonomy defect**
$(K-\operatorname{tr}\mathbf{M})/K \ge 0$ is the computable proxy
(`Cyclic.holonomyDefect`); it is a *trace*, hence
conjugation-invariant, hence $\mathbb{Z}_T$-invariant — the start frame
cannot be read off it.

### §8.3 The entropy functionals (imported; grounded in Fahmy)

**Definition 15** (palette entropy). $H(\mathbf{P}_t) = -\sum_k w_{t,k}\log w_{t,k}$
(natural log). $S_K$-invariant; $0\le H\le \log K$ (`Cyclic.paletteEntropy`).

**Definition 16** (Gaussian colour entropy). With $\mathbf{\Sigma}_t$ the
weighted $3\times3$ OKLab covariance (Fahmy App C eq. C.8), the
differential entropy of the Gaussian fit is
$H_g(\mathbf{P}_t) = \tfrac12\log\!\big((2\pi e)^3 |\mathbf{\Sigma}_t|\big)$
(`Cyclic.gaussianColorEntropy`). This is the **bridge** from Fahmy's
covariance machinery to entropy; $|\mathbf{\Sigma}_t|$ is a closed-form
$3\times3$ determinant.

**Definition 17** (transition cost / entropy).
$C_t = \sum_{i,j}\Gamma_{t,ij}\,\|\mathbf{P}_{t,i}-\mathbf{P}_{t+1,j}\|^2$
and $H(\mathbf{\Gamma}_t) = -\sum_{ij}\Gamma_{t,ij}\log\Gamma_{t,ij}$.
The cyclic total $\sum_t C_t$ is the literal "environment seen through
the $256$ deltas."

**Definition 18** (spectral entropy). For a gauge-invariant scalar
trajectory $f:\mathbb{Z}_T\to\mathbb{R}$ (e.g. $H(\mathbf{P}_t)$ or
$C_t$), let $\hat f$ be its DFT; the **spectral entropy** is the Shannon
entropy of the normalised power $|\hat f_k|^2$ over the AC bins. It is
$\mathbb{Z}_T$-**invariant** (a cyclic shift is a phase rotation, leaving
$|\hat f_k|$ fixed). A still loop scores $0$; a single-frequency loop is
near-$0$ (energy in one bin); a broadband/irregular loop approaches
$\log(T{-}1)$ (`Cyclic.spectralEntropy`).

**Definition 19** (entropy rate). The Kolmogorov–Szegő rate of the
covariance-stationary cyclic Gaussian process (Fahmy §9 stationarity),
estimated from the AC periodogram (`Cyclic.entropyRate`).

### §8.4 The invariant descriptor (the deferred-NN feature seam)

**Definition 20** (the descriptor). The **descriptor**
$\mathbf{D}\in\mathbb{R}^{16}$ collects $\mathbb{Z}_T\times S_K$-invariant
scalars: $\{\mathrm{mean}_t,\mathrm{sd}_t\}$ of $H(\mathbf{P}_t)$ and
$H_g(\mathbf{P}_t)$; total and mean transport cost; mean
$H(\mathbf{\Gamma}_t)$; spectral entropy of $H(\mathbf{P}_t)$, of
$H_g(\mathbf{P}_t)$ and of $C_t$; the entropy rate of $H(\mathbf{P}_t)$;
the holonomy defect; and the first four AC power magnitudes of
$H(\mathbf{P}_t)$ (`Cyclic.descriptor`, `Cyclic.descriptorDim = 16`).

**Theorem 5** (invariance). $\mathbf{D}(\sigma\cdot\mathbf{P})=\mathbf{D}(\mathbf{P})$
and $\mathbf{D}(\tau\cdot\mathbf{P})=\mathbf{D}(\mathbf{P})$ for every
cyclic shift $\sigma\in\mathbb{Z}_T$ and per-frame relabel $\tau\in S_K$.
*Proof sketch.* Each component is built only from $S_K$-invariant
per-frame scalars (Def 15–17) and $\mathbb{Z}_T$-invariant aggregate /
spectral / trace functionals (Def 18–19, Thm 4). ∎ Verified at 100
QuickCheck cases each in `Properties.Cyclic` (laws
`lawDescriptorGaugeInvariant`, `lawDescriptorCyclicShiftInvariant`).

**Remark 4** (this is Definition 10's input). $\mathbf{D}$ is the
concrete, fixed-dimensional input contract for the deferred
semi-parametric estimator $\hat\theta$ of Definition 10 — and, more
generally, for a categorisation estimator over the loop. It commits no
code surface beyond the reference functions, per the no-stubs rule; no
trainer consumes it yet.

---

## Bibliography

- Fahmy, H. (2017). *Mathematics of Statistical Modelling: Abstract to
  Specific.* HF Consulting, Waterloo. ISBN 978-0-9917975-8-5.
- Sinkhorn, R., & Knopp, P. (1967). Concerning nonnegative matrices and
  doubly stochastic matrices. *Pacific J. Math.* 21(2), 343–348.
- Cuturi, M. (2013). Sinkhorn distances: Lightspeed computation of
  optimal transport. *NeurIPS 26*.
- Cover, T. M., & Thomas, J. A. (1991). *Elements of Information Theory.*
  Wiley. (Shannon entropy, relative entropy, spectral/entropy rate —
  the §8 information-theoretic tools Fahmy does not cover.)
- Ottosson, B. (2020). *A perceptual color space for image processing.*
  https://bottosson.github.io/posts/oklab/
