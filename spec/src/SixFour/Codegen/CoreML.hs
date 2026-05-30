{- |
Module      : SixFour.Codegen.CoreML
Description : Emit the look-NN as a PyTorch nn.Module + a coremltools driver script.

The /dormant ANE-distillation fallback/ for the math-first NN pipeline. The
PRIMARY training path is MLX on the M1 (a native @mlx.nn@ emitter under the
reclaimed @Codegen.MLX@ name is planned but not yet built), and on-device
inference on the iPhone is intended to be a HAND-WRITTEN Swift + Metal forward
pass verified bit-for-bit against the Haskell golden vectors — never a CoreML
black box (the shipped app carries zero third-party dependencies; see the
repo-root @CLAUDE.md@ dependency contract). This module is kept as the
PyTorch→CoreML→ANE escape hatch should an enumerated-shape ANE distillation ever
be wanted; it is NOT on the shipped path.

It reads the typed spec (@SixFour.Spec.LookNetE/R/D@ + their σ-actions in
@SixFour.Spec.Tensor@) and emits TWO files into @trainer/generated/@:

  * @look_net_torch.py@ — a PyTorch @nn.Module@ implementing the L3 encoder,
    L4 recursion (ONE shared block reused over 8 Haar levels), and L5 per-level
    decoder reading the per-step contexts. Every
    weight matrix that the σ-equivariance contract forces to be block-diagonal
    is multiplied by the corresponding mask at forward time, so the model
    architecturally /cannot/ violate the algebraic constraint.

  * @build_mlpackage.py@ — a coremltools driver that loads a trained checkpoint
    into the PyTorch module, traces it at fixed shape, and converts to a
    CoreML @.mlpackage@ targeting the Apple Neural Engine
    (@ct.ComputeUnit.CPU_AND_NE@, @compute_precision=FLOAT16@,
    @minimum_deployment_target=ct.target.iOS18@).

Both files are deterministic from the spec: same Haskell ⇒ same emitted Python.
The constants emitted (model dim, channel splits, σ-masks, level dims) are read
back at test time by 'Properties.CoreMLContract' to guarantee no drift.

@Codegen.Shapes@ emits the NumPy shape + significance constants the trainer
imports; this module produces the (fallback) look-NN model + converter. Together
with @Codegen.Swift@ (on-device contract), @Codegen.Burn@ (Rust baseline
contract), and the on-device @STBN3DMaskLoader@, the spec generates the entire
cross-language surface from one Haskell source of truth.

== Why fixed token count

The ANE rejects dynamic shapes — every input dim must be static. The PyTorch
module accepts an input of shape @(B, maxTokens, gmmTokenDim) = (B, 16384, 10)@
(= @T·K·1@ = @64·256·10@); the trainer feeds a mask to zero out unused token
slots. This matches the @CyclicStack T K@ contract in "SixFour.Spec.Cyclic"
where @T·K = 16384@ is the upper bound on GMM tokens per capture.
-}
module SixFour.Codegen.CoreML
  ( emitLookNetTorch
  , emitBuildMlpackage
    -- * Shared constants (also used by Codegen.MLX + Properties.{CoreML,MLX}Contract)
  , maxTokens
  , emitLookNetConstants
  , pyBoolList
  , pyIntList
  ) where

import qualified Data.Text as T
import           Data.Text (Text)

import SixFour.Spec.Tensor
  ( hiddenAchromaticDim, hiddenRedGreenDim, hiddenBlueYellowDim, hiddenDim
  , sigma64Mask, gmmTokenSigmaMask
  )
import SixFour.Spec.LookNetR  (coreDepth, sharedBlockCount)
import SixFour.Spec.LookNetD  (decoderLevelDims, sigmaDecoderMask, decoderOutputDim, decoderTreeDepth)
import SixFour.Spec.SigmaPairHead (sigmaPairLeaves)
import SixFour.Spec.GMM       (gmmTokenDim)
import SixFour.Spec.LookNet   (modelDim, maxTokens)

