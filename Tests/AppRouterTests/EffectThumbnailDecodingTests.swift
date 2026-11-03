import AppKit
import Domain
import TestDoubles
import Testing

@testable import AppRouter

/// The call that makes a picture of a thumbnail's bytes (#12), over the real AppKit decoder: it is
/// deterministic and writes nothing, touches no camera or window, and reads one file of the
/// repository, `Examples/Ripple.lens/thumbnail.png`, the picture the README ships. The catalog only
/// checks a thumbnail's size and signature, so what these pin is what `resolveArtwork` relies on:
/// bytes that are not a picture are `nil` and not an image of no size, which a cell would draw as an
/// empty tile, and a picture is the picture it was and no larger than the limit.
///
/// What is not pinned: a PNG or JPEG cut off inside its pixel data. The decoder answers an image of
/// the header's size with the rows it never got drawn black (PNG) or grey (JPEG), and says nothing of
/// its being incomplete; that is the OS's behaviour, observed and written down in
/// `docs/ARCHITECTURE.md` → *Effect picker*, and not something to hold a build to.
@Suite("EffectThumbnailDecoding", .timeLimit(.minutes(1)))
struct EffectThumbnailDecodingTests {
    private static let ripple = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Examples/Ripple.lens/thumbnail.png")

    /// A grey bitmap of `width` × `height` pixels in `type`: valid bytes for the decoder. With `points`, the
    /// bitmap says it is that many points across, which a Retina export does: its pixels are twice them.
    private func picture(_ type: NSBitmapImageRep.FileType, width: Int, height: Int, points: NSSize? = nil) throws -> Data {
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 1, hasAlpha: false,
                isPlanar: false, colorSpaceName: .deviceWhite, bytesPerRow: 0, bitsPerPixel: 0))
        if let points { bitmap.size = points }
        return try #require(bitmap.representation(using: type, properties: [:]))
    }

    /// A `side` × `side` RGB bitmap in `type` filled with one colour: the pixels a decoder must hand back.
    private func solid(_ type: NSBitmapImageRep.FileType, side: Int, red: UInt8, green: UInt8, blue: UInt8) throws -> Data {
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let pixels = try #require(bitmap.bitmapData)
        for row in 0..<side {
            for column in 0..<side {
                let offset = row * bitmap.bytesPerRow + column * 3
                pixels[offset] = red
                pixels[offset + 1] = green
                pixels[offset + 2] = blue
            }
        }
        return try #require(bitmap.representation(using: type, properties: [:]))
    }

    private func thumbnail(_ data: Data, format: EffectThumbnailFormat) -> EffectThumbnail {
        EffectThumbnail(data: data, format: format)
    }

    /// `image` drawn into a `side` × `side` RGBA bitmap: the colours a viewer would see, one row after another.
    private func rendered(_ image: CGImage, side: Int = 8) throws -> [UInt8] {
        let context = try #require(
            CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        let data = try #require(context.data)
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: side * side * 4))
    }

    @Test(
        "a PNG and a JPEG decode to an image of their own size",
        arguments: [(NSBitmapImageRep.FileType.png, EffectThumbnailFormat.png), (.jpeg, .jpeg)])
    func decodesAPicture(type: NSBitmapImageRep.FileType, format: EffectThumbnailFormat) throws {
        let data = try picture(type, width: 12, height: 5)

        let image = EffectThumbnailDecoding.image(of: thumbnail(data, format: format))

        #expect(image?.width == 12)
        #expect(image?.height == 5)
    }

    @Test(
        "the pixels are the picture's: a solid colour comes back as that colour, in either format",
        arguments: [(NSBitmapImageRep.FileType.png, EffectThumbnailFormat.png), (.jpeg, .jpeg)])
    func decodesTheColour(type: NSBitmapImageRep.FileType, format: EffectThumbnailFormat) throws {
        let data = try solid(type, side: 8, red: 255, green: 0, blue: 0)

        let image = try #require(EffectThumbnailDecoding.image(of: thumbnail(data, format: format)))
        let pixels = try rendered(image)

        // The middle of the picture, with a margin for the colour conversion and for JPEG's loss.
        let middle = (4 * 8 + 4) * 4
        #expect(pixels[middle] > 220, "red")
        #expect(pixels[middle + 1] < 40, "green")
        #expect(pixels[middle + 2] < 40, "blue")
    }

    @Test("the picture the README ships, Examples/Ripple.lens/thumbnail.png, decodes at its own size and is not one flat colour")
    func decodesTheShippedExample() throws {
        let data = try Data(contentsOf: Self.ripple)

        let image = try #require(EffectThumbnailDecoding.image(of: thumbnail(data, format: .png)))
        let pixels = try rendered(image)

        #expect(image.width == 256)
        #expect(image.height == 256)
        let colours = Set(stride(from: 0, to: pixels.count, by: 4).map { Array(pixels[$0..<$0 + 3]) })
        #expect(colours.count > 1, "a decoder that handed back a blank bitmap would draw a flat square")
    }

    @Test("bytes that begin with the signature and are not a picture are nil, not an image of no size", arguments: EffectThumbnailFormat.allCases)
    func signatureAloneIsNotAPicture(format: EffectThumbnailFormat) {
        let signature = Data(format.leadingBytes)
        let garbage = Data(format.leadingBytes + [UInt8](repeating: 0x41, count: 100))

        #expect(EffectThumbnailDecoding.image(of: thumbnail(signature, format: format)) == nil)
        #expect(EffectThumbnailDecoding.image(of: thumbnail(garbage, format: format)) == nil)
    }

    @Test("a picture cut off inside its header, and no bytes at all, are nil", arguments: [NSBitmapImageRep.FileType.png, .jpeg])
    func truncatedHeaderIsNil(type: NSBitmapImageRep.FileType) throws {
        let data = try picture(type, width: 12, height: 5)
        let format: EffectThumbnailFormat = type == .png ? .png : .jpeg

        for length in [12, 33] {
            #expect(EffectThumbnailDecoding.image(of: thumbnail(data.prefix(length), format: format)) == nil, "cut at \(length) bytes")
        }
        #expect(EffectThumbnailDecoding.image(of: thumbnail(Data(), format: format)) == nil)
    }

    @Test("a PNG that says it has no pixels is nil, not an image of no size")
    func zeroSizeIsNil() {
        for (width, height) in [(0, 0), (0, 10), (10, 0)] as [(UInt32, UInt32)] {
            let data = pngClaiming(width: width, height: height)

            #expect(EffectThumbnailDecoding.image(of: thumbnail(data, format: .png)) == nil, "\(width) × \(height)")
        }
    }

    @Test("a picture of exactly the most pixels decodes, and one with more is nil: it would draw into far more memory than a cell is worth")
    func pixelLimit() throws {
        #expect(EffectThumbnailDecoding.maxPixels == 2048 * 2048, "the shapes below are written for this limit")
        let square = try picture(.png, width: 2048, height: 2048)
        let wide = try picture(.png, width: 4096, height: 1024)
        let overSquare = try picture(.png, width: 2049, height: 2049)
        let overWide = try picture(.png, width: 4097, height: 1024)

        #expect(EffectThumbnailDecoding.image(of: thumbnail(square, format: .png)) != nil)
        #expect(EffectThumbnailDecoding.image(of: thumbnail(wide, format: .png)) != nil)
        #expect(EffectThumbnailDecoding.image(of: thumbnail(overSquare, format: .png)) == nil)
        #expect(EffectThumbnailDecoding.image(of: thumbnail(overWide, format: .png)) == nil)
    }

    @Test("the limit counts pixels and not points: a picture that says it is half as wide in points is judged by its pixels")
    func pixelLimitIsInPixels() throws {
        let atTheLimit = try picture(.png, width: 2048, height: 2048, points: NSSize(width: 1024, height: 1024))
        let over = try picture(.png, width: 2049, height: 2049, points: NSSize(width: 1024.5, height: 1024.5))

        #expect(EffectThumbnailDecoding.image(of: thumbnail(atTheLimit, format: .png)) != nil)
        #expect(EffectThumbnailDecoding.image(of: thumbnail(over, format: .png)) == nil)
    }

    /// A PNG file made by hand: the signature, a header that says `width` × `height`, and an image
    /// data chunk that holds an empty zlib stream. It is well formed apart from having no pixels
    /// where the header says there are some, which is all that a decoder is asked about here.
    private func pngClaiming(width: UInt32, height: UInt32) -> Data {
        func bigEndian(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8((value >> UInt32(24 - 8 * $0)) & 0xFF) } }
        func chunk(_ name: String, _ body: [UInt8]) -> [UInt8] {
            let typed = Array(name.utf8) + body
            return bigEndian(UInt32(body.count)) + typed + bigEndian(crc32(typed))
        }
        func crc32(_ bytes: [UInt8]) -> UInt32 {
            ~bytes.reduce(UInt32.max) { crc, byte in
                (0..<8).reduce(crc ^ UInt32(byte)) { value, _ in value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
            }
        }
        let header = bigEndian(width) + bigEndian(height) + [8, 0, 0, 0, 0]
        let emptyZlibStream: [UInt8] = [0x78, 0x01, 0x01, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x01]
        return Data(EffectThumbnailFormat.png.leadingBytes + chunk("IHDR", header) + chunk("IDAT", emptyZlibStream) + chunk("IEND", []))
    }
}
