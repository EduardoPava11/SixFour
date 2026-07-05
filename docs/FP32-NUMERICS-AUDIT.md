# FP32 numerics audit — is the fused gradient cross-device reproducible?

> Status: AUDIT · Created: 2026-07-05 · Owner: SixFour
> The research (`docs/PER-CAPTURE-LEARNING-RESEARCH.md` §2 Task 1, §3 numerics) named
> the cross-generation determinism risk: if `FP32-accumulate → pinned-round → Q16` is
> not byte-identical across A-series and M-series, the "same burst → same GIF" promise
> voids every downstream determinism claim. This audits `deviceTrainSimtKernel`
> (`SixFour/Metal/DeviceTrainShaders.metal`) against that requirement.

## Verdict

**The kernel already implements the report's recommendation; it is cross-device-ready
BY CONSTRUCTION on every axis the source controls.** The one residual is a hardware
IEEE-conformance question that only a physical A-series run can settle — which is
exactly the narrow question the M-spec / A-proto split was designed to leave open.

## What the source guarantees (each pinned by a test)

| Requirement (report) | Kernel reality | Pinned by |
|---|---|---|
| No `half`/`bf16` (emulated with non-standard rounding on older iPhones) | **float-only** — no `half`/`bfloat`/`packed_half` token anywhere in the train kernels | source scan; `Fp32NumericsAuditTests` |
| FP32 master copy — never accumulate in the Q16 lattice | `threadgroup float th[kParamsD]` holds θ in FP32 for the WHOLE descent; the lattice is touched only at the final commit | `DeviceTrainGolden` (bytes) |
| Round only at the end, pinned rounding | `committedOut[j] = int(rint(raw * kQ16))` — `rint` = round-half-to-even = `ByteCarrier.reenterQ16` | `Fp32NumericsAuditTests` (round-half-to-even) |
| Deterministic reduction order | fixed binary-tree reduce over a FIXED thread count (`kSimtThreads = 256`); same input bits → same output bits | `RungDispatchTests.simtIsBitwiseReproducibleOnALargeBatch` |
| CPU ↔ GPU agreement | the fp32 SIMT kernel is byte-equal to the float64 CPU twin on a large batch | `RungDispatchTests.simtLargeBatchMatchesTheCPUDoubleTwin` |
| W₀ meta-init does not perturb the floor | `thetaInit` defaults to an all-zero buffer ⇒ byte-identical to the old `th = 0` | `MetaInitKernelWiringTests.defaultInitIsByteIdenticalToTheZeroFloor` |

## The one open item (needs a device, not more M-series code)

Basic float32 `mul`/`add`/`rint` on Metal *should* be IEEE-754 identical across A- and
M-series, but two things are not guaranteed by the source alone:

1. **FMA contraction** — a compiler may contract `a*b + c` into a fused multiply-add on
   one GPU family and not another, changing the last bit. (The kernel's inner products
   are the exposure.)
2. **`rint` at the exact half-ULP boundary** — round-half-to-even is specified, but the
   hardware path is what the A-series run confirms.

**How to close it (no new code):** run `AmortizedFitProbeTests` /
`fusedDispatchIsBitReproducibleAcrossRuns` on a physical iPhone and diff the printed
fingerprint against the M-series (simulator/host GPU) one:

```
M-series (host GPU): committed=[0, -5076, 3384, -1128, -4512, -1128, 1410]  loss(bits)=991480425
```

If the A-series line matches byte-for-byte, cross-generation determinism holds and the
per-capture gene is safe to ship. If it doesn't, the fix is to forbid FMA contraction on
the inner products (`fma`-free / `-fp-contract=off` equivalent, or explicit rounding
between the multiply and the add) — a targeted kernel change, not a redesign.
