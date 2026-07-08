//  KernelsGif.swift
//  Swift port of the GIF/quantize section of Native/src/kernels.zig (2026-07-06);
//  byte-exact twin; the encoder is additionally gated by DeterministicRenderer
//  SHA-256 reproducibility.
//
//  This file carries the GIF89a codec half of the slice:
//    s4_gif_encode_burst_bound, s4_burst_scratch_bytes, s4_gif_encode_burst,
//    s4_gif_assemble, s4_gif_decode_scratch_bytes, s4_gif_decode
//  (the quantize/dither/collapse pipeline half lives in KernelsQuantize.swift).
//  Shared surface (s4log, S4_* constants) comes from KernelsCore.swift; the
//  colour kernels the burst driver composes (s4_widen_half_to_q16,
//  s4_linear_to_oklab_q16, s4_palette_oklab_to_srgb8) are cross-slice s4_*
//  exports elsewhere in this module.
//
//  A single byte of drift in LZW packing, sub-block framing, or palette
//  ordering is a total failure: the code-size ladder (`next_code > 1 <<
//  code_size`), the dictionary reset (clear code emitted at the PRE-reset
//  size), and the LSB-first bit packing are translated verbatim.

// ── return codes (private copies of kernels.zig RC_*, per the port convention) ─
private let rcOK: Int32 = 0
private let rcNullPtr: Int32 = 1
private let rcBadShape: Int32 = 2
private let rcScratchTooSmall: Int32 = 3
private let rcOutputTooSmall: Int32 = 4
private let rcInfeasibleSignificance: Int32 = 5
private let rcBadDitherMode: Int32 = 6
private let rcOutOfRange: Int32 = 7
private let rcNotImplemented: Int32 = 100

// ── pure size helpers (stabilise the ABI for the callers) ─────────────────────

/// Upper bound on the GIF89a byte length for a burst of `frame_count` frames,
/// each `side`×`side`, with `k`-entry local colour tables. Generous so the Swift
/// caller can size `out_gif` once. Returns 0 on a nonsensical shape.
@_cdecl("s4_gif_encode_burst_bound")
public func s4_gif_encode_burst_bound(_ frame_count: Int32, _ side: Int32, _ k: Int32) -> Int {
    if frame_count <= 0 || side <= 0 || k <= 0 { return 0 }
    let fc = Int(frame_count)
    let p = Int(side) * Int(side)
    let kk = Int(k)

    // Header + logical screen descriptor + Netscape loop extension.
    let fileOverhead = 6 + 7 + 19
    // Generous slack for an optional comment-extension metadata block + trailer.
    let commentSlack = 8192

    // Per frame: graphics-control (8) + image descriptor (10) + local colour
    // table (3·k) + worst-case LZW (no compression: ~12-bit codes ⇒ <2·P bytes,
    // plus a 1-byte length per 255-byte sub-block, plus framing) + minCodeSize.
    let perFrame = 8 + 10 + 3 * kk + (2 * p + p / 255 + 64)

    return fileOverhead + commentSlack + fc * perFrame + 1
}

/// Working-memory bytes the burst pipeline needs in `scratch`. Two terms scale
/// with `frame_count`: the cross-frame accumulation buffers (`all_indices` +
/// `all_palettes`) that the single `s4_gif_assemble` call consumes at the end.
/// Everything else is one frame's working set (reused each iteration) plus the
/// quantiser's and dither's per-kernel scratch. This is sized EXACTLY for the
/// `s4_gif_encode_burst` carving below — keep the two in lockstep.
@_cdecl("s4_burst_scratch_bytes")
public func s4_burst_scratch_bytes(_ frame_count: Int32, _ side: Int32, _ k: Int32) -> Int {
    if frame_count <= 0 || side <= 0 || k <= 0 { return 0 }
    let fc = Int(frame_count)
    let p = Int(side) * Int(side)
    let kk = Int(k)

    // Persistent across the frame loop (the assembler reads ALL frames at once).
    let allIndices = fc * p // u8 index per pixel, every frame
    let allPalettes = fc * 3 * kk // sRGB8 local colour table, every frame
    // Per-frame working set (overwritten each iteration).
    let linQ16 = p * 3 * MemoryLayout<Int32>.stride // widened linear Q16
    let oklabQ16 = p * 3 * MemoryLayout<Int32>.stride // linear→OKLab Q16
    let centroids = kk * 3 * MemoryLayout<Int32>.stride
    let idxTmp = p // quantiser's throwaway nearest assignment
    let qScratch = p * MemoryLayout<Int64>.stride + 3 * kk * MemoryLayout<Int64>.stride + kk * MemoryLayout<Int32>.stride
    let dScratch = p * 3 * MemoryLayout<Int32>.stride // error-diffusion residual buffer
    // Base 16-alignment + per-region alignForward padding (8 regions).
    let alignSlack = 12 * 16

    return allIndices + allPalettes + linQ16 + oklabQ16 + centroids +
        idxTmp + qScratch + dScratch + alignSlack
}

