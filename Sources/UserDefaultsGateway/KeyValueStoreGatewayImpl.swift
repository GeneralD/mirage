import Domain
import Foundation

/// Live `KeyValueStoreGateway`: strings by key in the user's defaults, 1:1 over
/// `UserDefaults` (`string(forKey:)`, `set(_:forKey:)`, `removeObject(forKey:)`).
/// No branch and no state of its own; what a key holds and how it is encoded is
/// `PreferencesDataStore`'s.
///
/// `@unchecked Sendable`: the SDK does not mark `UserDefaults` `Sendable`, but its reads and
/// writes are documented thread-safe, and this struct holds nothing else.
public struct KeyValueStoreGatewayImpl: KeyValueStoreGateway, @unchecked Sendable {
    private let defaults: UserDefaults  // allow-physical: KeyValueStoreGateway

    /// `defaults` is the user's own (`.standard`) in the app; a smoke test passes a suite of
    /// its own so it never touches them.
    public init(defaults: UserDefaults = .standard) {  // allow-physical: KeyValueStoreGateway
        self.defaults = defaults
    }

    public func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    public func set(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func removeValue(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}
