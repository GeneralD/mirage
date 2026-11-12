import Dependencies
import Domain
import Foundation
import TestDoubles
import Testing

@Suite("FakeImageIOGateway")
struct FakeImageIOGatewayTests {
    /// A 2 × 2 image: 16 bytes, one row of 8 bytes per line.
    private static let photo = StillImage(width: 2, height: 2, bgra: [UInt8](repeating: 0x7F, count: 16))
    private static let bytes = Data([1, 2, 3])

    @Test("bytes that were never scripted read as notAnImage from both dimensions and decode, and both calls are recorded")
    func unscriptedBytesAreNotAnImage() {
        let fake = FakeImageIOGateway()

        #expect(throws: ImageIOError.notAnImage) { _ = try fake.dimensions(of: Self.bytes) }
        #expect(throws: ImageIOError.notAnImage) { _ = try fake.decode(Self.bytes) }
        #expect(fake.dimensionRequests.values == [Self.bytes])
        #expect(fake.decodes.values == [Self.bytes])
    }

    @Test("script of an image makes dimensions answer its size and decode answer the image itself")
    func scriptedImageAnswersSizeAndImage() throws {
        let fake = FakeImageIOGateway()
        fake.script(Self.photo, for: Self.bytes)

        #expect(try fake.dimensions(of: Self.bytes) == StillImageSize(width: 2, height: 2))
        #expect(try fake.decode(Self.bytes) == Self.photo)
    }

    @Test("script of an image does not answer for other bytes")
    func scriptedImageDoesNotLeakToOtherBytes() {
        let fake = FakeImageIOGateway()
        fake.script(Self.photo, for: Self.bytes)

        #expect(throws: ImageIOError.notAnImage) { _ = try fake.dimensions(of: Data([9])) }
        #expect(throws: ImageIOError.notAnImage) { _ = try fake.decode(Data([9])) }
    }

    @Test("script of a size makes dimensions answer that size and decode still say notAnImage")
    func scriptedSizeAnswersOnlyDimensions() throws {
        let fake = FakeImageIOGateway()
        fake.script(StillImageSize(width: 3, height: 5), for: Self.bytes)

        #expect(try fake.dimensions(of: Self.bytes) == StillImageSize(width: 3, height: 5))
        #expect(throws: ImageIOError.notAnImage) { _ = try fake.decode(Self.bytes) }
    }

    @Test("scripting the same bytes again replaces the earlier answer, whichever kind it was")
    func rescriptReplacesTheEarlierAnswer() throws {
        let fake = FakeImageIOGateway()
        fake.script(Self.photo, for: Self.bytes)
        fake.script(StillImageSize(width: 7, height: 1), for: Self.bytes)

        #expect(try fake.dimensions(of: Self.bytes) == StillImageSize(width: 7, height: 1))
        #expect(throws: ImageIOError.notAnImage) { _ = try fake.decode(Self.bytes) }

        fake.script(Self.photo, for: Self.bytes)

        #expect(try fake.decode(Self.bytes) == Self.photo)
        #expect(try fake.dimensions(of: Self.bytes) == StillImageSize(width: 2, height: 2))
    }

    @Test("encodePNG returns the stand-in bytes, records the image, and the bytes decode back to the same image")
    func encodePNGRoundTripsThroughTheFake() throws {
        let fake = FakeImageIOGateway()

        let encoded = try fake.encodePNG(Self.photo)

        #expect(encoded == FakeImageIOGateway.encoded(Self.photo))
        #expect(fake.encodes.values == [Self.photo])
        #expect(try fake.decode(encoded) == Self.photo)
        #expect(try fake.dimensions(of: encoded) == StillImageSize(width: 2, height: 2))
    }

    @Test("different images encode to different bytes, whether they differ in size or in pixels")
    func differentImagesEncodeToDifferentBytes() {
        let wide = StillImage(width: 2, height: 1, bgra: [UInt8](repeating: 0x7F, count: 8))
        let tall = StillImage(width: 1, height: 2, bgra: [UInt8](repeating: 0x7F, count: 8))
        let otherPixels = StillImage(width: 2, height: 2, bgra: [UInt8](repeating: 0x80, count: 16))

        #expect(FakeImageIOGateway.encoded(wide) != FakeImageIOGateway.encoded(tall))
        #expect(FakeImageIOGateway.encoded(Self.photo) != FakeImageIOGateway.encoded(otherPixels))
    }

    @Test("encodePNG refuses an image whose byte count is not width times height times four, and records the attempt")
    func encodePNGRefusesAMismatchedByteCount() {
        let fake = FakeImageIOGateway()
        let short = StillImage(width: 2, height: 2, bgra: [UInt8](repeating: 0, count: 15))

        #expect(throws: ImageIOError.encodeFailed) { _ = try fake.encodePNG(short) }
        #expect(fake.encodes.values == [short])
    }

    @Test("encodePNG refuses an image whose width or height is not positive, even with a consistent byte count")
    func encodePNGRefusesANonPositiveSize() {
        let fake = FakeImageIOGateway()
        let noWidth = StillImage(width: 0, height: 2, bgra: [])
        let noHeight = StillImage(width: 2, height: 0, bgra: [])
        let negative = StillImage(width: -2, height: -2, bgra: [UInt8](repeating: 0, count: 16))

        #expect(throws: ImageIOError.encodeFailed) { _ = try fake.encodePNG(noWidth) }
        #expect(throws: ImageIOError.encodeFailed) { _ = try fake.encodePNG(noHeight) }
        #expect(throws: ImageIOError.encodeFailed) { _ = try fake.encodePNG(negative) }
        #expect(fake.encodes.values == [noWidth, noHeight, negative])
    }

    @Test("while failEncode is on, encodePNG refuses even a valid image, and turning it off restores encoding")
    func failEncodeRefusesAValidImageUntilTurnedOff() throws {
        let fake = FakeImageIOGateway()

        fake.failEncode(true)
        #expect(throws: ImageIOError.encodeFailed) { _ = try fake.encodePNG(Self.photo) }

        fake.failEncode(false)
        #expect(try fake.encodePNG(Self.photo) == FakeImageIOGateway.encoded(Self.photo))
        #expect(fake.encodes.count == 2)
    }

    @Test("ImageIOError tells a bad image from a failed encode")
    func imageIOErrorDistinguishesItsCases() {
        #expect(ImageIOError.notAnImage != ImageIOError.encodeFailed)
        #expect(ImageIOError.notAnImage == ImageIOError.notAnImage)
    }

    @Test("imageIOGateway resolves to the fake a test puts in its dependencies")
    func dependencyKeyResolvesTheFake() {
        let fake = FakeImageIOGateway()
        withDependencies {
            $0.imageIOGateway = fake
        } operation: {
            @Dependency(\.imageIOGateway) var gateway
            _ = try? gateway.dimensions(of: Self.bytes)
        }
        #expect(fake.dimensionRequests.values == [Self.bytes])
    }
}
