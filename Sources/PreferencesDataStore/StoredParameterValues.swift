import Domain
import Foundation

/// The form the parameter values of one effect are kept in: one JSON object of
/// `EffectParameterValue`s, under a key of its own. The key is the prefix `effect.parameters.v1.`
/// followed by the effect's `StoredEffectID` string, so two effects never share a key. Pure, and
/// persisted, so the prefix and the form are never changed: the object is written with sorted keys
/// and read back with the synthesized `Codable` of `EffectParameterValue` (`#75`).
enum StoredParameterValues {
    private static let keyPrefix = "effect.parameters.v1."

    static func key(of id: EffectID) -> String {
        keyPrefix + StoredEffectID.encode(id)
    }

    /// `nil` when a value does not encode: `JSONEncoder` throws on a `Float` that is NaN or infinite.
    static func encode(_ values: [String: EffectParameterValue]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(values) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// `nil` when the string is not a JSON object whose values are all `EffectParameterValue`s.
    static func decode(_ stored: String) -> [String: EffectParameterValue]? {
        try? JSONDecoder().decode([String: EffectParameterValue].self, from: Data(stored.utf8))
    }
}
