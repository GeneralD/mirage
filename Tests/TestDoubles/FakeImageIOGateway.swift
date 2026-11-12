import Domain
import Foundation
import TestSupport

/// `ImageIOGateway` over scripted answers: the test says which bytes are an image, and the fake answers
/// only for those bytes; any other bytes read as `ImageIOError.notAnImage`. Every call is recorded, failing
/// ones included: `dimensionRequests` and `decodes` for the reads, `encodes` for the images handed to
/// `encodePNG`. `encodePNG` returns the stand-in bytes of `encoded(_:)` and scripts them as the same image,
/// so a round trip through the fake answers with the image it started from.
public final class FakeImageIOGateway: ImageIOGateway, Sendable {
    /// What the fake answers for one set of bytes.
    private enum Answer: Sendable {
        /// The bytes are this image: `dimensions` answers its size and `decode` answers the image itself.
        case image(StillImage)
        /// The bytes have this size: `dimensions` answers it and `decode` still says `notAnImage`.
        case size(StillImageSize)
    }

    private let answers = Locked<[Data: Answer]>([:])
    private let encodeFails = Locked(false)
    /// The bytes `dimensions(of:)` was asked about, in call order.
    public let dimensionRequests = Collector<Data>()
    /// The bytes `decode(_:)` was asked about, in call order.
    public let decodes = Collector<Data>()
    /// The images `encodePNG(_:)` was asked to write, in call order.
    public let encodes = Collector<StillImage>()

    public init() {}

    /// Makes `data` answer as `image`: its `dimensions` is the image's size and its `decode` is the image.
    /// Scripting the same bytes again replaces the earlier answer, whichever kind it was.
    public func script(_ image: StillImage, for data: Data) {
        answers.withLock { $0[data] = .image(image) }
    }

    /// Makes `dimensions(of:)` of `data` answer `size`; `decode(_:)` of those bytes still says `notAnImage`.
    /// Scripting the same bytes again replaces the earlier answer, whichever kind it was.
    public func script(_ size: StillImageSize, for data: Data) {
        answers.withLock { $0[data] = .size(size) }
    }

    /// While `fail` is `true`, `encodePNG` throws `ImageIOError.encodeFailed`, even for a valid image.
    public func failEncode(_ fail: Bool) {
        encodeFails.set(fail)
    }

    /// The stand-in PNG bytes `encodePNG` returns for `image`: a text header with the size, then the pixels.
    public static func encoded(_ image: StillImage) -> Data {
        Data("fakepng:\(image.width)x\(image.height):".utf8) + Data(image.bgra)
    }

    public func dimensions(of data: Data) throws -> StillImageSize {
        dimensionRequests.append(data)
        switch answers.withLock({ $0[data] }) {
        case .some(.image(let image)):
            return StillImageSize(width: image.width, height: image.height)
        case .some(.size(let size)):
            return size
        case .none:
            throw ImageIOError.notAnImage
        }
    }

    public func decode(_ data: Data) throws -> StillImage {
        decodes.append(data)
        guard case .some(.image(let image)) = answers.withLock({ $0[data] }) else {
            throw ImageIOError.notAnImage
        }
        return image
    }

    public func encodePNG(_ image: StillImage) throws -> Data {
        encodes.append(image)
        guard !encodeFails.current, Self.isEncodable(image) else {
            throw ImageIOError.encodeFailed
        }
        let bytes = Self.encoded(image)
        script(image, for: bytes)
        return bytes
    }

    /// The same checks the live encoder is held to: positive sides, and exactly `width * height * 4` bytes.
    private static func isEncodable(_ image: StillImage) -> Bool {
        image.width > 0 && image.height > 0 && image.bgra.count == image.width * image.height * 4
    }
}
