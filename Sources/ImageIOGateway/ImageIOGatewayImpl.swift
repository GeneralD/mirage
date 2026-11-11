/// `ImageIOGateway` live implementation, read half and the pixel layout.
/// OS API: `CGImageSourceCreateWithData`, `CGImageSourceCopyPropertiesAtIndex`,
/// `CGImageSourceCreateImageAtIndex`, `CGColorSpace(name:)`, `CGContext(data:...)`.
/// Every decision lives in the DataSource above; this only forwards and turns a nil into `ImageIOError`.
import CoreGraphics
import Dependencies
import Domain
import Foundation
import ImageIO

public struct ImageIOGatewayImpl: ImageIOGateway, Sendable {
    /// 8 bit BGRA with premultiplied alpha, 32 bit little-endian: the one pixel layout this gateway reads and writes.
    static let bitmapInfo: UInt32 = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

    public init() {}

    public func dimensions(of data: Data) throws -> StillImageSize {
        let source = try CGImageSourceCreateWithData(data as CFData, nil).orThrow(ImageIOError.notAnImage)
        let properties = try (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]).orThrow(ImageIOError.notAnImage)
        let width = try (properties[kCGImagePropertyPixelWidth] as? Int).orThrow(ImageIOError.notAnImage)
        let height = try (properties[kCGImagePropertyPixelHeight] as? Int).orThrow(ImageIOError.notAnImage)
        return StillImageSize(width: width, height: height)
    }

    public func decode(_ data: Data) throws -> StillImage {
        let source = try CGImageSourceCreateWithData(data as CFData, nil).orThrow(ImageIOError.notAnImage)
        let image = try CGImageSourceCreateImageAtIndex(source, 0, nil).orThrow(ImageIOError.notAnImage)
        let context = try CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: try CGColorSpace(name: CGColorSpace.sRGB).orThrow(ImageIOError.notAnImage), bitmapInfo: Self.bitmapInfo
        ).orThrow(ImageIOError.notAnImage)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let base = try context.data.orThrow(ImageIOError.notAnImage)
        // The pixels live in `context`'s memory, so the copy must finish while `context` is still alive.
        return withExtendedLifetime(context) {
            StillImage(
                width: image.width, height: image.height,
                bgra: Array(UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4)))
        }
    }
}
