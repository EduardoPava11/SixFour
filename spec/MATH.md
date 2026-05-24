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

## Bibliography

- Fahmy, H. (2017). *Mathematics of Statistical Modelling: Abstract to
  Specific.* HF Consulting, Waterloo. ISBN 978-0-9917975-8-5.
- Sinkhorn, R., & Knopp, P. (1967). Concerning nonnegative matrices and
  doubly stochastic matrices. *Pacific J. Math.* 21(2), 343–348.
- Cuturi, M. (2013). Sinkhorn distances: Lightspeed computation of
  optimal transport. *NeurIPS 26*.
- Ottosson, B. (2020). *A perceptual color space for image processing.*
  https://bottosson.github.io/posts/oklab/
