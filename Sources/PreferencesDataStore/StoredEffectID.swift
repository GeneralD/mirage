import Domain

/// The string an `EffectID` is kept as in the user's defaults (epic #42, D6): the origin's
/// raw value, one colon, then the key as it is — `package:glitch`, `bundled:Chromatic Grain`.
/// Pure, and persisted, so the form is never changed: a build that finds a string it does not
/// know ignores it (`Preferences.selectedEffect()`), but it cannot read one it should know.
///
/// The string is cut at the first colon. An origin never contains one and a key may (a folder
/// name can), so the key is whatever follows it, empty included. It is cut by Unicode scalar,
/// not by character: a key that starts with a combining mark would otherwise fuse with the
/// colon in front of it into one character that is not a colon. What decodes encodes back to
/// the same string, and every `EffectID` decodes from its encoding.
enum StoredEffectID {
    private static let separator: Unicode.Scalar = ":"

    static func encode(_ id: EffectID) -> String {
        "\(id.origin.rawValue)\(separator)\(id.key)"
    }

    /// `nil` when the string has no colon, or what precedes the first one is not the raw value
    /// of an `EffectOrigin` (case matters).
    static func decode(_ stored: String) -> EffectID? {
        let scalars = stored.unicodeScalars
        guard let colon = scalars.firstIndex(of: separator),
            let origin = EffectOrigin(rawValue: String(scalars[..<colon]))
        else { return nil }
        return EffectID(origin: origin, key: String(scalars[scalars.index(after: colon)...]))
    }
}
