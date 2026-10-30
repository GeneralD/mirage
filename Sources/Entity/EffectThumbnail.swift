import Foundation

/// The picture of a `.lens` package, for the effect picker (#12): the bytes of the file its
/// manifest's `thumbnail` names. The package DataSource makes one only from bytes it checked: at
/// most 1 MiB, and beginning with the signature of `format`. A signature is not a whole image, so
/// the bytes may still fail to decode, and a view that shows them must then show no picture.
/// Turning them into pixels is the view's; nothing below it decodes an image.
public struct EffectThumbnail: Sendable, Hashable {
    public let data: Data
    public let format: EffectThumbnailFormat

    public init(data: Data, format: EffectThumbnailFormat) {
        self.data = data
        self.format = format
    }
}

/// The image formats a thumbnail may be in. Which one it is comes from the bytes' signature,
/// not from the file name, for a decoder that wants to know the type before it reads.
public enum EffectThumbnailFormat: Sendable, Hashable, CaseIterable {
    case png
    case jpeg
}
