import Foundation

/// The picture a `.lens` package shows in the effect picker (#12): the bytes of the file its
/// manifest's `thumbnail` names, as the package DataSource read them. They are already checked:
/// at most 1 MiB, and beginning with the signature of `format`. Turning them into pixels is the
/// view's; nothing below it decodes an image.
public struct EffectThumbnail: Sendable, Hashable {
    public let data: Data
    public let format: EffectThumbnailFormat

    public init(data: Data, format: EffectThumbnailFormat) {
        self.data = data
        self.format = format
    }
}

/// The image formats a thumbnail may be in. Which one it is comes from the bytes' signature,
/// not from the file name.
public enum EffectThumbnailFormat: Sendable, Hashable, CaseIterable {
    case png
    case jpeg
}
