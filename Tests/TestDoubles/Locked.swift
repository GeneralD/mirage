import Foundation

/// A lock-protected box so a test double can be `Sendable` while every test
/// thread (the subject's executor, the test task, a gateway callback) writes to
/// it. `withLock` is the only access path; nothing escapes the critical section.
public final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    public init(_ value: Value) {
        self.value = value
    }

    public func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        try lock.withLock { try body(&value) }
    }

    public var current: Value { withLock { $0 } }

    public func set(_ newValue: Value) {
        withLock { $0 = newValue }
    }
}
