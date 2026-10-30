import AppKit
import Domain
import TestDoubles
import Testing

@testable import AppRouter

/// The call that makes a picture of a thumbnail's bytes (#12), over the real AppKit decoder: it is
/// deterministic and touches no disk, camera or window. The catalog only checks a thumbnail's size
/// and signature, so what these pin is what `resolveArtwork` relies on: bytes that are not a whole
/// picture are `nil` and not an image of no size, which a cell would draw as an empty tile.
@Suite("EffectThumbnailDecoding", .timeLimit(.minutes(1)))
struct EffectThumbnailDecodingTests {
    /// A grey bitmap of `width` × `height` pixels in `type`: valid bytes for the decoder.
    private func picture(_ type: NSBitmapImageRep.FileType, width: Int, height: Int) throws -> Data {
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 1, hasAlpha: false,
                isPlanar: false, colorSpaceName: .deviceWhite, bytesPerRow: 0, bitsPerPixel: 0))
        return try #require(bitmap.representation(using: type, properties: [:]))
    }

    private func thumbnail(_ data: Data, format: EffectThumbnailFormat) -> EffectThumbnail {
        EffectThumbnail(data: data, format: format)
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

    @Test("bytes that begin with the signature and are not a picture are nil, not an image of no size", arguments: EffectThumbnailFormat.allCases)
    func signatureAloneIsNotAPicture(format: EffectThumbnailFormat) {
        let signature = Data(format.leadingBytes)
        let garbage = Data(format.leadingBytes + [UInt8](repeating: 0x41, count: 100))

        #expect(EffectThumbnailDecoding.image(of: thumbnail(signature, format: format)) == nil)
        #expect(EffectThumbnailDecoding.image(of: thumbnail(garbage, format: format)) == nil)
    }

    @Test("a picture cut off before its pixels, and no bytes at all, are nil", arguments: [NSBitmapImageRep.FileType.png, .jpeg])
    func truncatedPictureIsNil(type: NSBitmapImageRep.FileType) throws {
        let data = try picture(type, width: 12, height: 5)
        let format: EffectThumbnailFormat = type == .png ? .png : .jpeg

        #expect(EffectThumbnailDecoding.image(of: thumbnail(data.prefix(12), format: format)) == nil)
        #expect(EffectThumbnailDecoding.image(of: thumbnail(Data(), format: format)) == nil)
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
}