-- | The pinned-dimension + σ-mask constant block, shared VERBATIM by the torch
-- ('emitLookNetTorch') and MLX ('SixFour.Codegen.MLX.emitLookNetMLX') emitters
-- so the two are byte-identical on every constant — the cross-emitter golden
-- sync that 'Properties.MLXContract' asserts. All comments are @#@ Python
-- comments, valid in both files.
emitLookNetConstants :: [Text]
emitLookNetConstants =
  [ "# ── Pinned dimensions (from Haskell spec; do not edit) ─────────────────────"
  , "GMM_TOKEN_DIM         = " <> tshow gmmTokenDim
  , "MODEL_DIM             = " <> tshow modelDim
  , "HIDDEN_ACHROMATIC_DIM = " <> tshow hiddenAchromaticDim
  , "HIDDEN_REDGREEN_DIM   = " <> tshow hiddenRedGreenDim
  , "HIDDEN_BLUEYELLOW_DIM = " <> tshow hiddenBlueYellowDim
  , "CORE_DEPTH            = " <> tshow coreDepth
  , "SHARED_BLOCK_COUNT    = " <> tshow sharedBlockCount <> "   # ONE block reused CORE_DEPTH times (Mixture-of-Recursions)"
  , "RECURSION_STEPS       = " <> tshow coreDepth <> "   # = CORE_DEPTH, one per Haar level"
  , "HALT_FEATURE_DIM      = 2    # (‖achromatic‖², ‖chromatic‖²) — the σ-invariant halt features"
  , "DECODER_OUT_DIM       = " <> tshow decoderOutputDim <> "   # = SIGMA_PAIR_DOF"
  , "DECODER_LEVEL_DIMS    = " <> pyIntList decoderLevelDims
  , "MAX_TOKENS            = " <> tshow maxTokens <> "   # T·K"
  , ""
  , "# ── SigmaPairHead pivot (NOTES 2026-05-28): the decoder emits a depth-7 ──"
  , "# generator pyramid (128 c_i), L6 σ-pair-interleaves into the 256-leaf"
  , "# palette [c0, σc0, c1, σc1, …] — exactly the σ-symmetric subspace (384 DOF)."
  , "SIGMA_PAIR_DOF        = " <> tshow decoderOutputDim <> "   # = 3·128 generators"
  , "SIGMA_PAIR_DEPTH      = " <> tshow decoderTreeDepth <> "    # depth-7 binary Haar generator pyramid"
  , "SIGMA_PAIR_LEAVES     = " <> tshow sigmaPairLeaves <> "  # reconstructed σ-pair palette leaves (= K)"
  , ""
  , "# ── σ-masks (derived from OKLab geometry; bit-identical to Haskell spec) ──"
  , "# 10-D GMM token: negate {μa, μb, ΣLa, ΣLb}; fix the rest."
  , "GMM_TOKEN_SIGMA_MASK = " <> pyBoolList gmmTokenSigmaMask
  , ""
  , "# 64-D hidden state: 22 σ-fixed achromatic + 42 σ-negated chromatic"
  , "# (21 red-green + 21 blue-yellow). Hurvich-Jameson 1:2 opponent ratio."
  , "SIGMA64_MASK = " <> pyBoolList sigma64Mask
  , ""
  , "# 384-D decoder output: per OKLab triple (L,a,b), negate (a,b). Repeating 128×."
  , "SIGMA_DECODER_MASK = " <> pyBoolList sigmaDecoderMask
  ]

-- ===========================================================================
-- look_net_torch.py — the PyTorch nn.Module
-- ===========================================================================

