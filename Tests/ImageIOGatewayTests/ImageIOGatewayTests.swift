import CoreGraphics
import Domain
import Foundation
import Testing

@testable import ImageIOGateway

/// Real ImageIO and CoreGraphics, no GPU: the only suite that proves the OS calls do what the thin Gateway
/// claims (the header read, the BGRA layout, the PNG signature and the round trip).
@Suite("ImageIOGateway")
struct ImageIOGatewayTests {
    private let gateway = ImageIOGatewayImpl()

    /// A 2 × 2 PNG: red top left, green top right, blue bottom left, half-transparent grey bottom right.
    private static let fixtureBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAE0lEQVR42mP4z8DwHwyBNAg0AABJSQl4nFEXkgAAAABJRU5ErkJggg=="

    /// The fixture's pixels as `decode` answers them: BGRA, premultiplied, top row first.
    private static let fixturePixels: [UInt8] = [0, 0, 255, 255, 0, 255, 0, 255, 255, 0, 0, 255, 128, 128, 128, 128]

    private func fixture() throws -> Data {
        try #require(Data(base64Encoded: Self.fixtureBase64))
    }

    @Test("dimensions reads the fixture as 2 wide and 2 high")
    func dimensionsOfFixture() throws {
        #expect(try gateway.dimensions(of: fixture()) == StillImageSize(width: 2, height: 2))
    }

    @Test("decode yields the fixture's pixels as premultiplied BGRA, top row first")
    func decodeFixture() throws {
        #expect(try gateway.decode(fixture()) == StillImage(width: 2, height: 2, bgra: Self.fixturePixels))
    }

    @Test("the pixel layout is premultiplied BGRA in 32 bit little-endian byte order")
    func pixelLayout() {
        #expect(ImageIOGatewayImpl.bitmapInfo == CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    }

    @Test("encodePNG writes bytes that begin with the PNG signature")
    func encodeStartsWithSignature() throws {
        let png = try gateway.encodePNG(gateway.decode(fixture()))
        #expect(Array(png.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    @Test("a decoded fixture encodes and decodes again with the same width, height and pixels")
    func fixtureRoundTrip() throws {
        let original = try gateway.decode(fixture())
        let again = try gateway.decode(gateway.encodePNG(original))
        #expect(again == original)
    }

    @Test("an opaque image of any size encodes and decodes again unchanged", arguments: [oneByOne, threeByTwo])
    func opaqueRoundTrip(image: StillImage) throws {
        #expect(try gateway.decode(gateway.encodePNG(image)) == image)
    }

    @Test("the PNG that encodePNG writes reports the size of the image it was given")
    func encodedSizeIsKept() throws {
        #expect(try gateway.dimensions(of: gateway.encodePNG(threeByTwo)) == StillImageSize(width: 3, height: 2))
    }

    @Test(
        "dimensions and decode say notAnImage for empty bytes, for text, and for three bytes that are no image",
        arguments: [Data(), Data("not an image".utf8), Data([1, 2, 3])])
    func notAnImage(bytes: Data) {
        #expect(throws: ImageIOError.notAnImage) { _ = try gateway.dimensions(of: bytes) }
        #expect(throws: ImageIOError.notAnImage) { _ = try gateway.decode(bytes) }
    }

    @Test(
        "encodePNG says encodeFailed for a byte count other than width * height * 4, and for a width or height of zero",
        arguments: [
            StillImage(width: 2, height: 2, bgra: Array(repeating: 0, count: 15)),
            StillImage(width: 2, height: 2, bgra: Array(repeating: 0, count: 17)),
            StillImage(width: 0, height: 2, bgra: []),
            StillImage(width: 2, height: 0, bgra: []),
            StillImage(width: 0, height: 0, bgra: []),
        ])
    func encodeFailure(image: StillImage) {
        #expect(throws: ImageIOError.encodeFailed) { _ = try gateway.encodePNG(image) }
    }
}

/// A 1 × 1 opaque image.
private let oneByOne = StillImage(width: 1, height: 1, bgra: [10, 20, 30, 255])

/// A 3 × 2 opaque image with a different colour in every pixel.
private let threeByTwo = StillImage(
    width: 3, height: 2, bgra: [0, 5, 9, 255, 40, 35, 29, 255, 80, 65, 49, 255, 120, 95, 69, 255, 160, 125, 89, 255, 200, 155, 109, 255])
