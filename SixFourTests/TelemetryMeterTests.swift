import Testing
@testable import SixFour

/// The liveScene instrument flanks' pure display math (`TelemetryMeterMath`):
/// the √N fill quantizer against the spec's 1:8:64 derived sample-volume lattice,
/// the three-state independence-health mapping (derived is EXPECTED-maximal, never
/// a false alarm), the one-vocabulary exposure labels, and the machine ring's
/// budget/thermal quantizers.
struct TelemetryMeterTests {

    // MARK: - √N significance fill (quantized to cell steps)

    @Test func sqrtFillEndpointsAndClamps() {
        #expect(TelemetryMeterMath.sqrtFillCells(volume: 0, reference: 64, width: 28) == 0)
        #expect(TelemetryMeterMath.sqrtFillCells(volume: -5, reference: 64, width: 28) == 0)
        #expect(TelemetryMeterMath.sqrtFillCells(volume: 64, reference: 64, width: 28) == 28)
        #expect(TelemetryMeterMath.sqrtFillCells(volume: 999, reference: 64, width: 28) == 28)
        #expect(TelemetryMeterMath.sqrtFillCells(volume: 5, reference: 0, width: 28) == 0)
        #expect(TelemetryMeterMath.sqrtFillCells(volume: 5, reference: 8, width: 0) == 0)
    }

    /// The derived 1:8:64 lattice (`lawDerivedSignificanceLattice`) reads on the
    /// bar as the √ ladder 1 : 2√2 : 8 — fills 4 / 10 / 28 of 28 cells against
    /// the coarsest (most significant) rung.
    @Test func sqrtFillReadsTheDerivedLattice() {
        #expect(TelemetryMeterMath.sqrtFillCells(volume: 1, reference: 64, width: 28) == 4)
        #expect(TelemetryMeterMath.sqrtFillCells(volume: 8, reference: 64, width: 28) == 10)
        #expect(TelemetryMeterMath.sqrtFillCells(volume: 64, reference: 64, width: 28) == 28)
    }

    /// The √N order IS the N order (`lawSignificanceSqrtMonotone`): the fill is
    /// monotone in the evidence.
    @Test func sqrtFillMonotone() {
        var last = 0
        for v in 0...64 {
            let f = TelemetryMeterMath.sqrtFillCells(volume: Int64(v), reference: 64, width: 28)
            #expect(f >= last)
            last = f
        }
        #expect(last == 28)
    }

    // MARK: - Arrival pulse beat (movement, never parity)

    /// THE REGRESSION: derived snapshots publish at the 16-rung cadence with
    /// `arrivals = ticks >> k`, so rung64 lands 4, 8, …, 64 and rung32 lands
    /// 2, 4, …, 32 — always even. Raw parity froze those pulses for the whole
    /// burst; the beat must flip on EVERY delivered movement instead.
    @Test func pulseBeatsOnEvenStrideCounters() {
        for k in 0...1 {   // the two flanks parity froze (rung64, rung32)
            var beat = false
            var last: Int? = nil
            var flips = 0
            for tick in 1...64 where tick % 4 == 0 {
                let arrivals = tick >> k
                let next = TelemetryMeterMath.pulseBeat(arrivals: arrivals, last: last, beat: beat)
                if next != beat { flips += 1 }
                beat = next
                last = arrivals
            }
            #expect(flips == 16)   // all 16 snapshots pulse
        }
    }

    /// A stalled rung keeps receiving snapshots (the other rungs drive the
    /// cadence) with an unchanged counter — the pulse must freeze: that IS the
    /// honest gap read.
    @Test func pulseStallsWithoutArrivals() {
        var beat = TelemetryMeterMath.pulseBeat(arrivals: 7, last: nil, beat: false)
        #expect(beat)   // arrivals already landed at first snapshot = first beat
        for _ in 0..<5 {
            let next = TelemetryMeterMath.pulseBeat(arrivals: 7, last: 7, beat: beat)
            #expect(next == beat)
            beat = next
        }
    }

    @Test func pulseBeatEdges() {
        // First snapshot with no arrivals yet stays off.
        #expect(!TelemetryMeterMath.pulseBeat(arrivals: 0, last: nil, beat: false))
        // A new burst's counter RESET (64 → 4) is movement — the pulse flips.
        #expect(!TelemetryMeterMath.pulseBeat(arrivals: 4, last: 64, beat: true))
        #expect(TelemetryMeterMath.pulseBeat(arrivals: 4, last: 64, beat: false))
        // Odd-stride counters (rung16: 1, 2, 3, …) flip every snapshot too.
        #expect(TelemetryMeterMath.pulseBeat(arrivals: 2, last: 1, beat: false))
    }

