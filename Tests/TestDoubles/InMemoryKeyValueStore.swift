import Domain
import TestSupport

/// `KeyValueStoreGateway` over a dictionary: strings by key, as the user's defaults hold
/// them. `values` is the whole content for an assertion, and `writes` records the keys
/// that were set or removed, in order, so a subject that must not write is asserted to
/// have written nothing.
public final class InMemoryKeyValueStore: KeyValueStoreGateway, Sendable {
    private let stored: Locked<[String: String]>
    /// The keys `set` and `removeValue` were called with, in call order.
    public let writes = Collector<String>()

    public init(_ initial: [String: String] = [:]) {
        stored = Locked(initial)
    }

    public var values: [String: String] { stored.current }

    public func string(forKey key: String) -> String? {
        stored.withLock { $0[key] }
    }

    public func set(_ value: String, forKey key: String) {
        stored.withLock { $0[key] = value }
        writes.append(key)
    }

    public func removeValue(forKey key: String) {
        stored.withLock { $0[key] = nil }
        writes.append(key)
    }
}
