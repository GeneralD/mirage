import Domain

/// What a picker cell draws once its artwork has met a decoder (#12): the decoded picture, or the
/// tile. It is generic over the decoded image so that the decision stays here, where it is tested,
/// while the type that holds pixels (`CGImage`) and the call that makes it stay with the view lane.
public enum EffectArtworkResolution<Image> {
    /// The thumbnail decoded.
    case image(Image)
    /// The tile: the effect has no thumbnail, or the one it has did not decode.
    case placeholder(EffectPlaceholder)
}

extension EffectArtworkResolution: Equatable where Image: Equatable {}
extension EffectArtworkResolution: Sendable where Image: Sendable {}

/// Decides what a cell draws for `artwork`. A thumbnail is handed to `decode`, which answers `nil`
/// for bytes it cannot turn into a picture: the package DataSource checked a thumbnail's size
/// and signature only, so a failed decode is expected, and it is answered with the tile the artwork
/// carries, never with an empty cell. A placeholder is never decoded.
public func resolveArtwork<Image>(
    _ artwork: EffectArtwork, decode: (EffectThumbnail) -> Image?
) -> EffectArtworkResolution<Image> {
    switch artwork {
    case .placeholder(let placeholder):
        .placeholder(placeholder)
    case .image(let thumbnail, let fallback):
        decode(thumbnail).map { .image($0) } ?? .placeholder(fallback)
    }
}