// NOTE (ported private helper): kernels.zig `Carver`.
// A bump-carver over the caller's `scratch` buffer: hands out per-region typed
// sub-buffers, each aligned for its element type. `base` is force-aligned to 16
// at construction so every Int64/Int32 region is safely aligned regardless of
// how the caller allocated. On overflow it flips `ok` (the caller checks once).
private struct Carver {
    var base: UnsafeMutableRawPointer
    var cap: Int
    var off: Int = 0
    var ok: Bool = true

    init(_ raw: UnsafeMutableRawPointer, _ cap: Int) {
        let addr = UInt(bitPattern: raw)
        let aligned = (addr &+ 15) & ~UInt(15)
        let skip = Int(aligned &- addr)
        self.base = raw + skip
        self.cap = cap > skip ? cap - skip : 0
    }

    mutating func take<T>(_ type: T.Type, _ count: Int) -> UnsafeMutablePointer<T> {
        let align = MemoryLayout<T>.alignment
        off = (off + align - 1) & ~(align - 1)
        let bytes = count * MemoryLayout<T>.stride
        if off + bytes > cap {
            ok = false
            return base.bindMemory(to: T.self, capacity: 1) // dummy; base is 16-aligned, never validly used
        }
        let ptr = (base + off).bindMemory(to: T.self, capacity: count)
        off += bytes
        return ptr
    }
}

