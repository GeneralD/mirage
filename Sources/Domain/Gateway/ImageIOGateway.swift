import Dependencies
import Foundation

/// Why image bytes could not be read, or an image could not be written as PNG. Closed so that every
/// consumer enumerates it. `notAnImage` is what the gateway says of bytes it cannot read as an image
/// (empty, corrupt, or a format this build does not decode); `encodeFailed` is what it says of an image
/// it cannot write as PNG.
public enum ImageIOError: Error, Sendable, Equatable {
    /// The bytes cannot be read as an image.
    case notAnImage
    /// The image cannot be written as PNG.
    case encodeFailed
}

/// Thin pass-through to ImageIO and CoreGraphics (live: PNG decode and encode, host only), the only way
/// a still image is read or written. What a failure means for the authoring command is the DataSource's
/// decision, against `FakeImageIOGateway`; the gateway only reports which of the two failures it met.
public protocol ImageIOGateway: Sendable {
    /// The size of the image in `data`, read from its header only: no pixel is decoded. Throws
    /// `ImageIOError.notAnImage` when the bytes cannot be read as an image.
    func dimensions(of data: Data) throws -> StillImageSize

    /// The first frame of the image in `data`, as 8 bit sRGB premultiplied BGRA with the rows packed
    /// (`width * 4` bytes each). Throws `ImageIOError.notAnImage` when the bytes cannot be read as an image.
    func decode(_ data: Data) throws -> StillImage

    /// `image` as PNG bytes. Throws `ImageIOError.encodeFailed` when `image.bgra.count` is not
    /// `width * height * 4`, when the width or the height is not positive, or when the encoder fails.
    func encodePNG(_ image: StillImage) throws -> Data
}

public enum ImageIOGatewayKey: TestDependencyKey {
    public static let testValue: any ImageIOGateway = UnimplementedImageIOGateway()
}

extension DependencyValues {
    public var imageIOGateway: any ImageIOGateway {
        get { self[ImageIOGatewayKey.self] }
        set { self[ImageIOGatewayKey.self] = newValue }
    }
}

private struct UnimplementedImageIOGateway: ImageIOGateway {
    func dimensions(of data: Data) throws -> StillImageSize {
        reportIssue("ImageIOGateway.dimensions not implemented")
        throw ImageIOError.notAnImage
    }

    func decode(_ data: Data) throws -> StillImage {
        reportIssue("ImageIOGateway.decode not implemented")
        throw ImageIOError.notAnImage
    }

    func encodePNG(_ image: StillImage) throws -> Data {
        reportIssue("ImageIOGateway.encodePNG not implemented")
        throw ImageIOError.encodeFailed
    }
}