    // MARK: - Independence health (the three-state cell)

    @Test func healthStates() {
        // Independent + decorrelated = the seal.
        #expect(TelemetryMeterMath.health(independent: true, comovementPermille: 500)
                == .independent)
        // -1 = no coarser rung / no data yet — not a warning.
        #expect(TelemetryMeterMath.health(independent: true, comovementPermille: -1)
                == .independent)
        // Independent by schedule but fully determined (1000‰) = the warning light
        // (the ladder fell back to indistinguishable-from-pooling).
        #expect(TelemetryMeterMath.health(independent: true, comovementPermille: 1000)
                == .correlated)
        // Derived pooling is the EXPECTED maximal pole — the derived glyph, never
        // a false alarm, regardless of the statistic.
        #expect(TelemetryMeterMath.health(independent: false, comovementPermille: 1000)
                == .derived)
        #expect(TelemetryMeterMath.health(independent: false, comovementPermille: -1)
                == .derived)
    }

    /// The shipped derived-mode snapshot maps to derived glyphs on every rung and
    /// the exact 4/10/28 √-ladder fills — the honest fallback, not an error state.
    @Test func derivedSnapshotReadsAsDerivedNotAlarm() {
        let tel = RungTelemetry.derived(ticks: 64, fineBinArea: 100, generation: 1)
        #expect(tel.rungs.count == 3)
        for r in tel.rungs {
            #expect(TelemetryMeterMath.health(
                independent: r.independent,
                comovementPermille: r.comovementPermilleVsCoarser) == .derived)
        }
        let ref = tel.rungs.map(\.sampleVolume).max() ?? 1
        let fills = tel.rungs.map {
            TelemetryMeterMath.sqrtFillCells(volume: $0.sampleVolume, reference: ref, width: 28)
        }
        #expect(fills == [4, 10, 28])
    }

    // MARK: - Exposure labels (one vocabulary, both modes)

    @Test func exposureLabels() {
        #expect(TelemetryMeterMath.evLabel(centistops: 100) == "+1.0")
        #expect(TelemetryMeterMath.evLabel(centistops: -50) == "-0.5")
        #expect(TelemetryMeterMath.evLabel(centistops: 0) == "+0.0")
        #expect(TelemetryMeterMath.evLabel(centistops: 250) == "+2.5")

        // Independent: optical shutter + gain. 50 000 µs = the pinned 1/20 s cap.
        #expect(TelemetryMeterMath.durationLabel(independent: true, durationUs: 50_000) == "1/20")
        #expect(TelemetryMeterMath.durationLabel(independent: true, durationUs: 0) == "-")
        #expect(TelemetryMeterMath.isoLabel(independent: true, isoMilli: 800_000) == "800")
        #expect(TelemetryMeterMath.isoLabel(independent: true, isoMilli: 0) == "-")

        // Derived: no per-rung shutter exists — the honest pooling vocabulary.
        #expect(TelemetryMeterMath.durationLabel(independent: false, durationUs: 0) == "POOL")
        #expect(TelemetryMeterMath.isoLabel(independent: false, isoMilli: 0) == "")
    }

    // MARK: - The machine ring quantizers

    @Test func budgetFill() {
        #expect(TelemetryMeterMath.budgetFillCells(us: 0, budgetUs: 50_000, width: 64) == 0)
        #expect(TelemetryMeterMath.budgetFillCells(us: 25_000, budgetUs: 50_000, width: 64) == 32)
        #expect(TelemetryMeterMath.budgetFillCells(us: 50_000, budgetUs: 50_000, width: 64) == 64)
        #expect(TelemetryMeterMath.budgetFillCells(us: 99_000, budgetUs: 50_000, width: 64) == 64)
        #expect(TelemetryMeterMath.budgetFillCells(us: 10, budgetUs: 0, width: 64) == 0)
        #expect(TelemetryMeterMath.budgetFillCells(us: -1, budgetUs: 50_000, width: 64) == 0)
    }

    @Test func thermalSteps() {
        #expect(TelemetryMeterMath.thermalLit(level: -1) == 0)   // never observed
        #expect((0...4).map { TelemetryMeterMath.thermalLit(level: $0) } == [1, 2, 3, 4, 5])
        #expect(TelemetryMeterMath.thermalLit(level: 9) == 5)    // clamped
    }
}