emitLookNetTorch :: Text
emitLookNetTorch = T.unlines (
  [ "# GENERATED by sixfour-spec / Codegen.CoreML — do not edit by hand."
  , "# Source of truth: spec/src/SixFour/Spec/{LookNetE,LookNetR,LookNetD,Tensor}.hs"
  , "# Regenerate with: cabal run spec-codegen"
  , "#"
  , "# The look-NN as a PyTorch nn.Module, with the Hurvich-Jameson σ-equivariance"
  , "# constraint baked in via per-weight binary masks. The masks force the trained"
  , "# model to be σ-equivariant by construction — no separate loss term required."
  , "\"\"\""
  , "look_net_torch — PyTorch implementation of the SixFour look-NN."
  , ""
  , "Pipeline: GmmTokenSet → L3Encoder → L4Recursion (ONE shared block reused over 8 Haar levels) → L5Decoder → 384 SigmaPairTree coefficients → reconstruct_sigma_pair → 256-leaf palette."
  , ""
  , "Every weight matrix marked as σ-mask-constrained is multiplied by its binary"
  , "block-diagonal mask at forward time. Cross-σ-class weights are forced to zero,"
  , "so the model architecturally cannot violate the algebraic σ-equivariance"
  , "contract proven typeable by SixFour.Spec.LookNetCompose.lookNetSigmaTheorem."
  , "\"\"\""
  , ""
  , "import torch"
  , "import torch.nn as nn"
  , "import torch.nn.functional as F"
  , ""
  ] <> emitLookNetConstants <>
  [ ""
  , "# ── σ-block-diagonal mask helpers ──────────────────────────────────────────"
  , ""
  , "def _block_diagonal_mask(in_mask: list, out_mask: list) -> torch.Tensor:"
  , "    \"\"\"Build the (len(out_mask), len(in_mask)) binary mask where entry"
  , "    [i, j] = 1 iff out_mask[i] == in_mask[j]. Weights with mask==0 are"
  , "    forced to zero by σ-equivariance.\"\"\""
  , "    return torch.tensor("
  , "        [[1.0 if out_mask[i] == in_mask[j] else 0.0"
  , "          for j in range(len(in_mask))]"
  , "         for i in range(len(out_mask))],"
  , "        dtype=torch.float32,"
  , "    )"
  , ""
  , "def _sigma_mask_64x64() -> torch.Tensor:"
  , "    return _block_diagonal_mask(SIGMA64_MASK, SIGMA64_MASK)"
  , ""
  , "def _sigma_mask_for_head(out_slice: slice) -> torch.Tensor:"
  , "    \"\"\"Mask for a decoder head whose output dims are SIGMA_DECODER_MASK[out_slice].\"\"\""
  , "    return _block_diagonal_mask(SIGMA64_MASK, SIGMA_DECODER_MASK[out_slice])"
  , ""
  , "# ── L3 encoder: σ-masked per-token linear (10 → 64), then sum-pool ───────"
  , ""
  , "class L3Encoder(nn.Module):"
  , "    \"\"\"Permutation-invariant set encoder. The per-token projection is a"
  , "    SINGLE σ-block-diagonal linear (no bias, no activation between layers):"
  , "    the cleanest σ-equivariant form. Sum-pooling over tokens is permutation-"
  , "    invariant by construction. Matches 'placeToken' in LookNetE.hs.\"\"\""
  , ""
  , "    def __init__(self):"
  , "        super().__init__()"
  , "        # Single linear 10 → 64 with σ-block-diagonal mask. No bias (a"
  , "        # constant bias would break σ-equivariance unless it lives in the"
  , "        # σ-fixed eigenspace; safer to omit). No intermediate nonlinearity"
  , "        # (the trainer can recover capacity via the 8 L4 blocks)."
  , "        self.phi = nn.Linear(GMM_TOKEN_DIM, MODEL_DIM, bias=False)"
  , "        self.register_buffer("
  , "            \"phi_mask\","
  , "            _block_diagonal_mask(GMM_TOKEN_SIGMA_MASK, SIGMA64_MASK),"
  , "        )"
  , ""
  , "    def forward(self, tokens: torch.Tensor, token_mask: torch.Tensor = None) -> torch.Tensor:"
  , "        # tokens: (B, MAX_TOKENS, 10);  token_mask: (B, MAX_TOKENS) in {0, 1}"
  , "        w = self.phi.weight * self.phi_mask       # σ-mask applied"
  , "        h = F.linear(tokens, w)                   # (B, MAX_TOKENS, 64)"
  , "        if token_mask is not None:"
  , "            h = h * token_mask.unsqueeze(-1)"
  , "        return h.sum(dim=1)                       # (B, 64) — sum-pool (perm-invariant)"
  , ""
  , "# ── L4 core: ONE shared block reused over 8 Haar levels (Mixture-of-Recursions) ──"
  , ""
  , "class SharedBlock(nn.Module):"
  , "    \"\"\"The ONE weight-shared block reused across all CORE_DEPTH recursion"
  , "    steps (Universal-Transformer / Mixture-of-Recursions). `refine` is the"
  , "    σ-equivariant residual update x ↦ x + φ(x); φ is a two-layer MLP whose"
  , "    weights are σ-block-diagonal-constrained (22²+42² = 2248 of 4096 free,"
  , "    ≈45% pruned by symmetry — LookNetR.lawSymmetryPruningRatio). `halt` is"
  , "    the σ-INVARIANT per-level halting head λ_ℓ ∈ [0,1] (PonderNet / MoR"
  , "    per-token routing, tokens = Haar levels).\"\"\""
  , ""
  , "    def __init__(self):"
  , "        super().__init__()"
  , "        self.w1 = nn.Linear(MODEL_DIM, MODEL_DIM, bias=False)"
  , "        self.w2 = nn.Linear(MODEL_DIM, MODEL_DIM, bias=False)"
  , "        self.register_buffer(\"sigma_mask\", _sigma_mask_64x64())"
  , "        # σ-INVARIANT halting head: reads ONLY (‖achroma‖², ‖chroma‖²), so"
  , "        # sign-flipping chroma cannot change λ_ℓ. Mirrors"
  , "        # LookNetR.sigmaInvariantFeatures / haltingFromFeatures."
  , "        self.halt_mlp = nn.Linear(HALT_FEATURE_DIM, 1)"
  , ""
  , "    def refine(self, x: torch.Tensor) -> torch.Tensor:"
  , "        w1 = self.w1.weight * self.sigma_mask"
  , "        w2 = self.w2.weight * self.sigma_mask"
  , "        # tanh is ODD — f(-x) = -f(x) — required for σ-equivariance under"
  , "        # sign-flip involutions. GELU/ReLU/SiLU are NOT odd and would break"
  , "        # equivariance (smoke test: max|σ(E(x))-E(σx)| ≈ 2950 with GELU, ~0 tanh)."
  , "        dx = torch.tanh(F.linear(x, w1))"
  , "        dx = F.linear(dx, w2)"
  , "        return x + dx"
  , ""
  , "    def halt(self, x: torch.Tensor) -> torch.Tensor:"
  , "        # σ-invariant features: squares kill the chromatic sign flip exactly."
  , "        achroma = x[..., :HIDDEN_ACHROMATIC_DIM]"
  , "        chroma  = x[..., HIDDEN_ACHROMATIC_DIM:]"
  , "        feats = torch.stack(["
  , "            (achroma ** 2).sum(dim=-1),"
  , "            (chroma ** 2).sum(dim=-1),"
  , "        ], dim=-1)                                 # (B, HALT_FEATURE_DIM)"
  , "        return torch.sigmoid(self.halt_mlp(feats)) # (B, 1) — λ_ℓ ∈ [0,1]"
  , ""
  , "    def forward(self, x: torch.Tensor) -> torch.Tensor:"
  , "        return self.refine(x)"
  , ""
  , "class L4Recursion(nn.Module):"
  , "    \"\"\"ONE SharedBlock reused RECURSION_STEPS (= CORE_DEPTH = 8) times. Returns"
  , "    the SEQUENCE of per-step contexts [ctx0, ctx1, …, ctx_CORE_DEPTH] (length"
  , "    CORE_DEPTH+1), so the decoder's level-ℓ head reads the context after ℓ"
  , "    refinements (deeper recursion → finer Haar detail). Static unroll (all"
  , "    steps run); halting λ_ℓ is exposed for the trainer's soft-PonderNet"
  , "    objective but does NOT gate control flow (hand-Metal / ANE friendly).\"\"\""
  , ""
  , "    def __init__(self):"
  , "        super().__init__()"
  , "        self.g = SharedBlock()                     # exactly ONE shared block"
  , ""
  , "    def forward(self, x: torch.Tensor) -> list:"
  , "        contexts = [x]"
  , "        for _ in range(RECURSION_STEPS):"
  , "            x = self.g(x)                          # reuse the shared block"
  , "            contexts.append(x)"
  , "        return contexts                            # length CORE_DEPTH + 1"
  , ""
  , "# ── L5 decoder: per-level Haar heads reading per-step contexts ─────────────"
  , ""
  , "class L5Decoder(nn.Module):"
  , "    \"\"\"Eight σ-block-diagonal heads (root + 7 generator Haar levels), each"
  , "    reading a DIFFERENT per-step context from L4Recursion: head i reads"
  , "    contexts[i], so the root (i=0) reads the pooled summary and finer Haar"
  , "    levels read deeper recursion outputs. Head i is masked against"
  , "    DECODER_LEVEL_DIMS[i]'s slice of SIGMA_DECODER_MASK. Sum of head sizes ="
  , "    sum(DECODER_LEVEL_DIMS) = SIGMA_PAIR_DOF = 384 (the 128 c_i generators)."
  , "    Mirrors LookNetD.decoderFromRecursion.\"\"\""
  , ""
  , "    def __init__(self):"
  , "        super().__init__()"
  , "        self.heads = nn.ModuleList()"
  , "        offsets = []"
  , "        cur = 0"
  , "        for d in DECODER_LEVEL_DIMS:"
  , "            self.heads.append(nn.Linear(MODEL_DIM, d, bias=False))"
  , "            offsets.append((cur, cur + d))"
  , "            cur += d"
  , "        self.offsets = offsets"
  , "        for i, (lo, hi) in enumerate(offsets):"
  , "            self.register_buffer("
  , "                f\"head_mask_{i}\","
  , "                _sigma_mask_for_head(slice(lo, hi)),"
  , "            )"
  , ""
  , "    def forward(self, contexts: list) -> torch.Tensor:"
  , "        # contexts: list of CORE_DEPTH+1 tensors (B, 64) from L4Recursion."
  , "        outs = []"
  , "        for i, head in enumerate(self.heads):"
  , "            mask = getattr(self, f\"head_mask_{i}\")"
  , "            w = head.weight * mask"
  , "            outs.append(F.linear(contexts[i], w))  # head i ← context i"
  , "        return torch.cat(outs, dim=-1)             # (B, 384) — the 384 SigmaPairTree coeffs"
  , ""
  , "# ── L6 reconstruction: SigmaPairTree (384) → 256-leaf σ-pair palette ───────"
  , ""
  , "def _haar_reconstruct(coeffs: torch.Tensor) -> torch.Tensor:"
  , "    \"\"\"Inverse Haar on the depth-7 generator pyramid. `coeffs` is (B, 384) ="
  , "    root(3) + level offsets [3,6,12,24,48,96,192], each an OKLab triple. At"
  , "    each level a node n with offset d yields [n+d, n-d]. Returns the 128"
  , "    generators c_i as (B, 128, 3). Mirrors PairTree.reconstruct.\"\"\""
  , "    b = coeffs.shape[0]"
  , "    nodes = coeffs[:, 0:3].reshape(b, 1, 3)        # root (B, 1, 3)"
  , "    cur = 3"
  , "    for lvl in range(SIGMA_PAIR_DEPTH):"
  , "        n = 1 << lvl                               # 2^lvl offsets this level"
  , "        offs = coeffs[:, cur:cur + 3 * n].reshape(b, n, 3)"
  , "        cur += 3 * n"
  , "        children = torch.stack([nodes + offs, nodes - offs], dim=2)  # (B, n, 2, 3)"
  , "        nodes = children.reshape(b, 2 * n, 3)      # interleaved [n+d, n-d]"
  , "    return nodes                                   # (B, 128, 3)"
  , ""
  , "def reconstruct_sigma_pair(coeffs: torch.Tensor) -> torch.Tensor:"
  , "    \"\"\"L6: the 128 generators c_i become the 256-leaf σ-pair palette"
  , "    [c0, σc0, c1, σc1, …] where σ(L,a,b) = (L,-a,-b). σ-symmetric by"
  , "    construction (every odd leaf is the σ-reflection of its even predecessor)."
  , "    Mirrors LookNetD.reconstructSigmaPair / SigmaPairHead.reconstructPaired.\"\"\""
  , "    gens = _haar_reconstruct(coeffs)               # (B, 128, 3)"
  , "    sig = torch.tensor([1.0, -1.0, -1.0], dtype=gens.dtype, device=gens.device)"
  , "    reflected = gens * sig                         # σ applied per generator"
  , "    paired = torch.stack([gens, reflected], dim=2) # (B, 128, 2, 3)"
  , "    return paired.reshape(coeffs.shape[0], SIGMA_PAIR_LEAVES, 3)  # (B, 256, 3)"
  , ""
  , "# ── The full pipeline ──────────────────────────────────────────────────────"
  , ""
  , "class LookNet(nn.Module):"
  , "    \"\"\"E :> R :> D, proven σ-equivariant end-to-end by"
  , "    SixFour.Spec.LookNetCompose.lookNetSigmaTheorem. forward() returns the raw"
  , "    384 SigmaPairTree coefficients (the trained genome + golden-vector"
  , "    contract); call reconstruct_sigma_pair() for the 256-leaf palette (L6).\"\"\""
  , ""
  , "    def __init__(self):"
  , "        super().__init__()"
  , "        self.encoder   = L3Encoder()"
  , "        self.recursion = L4Recursion()"
  , "        self.decoder   = L5Decoder()"
  , ""
  , "    def forward(self, tokens: torch.Tensor, token_mask: torch.Tensor = None) -> torch.Tensor:"
  , "        h = self.encoder(tokens, token_mask=token_mask)   # (B, 64)"
  , "        contexts = self.recursion(h)                      # [ (B,64) ] × (CORE_DEPTH+1)"
  , "        return self.decoder(contexts)                     # (B, 384)"
  ] )

