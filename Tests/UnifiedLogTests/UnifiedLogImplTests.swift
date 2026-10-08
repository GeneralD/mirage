import Domain
import Testing

@testable import UnifiedLog

@Suite("UnifiedLogImpl")
struct UnifiedLogImplTests {
    @Test("every log subsystem has a logger", arguments: UnifiedLogImpl.Level.allCases)
    func categoryMappingCoversAllSubsystems(level: UnifiedLogImpl.Level) {
        let log = UnifiedLogImpl(level: level)
        #expect(Set(log.loggers.keys) == Set(LogSubsystem.allCases))
    }

    @Test("each subsystem is filed under its own raw-value category", arguments: LogSubsystem.allCases)
    func categoryIsTheRawValue(subsystem: LogSubsystem) {
        #expect(UnifiedLogImpl.category(for: subsystem) == subsystem.rawValue)
    }

    @Test("categories are distinct so a filter selects one slice")
    func categoriesAreDistinct() {
        let categories = LogSubsystem.allCases.map(UnifiedLogImpl.category(for:))
        #expect(Set(categories).count == categories.count)
    }

    // The severity is fixed by the `switch` over the closed `Level` enum; the OS
    // log store cannot be redirected in a unit test, so it is not asserted here.
    @Test("recording to every subsystem at every level does not crash", arguments: UnifiedLogImpl.Level.allCases)
    func recordingEverySubsystem(level: UnifiedLogImpl.Level) {
        let log = UnifiedLogImpl(level: level)
        for subsystem in LogSubsystem.allCases {
            log.record(subsystem, "unit test line for \(subsystem.rawValue)")
        }
    }

    @Test("the same instance serves both ports")
    func servesBothPorts() {
        let log = UnifiedLogImpl(level: .error)
        let asError: any ErrorLog = log
        let asDeveloper: any DeveloperLog = log
        asError.record(.app, "error port")
        asDeveloper.record(.app, "developer port")
    }
}
