import Domain
import Foundation

/// Small builders for the catalog values the suites write over and over, so a test
/// states what matters (the key, the origin, whether it is broken) and not the rest.
extension EffectID {
    public static func bundled(_ key: String) -> EffectID { EffectID(origin: .bundled, key: key) }
    public static func package(_ key: String) -> EffectID { EffectID(origin: .package, key: key) }
}

extension EffectCatalogEntry {
    /// An entry for `id`, shown as `displayName` (the key when omitted), `.ready` unless told otherwise, by no author and with
    /// no thumbnail unless one is given.
    public static func fixture(
        _ id: EffectID, displayName: String? = nil, availability: EffectAvailability = .ready, author: String? = nil,
        thumbnail: EffectThumbnail? = nil
    ) -> EffectCatalogEntry {
        EffectCatalogEntry(
            id: id, displayName: displayName ?? id.key, origin: id.origin, availability: availability, author: author, thumbnail: thumbnail)
    }
}

extension EffectThumbnailFormat {
    /// The bytes a file of this format begins with, for a test that writes one: PNG's signature, and a JPEG's
    /// start-of-image marker with the first byte of the marker after it.
    public var leadingBytes: [UInt8] {
        switch self {
        case .png: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        case .jpeg: [0xFF, 0xD8, 0xFF, 0xE0]
        }
    }
}

extension EffectThumbnail {
    /// A thumbnail of `format` whose bytes are the format's leading bytes and then `marker`, so two fixtures are told apart.
    public static func fixture(_ marker: UInt8 = 1, format: EffectThumbnailFormat = .png) -> EffectThumbnail {
        EffectThumbnail(data: Data(format.leadingBytes + [marker]), format: format)
    }
}

extension EffectCatalogState {
    /// The state of a menu that lists `entries` and has chosen the first of them.
    public static func fixture(_ entries: [EffectCatalogEntry], outcome: EffectSelectionOutcome? = nil) -> EffectCatalogState {
        EffectCatalogState(entries: entries, selection: entries[0].id, outcome: outcome)
    }
}

extension EffectPackage {
    /// A package whose manifest is valid, names `author` if one is given, whose source is `source`, and which was read
    /// with `thumbnail` (its manifest naming `thumbnail.png` for it).
    public static func fixture(
        _ id: EffectID, name: String? = nil, author: String? = nil, source: String = "kernel void effect() {}",
        thumbnail: EffectThumbnail? = nil
    ) -> EffectPackage {
        EffectPackage(
            id: id,
            manifest: EffectManifest(formatVersion: 1, name: name ?? id.key, author: author, thumbnail: thumbnail.map { _ in "thumbnail.png" }),
            source: EffectSource(name: name ?? id.key, source: source),
            thumbnail: thumbnail)
    }
}
