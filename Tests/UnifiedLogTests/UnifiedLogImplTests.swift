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
