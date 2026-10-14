/// Where an effect comes from: compiled into the app, or loaded from a `.lens`
/// package in the effects folder (epic #42, D1 / D3). The raw value is what is
/// persisted (`EffectID`'s `Codable` form), so a case is never renamed.
public enum EffectOrigin: String, Sendable, Hashable, Codable, CaseIterable {
    case bundled
    case package
}

/// The identity of one effect, stable across edits (epic #42, D1). A bundled effect
/// is keyed by its name; a package by its folder name without the `.lens`
/// extension, so editing a package's manifest or shader never changes who it is.
/// The menu shows the manifest's `name`, never the key.
public struct EffectID: Sendable, Hashable, Codable {
    public let origin: EffectOrigin
    public let key: String

    public init(origin: EffectOrigin, key: String) {
        self.origin = origin
        self.key = key
    }
}