/// Whole-burst entrypoint — the deterministic `state = fold(apply, …)` core as a
/// SINGLE C-ABI call: linear-sRGB Float16 halfs → byte-exact GIF89a. It composes
/// the already-golden-gated sub-kernels, per frame:
///
///   widen(half→Q16) → linear→OKLab → quantise(maximin+Lloyd) → dither → palette,
///
/// accumulating per-frame indices + local colour tables, then one `s4_gif_assemble`.
/// Significance is intentionally NOT run here (the signature carries no
/// `min_population`): this is the pure core fold; the per-frame significance rescue
/// is a caller-side concern (see `DeterministicRenderer`). Output is a pure function
/// of the input halfs + parameters, identical on every device — so any consumer can
/// RECOMPUTE and verify it (the "apply" primitive a gene exchange needs).
///
/// `input_space` must be 0 (linear-sRGB primaries); other primaries are not yet
/// pinned. `k` must be a power of two ≤ 256 and ≤ `side²`. Each sub-kernel's rc is
/// propagated on failure (e.g. blue-noise `dither_mode` with a nil `stbn_mask` →
/// rcBadDitherMode). `scratch` must be ≥ `s4_burst_scratch_bytes`.
@_cdecl("s4_gif_encode_burst")
public func s4_gif_encode_burst(
    _ in_halfs: UnsafePointer<UInt16>?,
    _ frame_count: Int32,
    _ side: Int32,
    _ k: Int32,
    _ input_space: Int32,
    _ lloyd_iters: Int32,
    _ dither_mode: Int32,
    _ serpentine: Int32,
    _ stbn_mask: UnsafePointer<UInt8>?,
    _ frame_delay_cs: UInt16,
    _ comment: UnsafePointer<UInt8>?,
    _ comment_len: Int32,
    _ out_gif: UnsafeMutablePointer<UInt8>?,
    _ out_cap: Int,
    _ out_len: UnsafeMutablePointer<Int>?,
    _ scratch: UnsafeMutableRawPointer?,
    _ scratch_cap: Int
) -> Int32 {
    guard let halfs = in_halfs, let outGif = out_gif, let outLen = out_len, let scr = scratch else { return rcNullPtr }
    if frame_count <= 0 || side <= 0 || k <= 0 || k > 256 { return rcBadShape }
    if (k & (k - 1)) != 0 { return rcBadShape } // GIF local colour table needs power-of-two k
    if input_space != 0 { return rcBadShape } // only linear-sRGB primaries pinned (v1)

    let fc = Int(frame_count)
    let sidez = Int(side)
    let p = sidez * sidez
    let kk = Int(k)
    if kk > p { return rcBadShape } // maximin would emit duplicate seeds

    if scratch_cap < s4_burst_scratch_bytes(frame_count, side, k) { return rcScratchTooSmall }

    var carve = Carver(scr, scratch_cap)
    let allIndices = carve.take(UInt8.self, fc * p) // cross-frame: assembled at the end
    let allPalettes = carve.take(UInt8.self, fc * 3 * kk)
    let linQ16 = carve.take(Int32.self, p * 3)
    let oklabQ16 = carve.take(Int32.self, p * 3)
    let centroids = carve.take(Int32.self, kk * 3)
    let idxTmp = carve.take(UInt8.self, p)
    let qWords = p + 3 * kk + (kk + 1) / 2 // i64 sums + (rounded-up) i32 counts
    let qScratch = carve.take(Int64.self, qWords)
    let dScratch = carve.take(Int32.self, p * 3)
    if !carve.ok { return rcScratchTooSmall }

    let qScratchBytes = qWords * MemoryLayout<Int64>.stride
    let dScratchBytes = p * 3 * MemoryLayout<Int32>.stride
    let pp = Int32(p)

    var f = 0
    while f < fc {
        let halfsF = halfs + f * p * 3
        var rc = s4_widen_half_to_q16(halfsF, Int32(p * 3), linQ16)
        if rc != rcOK { return rc }
        rc = s4_linear_to_oklab_q16(linQ16, pp, oklabQ16)
        if rc != rcOK { return rc }
        // quantise → centroids (+ a throwaway nearest assignment we discard;
        // the dither pass produces the FINAL indices for this frame).
        rc = s4_quantize_frame(oklabQ16, pp, k, lloyd_iters, centroids, idxTmp, UnsafeMutableRawPointer(qScratch), qScratchBytes)
        if rc != rcOK { return rc }
        let stbnF: UnsafePointer<UInt8>? = stbn_mask == nil ? nil : stbn_mask! + f * p
        rc = s4_dither_frame(oklabQ16, centroids, pp, k, dither_mode, serpentine, stbnF, allIndices + f * p, UnsafeMutableRawPointer(dScratch), dScratchBytes)
        if rc != rcOK { return rc }
        rc = s4_palette_oklab_to_srgb8(centroids, k, allPalettes + f * 3 * kk, nil, 0)
        if rc != rcOK { return rc }
        f += 1
    }

    s4log("burst     \(frame_count)f \(side)²×\(k) → assemble (fold: widen→oklab→quant→dither→palette)")
    return s4_gif_assemble(allIndices, allPalettes, frame_count, side, k, frame_delay_cs, comment, comment_len, outGif, out_cap, outLen)
}

// ── GIF89a + LZW (byte-faithful port of GIFEncoder.swift via kernels.zig) ─────

// NOTE (ported private helpers): kernels.zig `LZW_SLOTS` / `LZW_EMPTY` / `lzwHash`.
// Open-addressed LZW dictionary, keyed by (prefix_code<<8 | byte). Power-of-two
// slot count; holds ≤ ~3837 live entries (load < 0.5). Stack-resident (≤48 KB).
private let lzwSlots = 8192
private let lzwEmpty: UInt32 = 0xFFFF_FFFF

@inline(__always)
private func lzwHash(_ key: UInt32) -> Int {
    Int((key &* 2_654_435_761) >> (32 - 13)) // top 13 bits → [0, 8191]
}

// NOTE (ported private helper): kernels.zig `GifWriter`.
// Append-only writer over a caller-owned buffer; flags (never overruns) overflow.
private struct GifWriter {
    let out: UnsafeMutablePointer<UInt8>
    let cap: Int
    var pos: Int = 0
    var overflow: Bool = false

    mutating func byte(_ b: UInt8) {
        if pos >= cap {
            overflow = true
            return
        }
        out[pos] = b
        pos += 1
    }

    mutating func u16le(_ v: UInt16) {
        byte(UInt8(v & 0xFF))
        byte(UInt8((v >> 8) & 0xFF))
    }
}

