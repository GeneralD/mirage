import Dependencies

/// Thin pass-through to the user's defaults (live: `UserDefaults`): strings by key,
/// nothing else. What is stored under a key and how it is encoded is the DataStore's
/// (`PreferencesDataStore`).
public protocol KeyValueStoreGateway: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
    func removeValue(forKey key: String)
}

public enum KeyValueStoreGatewayKey: TestDependencyKey {
    public static let testValue: any KeyValueStoreGateway = UnimplementedKeyValueStoreGateway()
}

extension DependencyValues {
    public var keyValueStoreGateway: any KeyValueStoreGateway {
        get { self[KeyValueStoreGatewayKey.self] }
        set { self[KeyValueStoreGatewayKey.self] = newValue }
    }
}

private struct UnimplementedKeyValueStoreGateway: KeyValueStoreGateway {
    func string(forKey key: String) -> String? {
        reportIssue("KeyValueStoreGateway.string not implemented")
        return nil
    }

    func set(_ value: String, forKey key: String) {
        reportIssue("KeyValueStoreGateway.set not implemented")
    }

    func removeValue(forKey key: String) {
        reportIssue("KeyValueStoreGateway.removeValue not implemented")
    }
}
