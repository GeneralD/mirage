import Dependencies

/// The host-time axis (mach uptime) that presentation timestamps live on.
/// Sleeping, timers and debouncing use `\.continuousClock` instead; the two are
/// never compared with each other (docs/ARCHITECTURE.md → Two time sources).
public protocol HostTimeProvider: Sendable {
    func now() -> HostTimestamp
}

public enum HostTimeProviderKey: TestDependencyKey {
    /// Pure port: a fixed reading is a safe default, so tests that do not care
    /// about time need no override.
    public static let testValue: any HostTimeProvider = FrozenHostTime()
}

extension DependencyValues {
    public var hostTime: any HostTimeProvider {
        get { self[HostTimeProviderKey.self] }
        set { self[HostTimeProviderKey.self] = newValue }
    }
}

private struct FrozenHostTime: HostTimeProvider {
    func now() -> HostTimestamp { .zero }
}