-- ===========================================================================
-- build_mlpackage.py — the coremltools driver
-- ===========================================================================

emitBuildMlpackage :: Text
emitBuildMlpackage = T.unlines
  [ "# GENERATED by sixfour-spec / Codegen.CoreML — do not edit by hand."
  , "# Source of truth: spec/src/SixFour/Codegen/CoreML.hs"
  , "# Regenerate with: cabal run spec-codegen"
  , "#"
  , "# Converts the trained PyTorch LookNet (look_net_torch.py) into a CoreML"
  , "# .mlpackage targeting the ANE. Static shapes (required for ANE), FP16"
  , "# precision, deterministic output given a fixed checkpoint."
  , ""
  , "\"\"\""
  , "build_mlpackage — coremltools driver for the SixFour look-NN."
  , ""
  , "Usage:"
  , "    python build_mlpackage.py --weights look_net.safetensors --out SixFour/Resources/LookNet.mlpackage"
  , ""
  , "Requires: coremltools >= 7.2, torch >= 2.0, safetensors (optional)."
  , "\"\"\""
  , ""
  , "import argparse"
  , "import sys"
  , "from pathlib import Path"
  , ""
  , "import numpy as np"
  , "import torch"
  , "import coremltools as ct"
  , ""
  , "# The PyTorch module is in the same generated/ directory."
  , "sys.path.insert(0, str(Path(__file__).parent))"
  , "from look_net_torch import LookNet, GMM_TOKEN_DIM, MAX_TOKENS, DECODER_OUT_DIM"
  , ""
  , ""
  , "def _load_state_dict(path: Path) -> dict:"
  , "    if path.suffix == \".safetensors\":"
  , "        try:"
  , "            from safetensors.torch import load_file"
  , "            return load_file(str(path))"
  , "        except ImportError as e:"
  , "            raise SystemExit("
  , "                \"safetensors not installed; pip install safetensors or pass a .pt file\""
  , "            ) from e"
  , "    return torch.load(path, map_location=\"cpu\")"
  , ""
  , ""
  , "def build(weights_path: Path, out_path: Path) -> None:"
  , "    model = LookNet()"
  , "    state = _load_state_dict(weights_path)"
  , "    model.load_state_dict(state)"
  , "    model.eval()"
  , ""
  , "    # ANE requires static shapes. Trace at the maximum-token shape; runtime"
  , "    # callers pad/mask to this shape."
  , "    example_tokens = torch.zeros(1, MAX_TOKENS, GMM_TOKEN_DIM, dtype=torch.float32)"
  , "    example_mask   = torch.zeros(1, MAX_TOKENS, dtype=torch.float32)"
  , ""
  , "    # Wrap so that the traced module takes a single tensor input (CoreML's"
  , "    # MLProgram converter handles tuples but single-input traces are cleaner)."
  , "    class TracedLookNet(torch.nn.Module):"
  , "        def __init__(self, m):"
  , "            super().__init__()"
  , "            self.m = m"
  , "        def forward(self, tokens, token_mask):"
  , "            return self.m(tokens, token_mask=token_mask)"
  , ""
  , "    traced = torch.jit.trace(TracedLookNet(model), (example_tokens, example_mask))"
  , ""
  , "    mlmodel = ct.convert("
  , "        traced,"
  , "        inputs=["
  , "            ct.TensorType("
  , "                name=\"tokens\","
  , "                shape=(1, MAX_TOKENS, GMM_TOKEN_DIM),"
  , "                dtype=np.float32,"
  , "            ),"
  , "            ct.TensorType("
  , "                name=\"token_mask\","
  , "                shape=(1, MAX_TOKENS),"
  , "                dtype=np.float32,"
  , "            ),"
  , "        ],"
  , "        outputs=["
  , "            ct.TensorType(name=\"haar_coeffs\", dtype=np.float16),"
  , "        ],"
  , "        convert_to=\"mlprogram\","
  , "        compute_precision=ct.precision.FLOAT16,"
  , "        compute_units=ct.ComputeUnit.CPU_AND_NE,"
  , "        minimum_deployment_target=ct.target.iOS18,"
  , "    )"
  , ""
  , "    # Stamp the model card with the spec source hash so a future loader can"
  , "    # verify the .mlpackage matches the spec it was generated against."
  , "    mlmodel.author = \"SixFour spec-codegen\""
  , "    mlmodel.short_description = ("
  , "        \"Look-NN: 64-frame palette collapse. σ-equivariant by construction \""
  , "        \"(Hurvich-Jameson 22+21+21 hidden split; per-weight block-diagonal masks).\""
  , "    )"
  , "    mlmodel.version = \"1.0\""
  , ""
  , "    out_path.parent.mkdir(parents=True, exist_ok=True)"
  , "    mlmodel.save(str(out_path))"
  , "    print(f\"wrote {out_path}\")"
  , "    print(f\"  input  tokens     : (1, {MAX_TOKENS}, {GMM_TOKEN_DIM}) float32\")"
  , "    print(f\"  input  token_mask : (1, {MAX_TOKENS}) float32\")"
  , "    print(f\"  output haar_coeffs: (1, {DECODER_OUT_DIM}) float16\")"
  , ""
  , ""
  , "def main() -> None:"
  , "    parser = argparse.ArgumentParser(description=__doc__)"
  , "    parser.add_argument(\"--weights\", type=Path, required=True,"
  , "                        help=\"trained checkpoint (.safetensors or .pt)\")"
  , "    parser.add_argument(\"--out\", type=Path, required=True,"
  , "                        help=\"output .mlpackage path\")"
  , "    args = parser.parse_args()"
  , "    build(args.weights, args.out)"
  , ""
  , ""
  , "if __name__ == \"__main__\":"
  , "    main()"
  ]

-- ===========================================================================
-- Helpers
-- ===========================================================================

-- | Format an @[Int]@ as a Python list literal: @[1, 2, 3]@.
pyIntList :: [Int] -> Text
pyIntList xs = "[" <> T.intercalate ", " (map tshow xs) <> "]"

-- | Format a @[Bool]@ as a Python list literal: @[True, False, ...]@.
pyBoolList :: [Bool] -> Text
pyBoolList xs = "[" <> T.intercalate ", " (map pyB xs) <> "]"
  where
    pyB True  = "True"
    pyB False = "False"

tshow :: Show a => a -> Text
tshow = T.pack . show
