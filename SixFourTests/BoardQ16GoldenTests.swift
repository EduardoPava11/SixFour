import Testing
import simd
@testable import SixFour

/// Gate for the owned deterministic board-mass kernels (`s4_board_mass_q16` /
/// `s4_board_counts_to_mass_q16` via `SixFourNative`) — the Swift end of the
/// port of `SixFour.Spec.BoardQ16`. Spec≡Zig is pinned by the Zig unit test in
/// `kernels.zig`; THIS pins the Swift FFI surface against the SAME
/// Haskell-confirmed golden, plus the permutation-invariance the old float
/// histogram lacked (debt `board-q16-unported`).
struct BoardQ16GoldenTests {

    /// Haskell-confirmed golden input (`Spec.BoardQ16.boardMassQ16`):
    /// bins 136/569/3839/3976 → mass 10923 (count 1); bin 2288 → 21845 (count 2).
    private let colors: [SIMD3<Int32>] = [
        SIMD3<Int32>(0, 0, 0),
        SIMD3<Int32>(65535, 0, 0),
        SIMD3<Int32>(32768, 32768, -32768),
        SIMD3<Int32>(32768, 32768, -32768),
        SIMD3<Int32>(10000, -20000, 5000),
        SIMD3<Int32>(60000, 30000, 30000),
    ]
    private let occupied: Set<Int> = [136, 569, 2288, 3839, 3976]

    /// Swift (via Zig) reproduces the exact Haskell golden mass channel.
    @Test func massMatchesHaskellGolden() {
        guard let m = SixFourNative.boardMassQ16(colorsQ16: colors) else {
            Issue.record("s4_board_mass_q16 returned nil"); return
        }
        #expect(m.count == 4096)
        #expect(m[136] == 10923)
        #expect(m[569] == 10923)
        #expect(m[2288] == 21845)
        #expect(m[3839] == 10923)
        #expect(m[3976] == 10923)
        // lawMassQ16Bounded: |Σ − 2¹⁶| ≤ boardBins
        let sum = m.reduce(0) { $0 + Int($1) }
        #expect(abs(sum - 65536) <= 4096)
        // every non-occupied bin is exactly zero
        for i in 0 ..< 4096 where !occupied.contains(i) { #expect(m[i] == 0) }
    }

    /// The determinism the float histogram failed: reversing the input cannot
    /// change a single bin (`lawCountsOrderIndependent`).
    @Test func massIsOrderIndependent() {
        guard let a = SixFourNative.boardMassQ16(colorsQ16: colors),
              let b = SixFourNative.boardMassQ16(colorsQ16: colors.reversed()) else {
            Issue.record("s4_board_mass_q16 returned nil"); return
        }
        #expect(a == b)
    }

    /// The counts→mass kernel agrees on a hand-built count vector
    /// (`Spec.BoardQ16.massQ16`, the pixel-channel path).
    @Test func countsToMassMatchesGolden() {
        var counts = [Int32](repeating: 0, count: 4096)
        counts[2288] = 2
        counts[136] = 1
        guard let m = SixFourNative.boardMassQ16(counts: counts, total: 3) else {
            Issue.record("s4_board_counts_to_mass_q16 returned nil"); return
        }
        #expect(m[2288] == 43691) // (2·65536 + 1) / 3
        #expect(m[136] == 21845)  // (1·65536 + 1) / 3
    }
}