// NOTE (ported private helper): kernels.zig `BitSink` + `lzwEncodeFrame`,
// fused: the Zig `BitSink` struct held a pointer to the writer; Swift's
// exclusivity rules make that awkward, so its state (code_size/buf/cnt/sub)
// lives in locals here and its methods are local functions — the emitted
// byte sequence is IDENTICAL (LSB-first codes packed into ≤255-byte
// length-prefixed sub-blocks; mirrors GIFEncoder.lzwEncode's
// outputCode/flushSubBlock).
//
// LZW-compress one frame's indices into the GIF image-data stream: the
// minCodeSize byte, length-prefixed sub-blocks, then the 0x00 terminator.
private func lzwEncodeFrame(_ w: inout GifWriter, _ pixels: UnsafePointer<UInt8>, _ pixelCount: Int, _ k: Int32) {
    var mcs: UInt32 = 2
    while (UInt32(1) << mcs) < UInt32(k) { mcs += 1 }
    w.byte(UInt8(mcs))

    let clearCode: UInt32 = UInt32(1) << mcs
    let endCode: UInt32 = clearCode + 1
    let maxCode: UInt32 = 4095

    withUnsafeTemporaryAllocation(of: UInt32.self, capacity: lzwSlots) { keysBuf in
        withUnsafeTemporaryAllocation(of: UInt16.self, capacity: lzwSlots) { valsBuf in
            withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 255) { subBuf in
                let keys = keysBuf.baseAddress!
                let vals = valsBuf.baseAddress!
                let sub = subBuf.baseAddress!
                keys.update(repeating: lzwEmpty, count: lzwSlots)

                var codeSize: UInt32 = mcs + 1
                var bitBuf: UInt32 = 0
                var bitCnt: UInt32 = 0
                var subLen = 0

                func flushSub() {
                    if subLen != 0 {
                        w.byte(UInt8(subLen))
                        var i = 0
                        while i < subLen {
                            w.byte(sub[i])
                            i += 1
                        }
                        subLen = 0
                    }
                }
                func pushByte(_ b: UInt8) {
                    sub[subLen] = b
                    subLen += 1
                    if subLen == 255 { flushSub() }
                }
                func emit(_ code: UInt32) {
                    bitBuf |= code << bitCnt // cnt < 8 at every entry
                    bitCnt += codeSize
                    while bitCnt >= 8 {
                        pushByte(UInt8(bitBuf & 0xFF))
                        bitBuf >>= 8
                        bitCnt -= 8
                    }
                }
                func finish() {
                    if bitCnt > 0 { pushByte(UInt8(bitBuf & 0xFF)) }
                    flushSub()
                }

                var nextCode: UInt32 = endCode + 1

                emit(clearCode)
                if pixelCount == 0 {
                    emit(endCode)
                    finish()
                    w.byte(0x00)
                    return
                }

                var current: UInt32 = UInt32(pixels[0])
                var i = 1
                while i < pixelCount {
                    let px = UInt32(pixels[i])
                    let key: UInt32 = (current << 8) | px
                    var slot = lzwHash(key)
                    var found: UInt16? = nil
                    while keys[slot] != lzwEmpty {
                        if keys[slot] == key {
                            found = vals[slot]
                            break
                        }
                        slot = (slot + 1) & (lzwSlots - 1)
                    }
                    if let v = found {
                        current = UInt32(v)
                    } else {
                        emit(current)
                        if nextCode <= maxCode {
                            keys[slot] = key // `slot` is the empty slot the probe stopped on
                            vals[slot] = UInt16(nextCode)
                            nextCode += 1
                            if nextCode > (UInt32(1) << codeSize) && codeSize < 12 {
                                codeSize += 1
                            }
                        } else {
                            emit(clearCode) // at the CURRENT (pre-reset) code size
                            keys.update(repeating: lzwEmpty, count: lzwSlots)
                            codeSize = mcs + 1
                            nextCode = endCode + 1
                        }
                        current = px
                    }
                    i += 1
                }
                emit(current)
                emit(endCode)
                finish()
                w.byte(0x00)
            }
        }
    }
}

