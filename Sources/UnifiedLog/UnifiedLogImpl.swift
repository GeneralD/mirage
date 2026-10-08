import Domain
import os

/// Live `ErrorLog` / `DeveloperLog` over the unified logging system.
///
/// Both ports share one method shape, so one type serves both and the `level`
/// picked at construction decides where a line lands: `.error` for operational
/// failures that must survive in the log store, `.debug` for developer tracing
/// the OS discards unless a debugger or `log config` asks for it. One
/// `os.Logger` per `LogSubsystem` is built once, so `log stream --predicate
/// 'category == "transport"'` filters a single slice of the product.
public struct UnifiedLogImpl: ErrorLog, DeveloperLog {
    public enum Level: Sendable, CaseIterable {
        case error
        case debug
    }

    let level: Level
    let loggers: [LogSubsystem: Logger]

    public init(level: Level) {
        self.level = level
        loggers = Dictionary(
            uniqueKeysWithValues: LogSubsystem.allCases.map {
                ($0, Logger(subsystem: ProductIdentity.logSubsystem, category: $0.rawValue))
            }
        )
    }

    public func record(_ subsystem: LogSubsystem, _ message: String) {
        let logger = loggers[subsystem, default: Logger(subsystem: ProductIdentity.logSubsystem, category: subsystem.rawValue)]
        switch level {
        case .error: logger.error("\(message, privacy: .public)")
        case .debug: logger.debug("\(message, privacy: .public)")
        }
    }
}
