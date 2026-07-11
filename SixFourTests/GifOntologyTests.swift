import Foundation
import Testing
@testable import SixFour

/// THE ONTOLOGY'S LAWS (docs/REBUILD-2026-07-10-PLAN.md §2b): the four core
/// types are only worth promoting if the GIF concepts they abstract hold as
/// checkable laws — delay is a theorem of the rung, the sRGB8 palette wire
/// round-trips, and a Loop survives its own GIF89a serialization exactly
/// (self-contained stop motion, literally).
struct GifOntologyTests {

    private func randomCanonicalPalette(k: Int, seed: inout UInt64) -> Palette? {
        var rgb = [UInt8](repeating: 0, count: k * 3)
        for i in rgb.indices {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            rgb[i] = UInt8(truncatingIfNeeded: seed >> 33)
        }
        return Palette(srgb8: rgb)
    }

    private func randomLoop(frames: Int, rung: WeaveRung, k: Int, seed: inout UInt64) -> Loop? {
        var cels = [Cel]()
        var palettes = [Palette]()
        for _ in 0..<frames {
            var indices = [UInt8](repeating: 0, count: rung.side * rung.side)
            for i in indices.indices {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                indices[i] = UInt8(truncatingIfNeeded: (seed >> 33) % UInt64(k))
            }
            guard let plane = IndexPlane(side: rung.side, indices: indices),
                  let cel = Cel(plane: plane, rung: rung),
                  let palette = randomCanonicalPalette(k: k, seed: &seed)
            else { return nil }
            cels.append(cel)
            palettes.append(palette)
        }
        return Loop(cels: cels, palettes: palettes)
    }

    @Test func delayIsATheoremOfTheRung() {
        // The GIF89a time law, per rung — the values are the kernel's, not ours.
        #expect(WeaveRung.w64.delayCs == 20 / 4)   // 64 @ 20 fps → 5 cs
        #expect(WeaveRung.w32.delayCs == 10)       // 32 @ 10 fps
        #expect(WeaveRung.w16.delayCs == 20)       // 16 @ 5 fps
        for rung in WeaveRung.allCases {
            #expect(Int32(rung.delayCs) == s4_ladder_delay_cs(Int32(rung.side)))
        }
        // A replicated raster (64-rung content exported at 256²) keeps the
        // SOURCE rung's time: replication adds pixels, never time.
        let plane = IndexPlane(side: 256, indices: [UInt8](repeating: 0, count: 256 * 256))!
        let cel = Cel(plane: plane, rung: .w64)
        #expect(cel?.delayCs == 5)
        // A raster that is not an integer replication of the rung is refused.
        let odd = IndexPlane(side: 48, indices: [UInt8](repeating: 0, count: 48 * 48))!
        #expect(Cel(plane: odd, rung: .w64) == nil)
    }

    @Test func paletteSRGB8WireRoundTrips() {
        var seed: UInt64 = 0xC0FF_EE00_0C7A_1001
        for k in [4, 16, 256] {
            guard let palette = randomCanonicalPalette(k: k, seed: &seed) else {
                Issue.record("canonical palette construction failed k=\(k)"); return
            }
            // CANONICAL FORM: arbitrary bytes stabilize on entry (the
            // inverse/realize pair is idempotent, not id, on raw bytes), and
            // once canonical the wire is a true fixed point — rebuilding from
            // the view is value-exact and byte-exact, forever.
            guard let rgb = palette.srgb8(), let rebuilt = Palette(srgb8: rgb) else {
                Issue.record("view failed k=\(k)"); return
            }
            #expect(rebuilt == palette)
            #expect(rebuilt.srgb8() == rgb)
        }
    }

    @Test func loopSurvivesItsOwnGifSerialization() {
        // Self-contained stop motion, literally: encode to GIF89a bytes,
        // decode, and get the SAME VALUE back — plus byte-identical
        // re-encode (the codec is deterministic on its range).
        var seed: UInt64 = 0xC0FF_EE00_0C7A_2002
        for (rung, k) in [(WeaveRung.w16, 4), (.w16, 256), (.w32, 16)] {
            guard let loop = randomLoop(frames: 4, rung: rung, k: k, seed: &seed) else {
                Issue.record("loop construction failed \(rung) k=\(k)"); return
            }
            guard let bytes = loop.gifBytes() else {
                Issue.record("encode failed \(rung) k=\(k)"); return
            }
            guard let decoded = Loop(gifBytes: bytes) else {
                Issue.record("decode failed \(rung) k=\(k)"); return
            }
            // Component-wise so a failure names its layer.
            #expect(decoded.cels == loop.cels, "index planes/rungs differ for \(rung) k=\(k)")
            for t in 0..<loop.frameCount where decoded.palettes[t] != loop.palettes[t] {
                let wireEqual = decoded.palettes[t].srgb8() == loop.palettes[t].srgb8()
                Issue.record("palette \(t) differs (\(rung) k=\(k)); sRGB8 wire equal=\(wireEqual) — \(wireEqual ? "Q16 inverse not injective on wire" : "codec changed bytes")")
            }
            #expect(decoded == loop, "decode(encode(loop)) != loop for \(rung) k=\(k)")
            #expect(decoded.gifBytes() == bytes, "re-encode not byte-identical")
        }
    }

    @Test func renderIsPaletteIndex() {
        // The ontology IS the render: frame pixels are exactly palette[index].
        var seed: UInt64 = 0xC0FF_EE00_0C7A_3003
        guard let loop = randomLoop(frames: 2, rung: .w16, k: 4, seed: &seed),
              let rendered = loop.renderFrameQ16(1) else {
            Issue.record("render failed"); return
        }
        let leaves = loop.palettes[1].leavesQ16
        let expected = loop.cels[1].plane.indices.map { leaves[Int($0)] }
        #expect(rendered == expected)
        #expect(loop.renderFrameQ16(2) == nil)   // out of range refuses
    }

    @Test func ingestInvertsTheWire() {
        // SELF-CONTAINMENT, both directions: export a canonical loop to the
        // 256-side wire, ingest the bytes, and recover the SAME VALUE — the
        // capture-format contract (replicate ∘ decimate == id) at Loop level.
        var seed: UInt64 = 0xC0FF_EE00_0C7A_6006
        guard let loop = randomLoop(frames: 3, rung: .w64, k: 16, seed: &seed),
              let wire = loop.replicated(by: SixFourCaptureFormat.upscaleFactor),
              let bytes = wire.gifBytes() else {
            Issue.record("wire construction failed"); return
        }
        #expect(Loop.ingest(wireGif: bytes) == loop)
        // A native ladder-side GIF passes through ingest unchanged.
        guard let nativeBytes = loop.gifBytes() else { Issue.record("encode failed"); return }
        #expect(Loop.ingest(wireGif: nativeBytes) == loop)
        // decimated is the exact left inverse of replicated.
        #expect(wire.decimated(by: SixFourCaptureFormat.upscaleFactor) == loop)
    }

    @Test func nonUniformLoopRefusesEncode() {
        // GIF89a needs one side / one K / one rung; the Loop refuses to
        // coerce a mixed value silently.
        var seed: UInt64 = 0xC0FF_EE00_0C7A_4004
        guard var loop = randomLoop(frames: 2, rung: .w16, k: 4, seed: &seed),
              let mixed = randomLoop(frames: 1, rung: .w32, k: 4, seed: &seed) else {
            Issue.record("construction failed"); return
        }
        loop.cels.append(mixed.cels[0])
        loop.palettes.append(mixed.palettes[0])
        #expect(loop.gifBytes() == nil)
    }
}