/// LZW + GIF89a serialisation from per-frame indices + sRGB8 palettes. Mirrors
/// GIFEncoder.swift / SixFour.Gen.GifWire byte-for-byte. `k` must be a power of
/// two ≤ 256. Writes the GIF length to `out_len`.
@_cdecl("s4_gif_assemble")
public func s4_gif_assemble(
    _ indices: UnsafePointer<UInt8>?,
    _ palettes_rgb: UnsafePointer<UInt8>?,
    _ frame_count: Int32,
    _ side: Int32,
    _ k: Int32,
    _ frame_delay_cs: UInt16,
    _ comment: UnsafePointer<UInt8>?,
    _ comment_len: Int32,
    _ out_gif: UnsafeMutablePointer<UInt8>?,
    _ out_cap: Int,
    _ out_len: UnsafeMutablePointer<Int>?
) -> Int32 {
    guard let idx = indices, let pal = palettes_rgb, let outGif = out_gif, let outLen = out_len else { return rcNullPtr }
    if frame_count <= 0 || side <= 0 || k <= 0 || k > 256 { return rcBadShape }
    if (k & (k - 1)) != 0 { return rcBadShape } // power of two
    let fc = Int(frame_count)
    let sidez = Int(side)
    let p = sidez * sidez
    let kk = Int(k)

    var w = GifWriter(out: outGif, cap: out_cap)

    // "GIF89a"
    w.byte(0x47); w.byte(0x49); w.byte(0x46); w.byte(0x38); w.byte(0x39); w.byte(0x61)
    w.u16le(UInt16(side)) // logical screen width
    w.u16le(UInt16(side)) // height
    w.byte(0x70) // packed: no GCT, colour-res 7
    w.byte(0x00) // background colour index
    w.byte(0x00) // pixel aspect ratio
    // NETSCAPE2.0 loop-forever block
    w.byte(0x21); w.byte(0xFF); w.byte(0x0B)
    w.byte(0x4E); w.byte(0x45); w.byte(0x54); w.byte(0x53); w.byte(0x43); w.byte(0x41)
    w.byte(0x50); w.byte(0x45); w.byte(0x32); w.byte(0x2E); w.byte(0x30)
    w.byte(0x03); w.byte(0x01); w.byte(0x00); w.byte(0x00); w.byte(0x00)

    if let cm = comment, comment_len > 0 {
        w.byte(0x21); w.byte(0xFE)
        let clen = Int(comment_len)
        var off = 0
        while off < clen {
            let chunk = min(255, clen - off)
            w.byte(UInt8(chunk))
            var j = 0
            while j < chunk {
                w.byte(cm[off + j])
                j += 1
            }
            off += chunk
        }
        w.byte(0x00)
    }

    // Image-descriptor LCT-size field: 2^(field+1) == k.
    var field: UInt32 = 0
    while (UInt32(1) << (field + 1)) < UInt32(k) { field += 1 }
    let packedDesc: UInt8 = 0x80 | UInt8(field)

    var f = 0
    while f < fc {
        // Graphic control extension (disposal 1, delay).
        w.byte(0x21); w.byte(0xF9); w.byte(0x04); w.byte(0x04)
        w.u16le(frame_delay_cs)
        w.byte(0x00)
        w.byte(0x00)
        // Image descriptor with LCT.
        w.byte(0x2C)
        w.u16le(0)
        w.u16le(0)
        w.u16le(UInt16(side))
        w.u16le(UInt16(side))
        w.byte(packedDesc)
        // Local colour table (k × RGB8) — bulk copy (same overflow semantics as
        // GifWriter.byte: write nothing + flag overflow if it wouldn't fit).
        let lctLen = kk * 3
        if w.pos + lctLen > w.cap {
            w.overflow = true
        } else {
            (w.out + w.pos).update(from: pal + f * lctLen, count: lctLen)
            w.pos += lctLen
        }
        // LZW image data.
        lzwEncodeFrame(&w, idx + f * p, p, k)
        f += 1
    }

    w.byte(0x3B) // trailer

    if w.overflow { return rcOutputTooSmall }
    outLen.pointee = w.pos
    s4log("gif       frames=\(frame_count) side=\(side) k=\(k) -> \(w.pos) bytes (LZW)")
    return rcOK
}

// ── GIF89a decoder — byte-faithful port of SixFour.Gen.GifDecode (the inverse of
// s4_gif_assemble). Parses the app dialect (no GCT, per-frame LCT, NETSCAPE loop,
// optional Comment ext, disposal-1 frames) + the standard variable-width LZW. ──

