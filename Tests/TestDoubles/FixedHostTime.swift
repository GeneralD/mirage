import Domain

/// Host time the test moves by hand. `now()` never advances on its own.
public final class FixedHostTime: HostTimeProvider, Sendable {
    private let value: Locked<HostTimestamp>

    public init(_ start: HostTimestamp = .zero) {
        value = Locked(start)
    }

    public func now() -> HostTimestamp { value.current }

    public func set(_ timestamp: HostTimestamp) {
        value.set(timestamp)
    }

    public func advance(by duration: Duration) {
        value.withLock { $0 = $0.advanced(by: duration) }
    }
}
