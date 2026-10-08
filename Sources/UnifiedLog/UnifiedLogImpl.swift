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
        loggers = Dictionary(uniqueKeysWithValues: LogSubsystem.allCases.map { ($0, Self.logger(for: $0)) })
    }

    /// The category a subsystem's lines are filed under. `os.Logger` does not
    /// expose its category, so this is the testable half of the mapping.
    static func category(for subsystem: LogSubsystem) -> String { subsystem.rawValue }

    private static func logger(for subsystem: LogSubsystem) -> Logger {
        Logger(subsystem: ProductIdentity.logSubsystem, category: category(for: subsystem))
    }

    /// `init` builds a logger for every `LogSubsystem` case, so the lookup
    /// cannot miss; optional chaining only avoids a force unwrap.
    public func record(_ subsystem: LogSubsystem, _ message: String) {
        switch level {
        case .error: loggers[subsystem]?.error("\(message, privacy: .public)")
        case .debug: loggers[subsystem]?.debug("\(message, privacy: .public)")
        }
    }
}
