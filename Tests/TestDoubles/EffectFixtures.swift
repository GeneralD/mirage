import Domain

/// Small builders for the catalog values the suites write over and over, so a test
/// states what matters (the key, the origin, whether it is broken) and not the rest.
extension EffectID {
    public static func bundled(_ key: String) -> EffectID { EffectID(origin: .bundled, key: key) }
    public static func package(_ key: String) -> EffectID { EffectID(origin: .package, key: key) }
}

extension EffectCatalogEntry {
    /// An entry for `id`, shown as `displayName` (the key when omitted), `.ready` unless told otherwise.
    public static func fixture(_ id: EffectID, displayName: String? = nil, availability: EffectAvailability = .ready) -> EffectCatalogEntry {
        EffectCatalogEntry(id: id, displayName: displayName ?? id.key, origin: id.origin, availability: availability)
    }
}

extension EffectCatalogState {
    /// The state of a menu that lists `entries` and has chosen the first of them.
    public static func fixture(_ entries: [EffectCatalogEntry], outcome: EffectSelectionOutcome? = nil) -> EffectCatalogState {
        EffectCatalogState(entries: entries, selection: entries[0].id, outcome: outcome)
    }
}

extension EffectPackage {
    /// A package whose manifest is valid and whose source is `source`.
    public static func fixture(_ id: EffectID, name: String? = nil, source: String = "kernel void effect() {}") -> EffectPackage {
        EffectPackage(
            id: id,
            manifest: EffectManifest(formatVersion: 1, name: name ?? id.key),
            source: EffectSource(name: name ?? id.key, source: source))
    }
}