/// Working bytes s4_gif_decode needs: one frame's de-framed payload (≤ gif_len) +
/// the 4096-entry LZW dictionary (prefix Int32 + suffix UInt8 + first UInt8) + a
/// 4096-byte reconstruction stack + slack. 0 on gif_len == 0.
@_cdecl("s4_gif_decode_scratch_bytes")
public func s4_gif_decode_scratch_bytes(_ gif_len: Int) -> Int {
    if gif_len == 0 { return 0 }
    return gif_len + 4096 * MemoryLayout<Int32>.stride + 4096 + 4096 + 4096 + 1024
}

// NOTE (ported private helper): kernels.zig `GifReader`.
private struct GifReader {
    let g: UnsafePointer<UInt8>
    let len: Int
    var pos: Int = 0

    mutating func byte() -> UInt8? {
        if pos >= len { return nil }
        let b = g[pos]
        pos += 1
        return b
    }

    mutating func u16le() -> UInt16? {
        if pos + 2 > len { return nil }
        let v = UInt16(g[pos]) | (UInt16(g[pos + 1]) << 8)
        pos += 2
        return v
    }

    mutating func skip(_ n: Int) -> Bool {
        if pos + n > len { return false }
        pos += n
        return true
    }
}

// NOTE (ported private helper): kernels.zig `gifReadSubBlocks`.
// De-frame length-prefixed sub-blocks into `payload`; returns payload length or nil.
private func gifReadSubBlocks(_ r: inout GifReader, _ payload: UnsafeMutablePointer<UInt8>, _ payloadCap: Int) -> Int? {
    var n = 0
    while true {
        guard let len = r.byte() else { return nil }
        if len == 0 { return n }
        let l = Int(len)
        if r.pos + l > r.len || n + l > payloadCap { return nil }
        (payload + n).update(from: r.g + r.pos, count: l)
        n += l
        r.pos += l
    }
}

// NOTE (ported private helper): kernels.zig `gifReadCode`.
// Read one `size`-bit code, LSB-first (bit j of the code = stream bit pos+j).
private func gifReadCode(_ payload: UnsafePointer<UInt8>, _ totalBits: Int, _ bitpos: inout Int, _ size: Int) -> Int32? {
    if bitpos + size > totalBits { return nil }
    var code: Int32 = 0
    var j = 0
    while j < size {
        let i = bitpos + j
        let bit = Int32((payload[i >> 3] >> UInt8(i & 7)) & 1)
        code |= bit << Int32(j)
        j += 1
    }
    bitpos += size
    return code
}

// NOTE (ported private helper): kernels.zig `gifEmit`.
// Emit code's byte sequence (walk prefix chain into `emit`, output reversed). false on overflow.
private func gifEmit(
    _ code: Int32,
    _ prefix: UnsafePointer<Int32>,
    _ suffix: UnsafePointer<UInt8>,
    _ emit: UnsafeMutablePointer<UInt8>,
    _ emitCap: Int,
    _ out: UnsafeMutablePointer<UInt8>,
    _ outCap: Int,
    _ outN: inout Int
) -> Bool {
    var n = 0
    var k = code
    while prefix[Int(k)] != -1 {
        if n >= emitCap { return false }
        emit[n] = suffix[Int(k)]
        n += 1
        k = prefix[Int(k)]
    }
    if n >= emitCap || outN + n + 1 > outCap { return false }
    emit[n] = suffix[Int(k)] // root literal
    n += 1
    var t = 0
    while t < n {
        out[outN + t] = emit[n - 1 - t]
        t += 1
    }
    outN += n
    return true
}

