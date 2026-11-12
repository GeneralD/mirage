/// `ImageIOGateway` live implementation, write half.
/// OS API: `CGImage(width:...)`, `CGDataProvider(data:)`, `CGImageDestinationCreateWithData`,
/// `CGImageDestinationAddImage`, `CGImageDestinationFinalize`.
import CoreGraphics
import Domain
import Foundation
import ImageIO

extension ImageIOGatewayImpl {
    public func encodePNG(_ image: StillImage) throws -> Data {
        try (image.bgra.count == image.width * image.height * 4).orThrow(ImageIOError.encodeFailed)
        let cgImage = try CGImage(
            width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: image.width * 4,
            space: try CGColorSpace(name: CGColorSpace.sRGB).orThrow(ImageIOError.encodeFailed),
            bitmapInfo: CGBitmapInfo(rawValue: Self.bitmapInfo),
            provider: try CGDataProvider(data: Data(image.bgra) as CFData).orThrow(ImageIOError.encodeFailed),
            decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ).orThrow(ImageIOError.encodeFailed)
        let output = NSMutableData()
        let destination = try CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil).orThrow(ImageIOError.encodeFailed)
        CGImageDestinationAddImage(destination, cgImage, nil)
        try CGImageDestinationFinalize(destination).orThrow(ImageIOError.encodeFailed)
        return output as Data
    }
}
