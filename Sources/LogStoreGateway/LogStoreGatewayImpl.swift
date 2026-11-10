// The port: Sources/Domain/Gateway/LogStoreGateway.swift. OS API: OSLogStore, scoped to this process.
// Thin and coverage-ignored by rule: a log store cannot be read in CI, so there is no smoke.
// Which lines are kept, and in what order, is decided above, in the support log DataSource.
import Domain
import Foundation
import OSLog

public struct LogStoreGatewayImpl {
    public init() {}
}

extension LogStoreGatewayImpl: LogStoreGateway {
    public func entries(subsystem: String) throws -> [SupportLogEntry] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        return try store.getEntries(matching: NSPredicate(format: "subsystem == %@", subsystem))
            .compactMap { $0 as? OSLogEntryLog }
            .map { SupportLogEntry(timestamp: $0.date.timeIntervalSince1970, category: $0.category, message: $0.composedMessage) }
    }
}