// NOTE (ported private helper): kernels.zig `gifLzwDecode`.
// Decode one frame's LZW payload into `out`; returns pixel count or nil on malformed.
private func gifLzwDecode(
    _ payload: UnsafePointer<UInt8>,
    _ payloadLen: Int,
    _ mcs: Int,
    _ prefix: UnsafeMutablePointer<Int32>,
    _ suffix: UnsafeMutablePointer<UInt8>,
    _ first: UnsafeMutablePointer<UInt8>,
    _ emit: UnsafeMutablePointer<UInt8>,
    _ out: UnsafeMutablePointer<UInt8>,
    _ outCap: Int
) -> Int? {
    let clearCode: Int32 = Int32(1) << Int32(mcs)
    let endCode: Int32 = clearCode + 1
    let totalBits = payloadLen * 8
    var bitpos = 0
    var outN = 0

    // base table: literals 0..clear_code-1
    // (UInt8(c) is the trapping twin of Zig's `@intCast(c)` to u8: a malformed
    // mcs ≥ 9 traps at c == 256 in both implementations.)
    var c: Int32 = 0
    while c < clearCode {
        prefix[Int(c)] = -1
        suffix[Int(c)] = UInt8(c)
        first[Int(c)] = UInt8(c)
        c += 1
    }

    var size = mcs + 1
    guard var code = gifReadCode(payload, totalBits, &bitpos, size) else { return outN }
    if code == clearCode {
        guard let c2 = gifReadCode(payload, totalBits, &bitpos, size) else { return outN }
        code = c2
    }
    if code == endCode { return outN }
    if !gifEmit(code, prefix, suffix, emit, 4096, out, outCap, &outN) { return nil }
    var prevCode: Int32 = code
    var next: Int32 = endCode + 1

    while true {
        guard let cd = gifReadCode(payload, totalBits, &bitpos, size) else { break }
        if cd == endCode { break }
        if cd == clearCode {
            size = mcs + 1
            guard let lit = gifReadCode(payload, totalBits, &bitpos, size) else { break }
            if lit == endCode { break }
            if !gifEmit(lit, prefix, suffix, emit, 4096, out, outCap, &outN) { return nil }
            prevCode = lit
            next = endCode + 1
            continue
        }
        var head: UInt8
        if cd < next {
            if !gifEmit(cd, prefix, suffix, emit, 4096, out, outCap, &outN) { return nil }
            head = first[Int(cd)]
        } else { // KwKwK: cd == next, entry = prevEntry ++ [head prevEntry]
            head = first[Int(prevCode)]
            if !gifEmit(prevCode, prefix, suffix, emit, 4096, out, outCap, &outN) { return nil }
            if outN >= outCap { return nil }
            out[outN] = head
            outN += 1
        }
        if next < 4096 {
            prefix[Int(next)] = prevCode
            suffix[Int(next)] = head
            first[Int(next)] = first[Int(prevCode)]
        }
        next += 1
        if next == (Int32(1) << Int32(size)) && size < 12 { size += 1 }
        prevCode = cd
    }
    return outN
}

