import Domain
import TestSupport

/// `LogStoreGateway` over a fixed list: `entries(subsystem:)` hands back what it was made with,
/// in the order it was given. `queries` records every subsystem asked for, in call order, and is
/// written before a `failure` is thrown, so a subject that asks is asserted to have asked even
/// when the store cannot be read.
public final class FakeLogStoreGateway: LogStoreGateway, Sendable {
    /// The subsystems `entries(subsystem:)` was called with, in call order.
    public let queries = Collector<String>()
    private let held: [SupportLogEntry]
    private let failure: (any Error)?

    public init(entries: [SupportLogEntry] = [], failure: (any Error)? = nil) {
        held = entries
        self.failure = failure
    }

    public func entries(subsystem: String) throws -> [SupportLogEntry] {
        queries.append(subsystem)
        if let failure { throw failure }
        return held
    }
}
