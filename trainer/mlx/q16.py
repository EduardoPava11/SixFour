"""Q16 fixed-point crossing, the byte-exact twin of spec/SixFour/Spec/Q16.hs + ByteCarrier.hs.

This is the SINGLE float to device-byte crossing. Everything the trainer commits
passes through `quantize_q16`, which must reproduce the Haskell `quantizeQ16`
byte-for-byte:

    quantizeQ16 x = round (x * 65536)     -- round-half-to-even (Haskell `round`)
    toQ16       q = fromIntegral q / 65536

Python's builtin `round` is round-half-to-even, so it matches Haskell `round`
exactly on the IEEE-754 double grid. The arithmetic is done in float64 (Python
float == C double == Haskell Double); never float32, or the rounded byte drifts.

Realizes (EncoderFrozen.hs / ByteCarrier.hs):
  * lawEmbeddingNeverBypassesQ16   - the only path float -> byte is this requantise
  * lawRawEmbeddingCommitIsUnsafe  - sub-quantum floats collapse to one byte
"""
from __future__ import annotations

Q16_ONE = 65536  # the 16.16 fixed-point scale


def to_q16(q: int) -> float:
    """Integer Q16 grid point viewed as a Double. Inverse of `quantize_q16` on the grid."""
    return q / Q16_ONE


def quantize_q16(x: float) -> int:
    """Round a Mac-side float onto the Q16 grid: round(x * 65536), half-to-even.

    The one sanctioned float->device crossing (ByteCarrier.reenterQ16 . mkLatent,
    then toByte). `round` here is Python's banker's rounding == Haskell `round`.
    """
    return round(float(x) * Q16_ONE)


# `reenterQ16 . mkLatent` then `toByte` collapses to exactly `quantize_q16` (ByteCarrier.hs:110).
reenter_q16 = quantize_q16


if __name__ == "__main__":
    fails = 0

    # lawReentryIsFloor / lawTerminalQuantizationIdempotent: the grid is a fixpoint.
    if quantize_q16(to_q16(3000)) != 3000:
        print("FAIL: quantize_q16(to_q16(3000)) != 3000"); fails += 1
    for q in (0, 1, 3000, 32768, 65535, 98304, 131072):
        if quantize_q16(to_q16(q)) != q:
            print(f"FAIL: grid point {q} not a re-entry fixpoint"); fails += 1

    # lawEmbeddingNeverBypassesQ16: raw 1.5 -> exact grid point 1.5 * 65536 = 98304.
    if quantize_q16(1.5) != 98304:
        print("FAIL: quantize_q16(1.5) != 98304"); fails += 1

    # lawRawEmbeddingCommitIsUnsafe: sub-quantum apart -> SAME byte; whole-unit -> DIFFERENT.
    if quantize_q16(1.0) != quantize_q16(1.0000001):
        print("FAIL: sub-quantum floats did not collapse to one byte"); fails += 1
    if quantize_q16(1.0) == quantize_q16(2.0):
        print("FAIL: whole-unit-apart floats collapsed to one byte"); fails += 1

    print("q16: PASS" if fails == 0 else f"q16: {fails} FAIL")
    raise SystemExit(1 if fails else 0)