/// Decode a GIF89a (the app dialect) into per-frame indices + sRGB8 palettes.
/// Pass nil `out_indices`/`out_palettes_rgb` to SHAPE-PROBE: fills only
/// out_frame_count/out_side/out_k and returns rcOK without writing pixels (so the
/// caller can size the buffers). Otherwise `out_indices` is frame_count·side·side u8
/// and `out_palettes_rgb` is frame_count·k·3 u8. `scratch` ≥ s4_gif_decode_scratch_bytes.
@_cdecl("s4_gif_decode")
public func s4_gif_decode(
    _ gif: UnsafePointer<UInt8>?,
    _ gif_len: Int,
    _ out_indices: UnsafeMutablePointer<UInt8>?,
    _ out_palettes_rgb: UnsafeMutablePointer<UInt8>?,
    _ out_frame_count: UnsafeMutablePointer<Int32>?,
    _ out_side: UnsafeMutablePointer<Int32>?,
    _ out_k: UnsafeMutablePointer<Int32>?,
    _ scratch: UnsafeMutableRawPointer?,
    _ scratch_cap: Int
) -> Int32 {
    guard let g = gif, let outFC = out_frame_count, let outSide = out_side, let outK = out_k else { return rcNullPtr }
    if gif_len < 14 { return rcBadShape }
    let probe = (out_indices == nil || out_palettes_rgb == nil)

    var r = GifReader(g: g, len: gif_len)
    // header "GIF89a"
    if !(g[0] == 0x47 && g[1] == 0x49 && g[2] == 0x46 && g[3] == 0x38 && g[4] == 0x39 && g[5] == 0x61) {
        return rcBadShape
    }
    r.pos = 6
    guard r.u16le() != nil else { return rcBadShape } // canvas w
    guard r.u16le() != nil else { return rcBadShape } // canvas h
    guard let lsdPacked = r.byte() else { return rcBadShape }
    guard r.byte() != nil else { return rcBadShape } // bg
    guard r.byte() != nil else { return rcBadShape } // aspect
    if (lsdPacked & 0x80) != 0 { // skip a Global Colour Table (app never writes one)
        let gct = 3 * (1 << (Int(lsdPacked & 0x07) + 1))
        if !r.skip(gct) { return rcBadShape }
    }

    // scratch layout (full decode only)
    var prefix: UnsafeMutablePointer<Int32>?
    var suffix: UnsafeMutablePointer<UInt8>?
    var first: UnsafeMutablePointer<UInt8>?
    var emit: UnsafeMutablePointer<UInt8>?
    var payload: UnsafeMutablePointer<UInt8>?
    if !probe {
        let need = s4_gif_decode_scratch_bytes(gif_len)
        guard let scr = scratch, scratch_cap >= need else { return rcScratchTooSmall }
        var off = 0
        prefix = scr.bindMemory(to: Int32.self, capacity: 4096)
        off += 4096 * MemoryLayout<Int32>.stride
        suffix = (scr + off).bindMemory(to: UInt8.self, capacity: 4096)
        off += 4096
        first = (scr + off).bindMemory(to: UInt8.self, capacity: 4096)
        off += 4096
        emit = (scr + off).bindMemory(to: UInt8.self, capacity: 4096)
        off += 4096
        payload = (scr + off).bindMemory(to: UInt8.self, capacity: gif_len)
    }

    var frameCount: Int32 = 0
    var side: Int32 = 0
    var k: Int32 = 0

    while true {
        guard let tag = r.byte() else { return rcBadShape }
        if tag == 0x3B { break } // trailer
        if tag == 0x21 { // extension: label + sub-blocks (we skip the payload)
            guard r.byte() != nil else { return rcBadShape } // label
            while true {
                guard let len = r.byte() else { return rcBadShape }
                if len == 0 { break }
                if !r.skip(Int(len)) { return rcBadShape }
            }
            continue
        }
        if tag != 0x2C { return rcBadShape } // unknown block
        // image descriptor: left,top,iw,ih (u16) + packed
        guard r.u16le() != nil else { return rcBadShape }
        guard r.u16le() != nil else { return rcBadShape }
        guard let iw = r.u16le() else { return rcBadShape }
        guard let ih = r.u16le() else { return rcBadShape }
        guard let imgPacked = r.byte() else { return rcBadShape }
        if (imgPacked & 0x80) == 0 { return rcBadShape } // app always writes an LCT
        let lctSize = 1 << (Int(imgPacked & 0x07) + 1)

        if frameCount == 0 {
            side = Int32(iw)
            k = Int32(lctSize)
        } else if Int32(iw) != side || ih != iw || Int(k) != lctSize {
            return rcBadShape // non-uniform frames break the (T,side,k) contract
        }
        if iw != ih { return rcBadShape } // square frames only

        let f = Int(frameCount)
        if probe {
            if !r.skip(lctSize * 3) { return rcBadShape } // skip LCT
            guard r.byte() != nil else { return rcBadShape } // minCodeSize
            while true { // skip image sub-blocks
                guard let len = r.byte() else { return rcBadShape }
                if len == 0 { break }
                if !r.skip(Int(len)) { return rcBadShape }
            }
        } else {
            // copy LCT → out_palettes_rgb[f]
            if r.pos + lctSize * 3 > r.len { return rcBadShape }
            (out_palettes_rgb! + f * lctSize * 3).update(from: r.g + r.pos, count: lctSize * 3)
            r.pos += lctSize * 3
            guard let mcsByte = r.byte() else { return rcBadShape }
            guard let payloadLen = gifReadSubBlocks(&r, payload!, gif_len) else { return rcBadShape }
            let p = Int(iw) * Int(ih)
            // Zig `@intCast(mcs_byte)` to u5 traps on mcs_byte ≥ 32 in every safe
            // build mode; this precondition is that trap's exact Swift twin.
            precondition(mcsByte < 32, "GIF minCodeSize ≥ 32 (Zig u5 @intCast trap twin)")
            guard let got = gifLzwDecode(payload!, payloadLen, Int(mcsByte), prefix!, suffix!, first!, emit!, out_indices! + f * p, p) else {
                return rcOutputTooSmall
            }
            if got != p { return rcBadShape } // pixel count must match iw·ih
        }
        frameCount += 1
    }

    outFC.pointee = frameCount
    outSide.pointee = side
    outK.pointee = k
    s4log("gif_decode frames=\(frameCount) side=\(side) k=\(k) (probe=\(probe ? 1 : 0))")
    return rcOK
}
