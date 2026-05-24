import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import simd

/// Render 64 OKLab tiles back to sRGB as an 8×8 grid PNG (no palette quantization).
/// Saved alongside each captured GIF so the user can verify the *raw* capture before
/// judging the palette quantizer.
enum ContactSheet {

    enum Error: Swift.Error {
        case wrongTileCount(Int)
        case cgContextFailed
        case pngEncodeFailed
    }

    static func writePNG(tiles: [OKLabTile], to url: URL, cols: Int = 8, rows: Int = 8) throws {
        if tiles.count != rows * cols {
            throw Error.wrongTileCount(tiles.count)
        }
        let tileSide = tiles[0].side
        let width = cols * tileSide
        let height = rows * tileSide

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for (i, tile) in tiles.enumerated() {
            let row = i / cols
            let col = i % cols
            for ty in 0..<tileSide {
                for tx in 0..<tileSide {
                    let lab = OKLab(tile.pixels[ty * tileSide + tx])
                    let s = ColorScience.okLabToSRGB8(lab)
                    let dy = row * tileSide + ty
                    let dx = col * tileSide + tx
                    let idx = (dy * width + dx) * 4
                    pixels[idx + 0] = s.x
                    pixels[idx + 1] = s.y
                    pixels[idx + 2] = s.z
                    pixels[idx + 3] = 255
                }
            }
        }

        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx = pixels.withUnsafeMutableBytes({ raw -> CGContext? in
            CGContext(
                data: raw.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: cs, bitmapInfo: bitmapInfo.rawValue
            )
        }), let cg = ctx.makeImage() else {
            throw Error.cgContextFailed
        }

        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { throw Error.pngEncodeFailed }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { throw Error.pngEncodeFailed }
        try (data as Data).write(to: url)
    }
}
