import Dependencies
import Domain
import Foundation
import TestDoubles
import Testing

@testable import SupportLogRepository

private let host = HostEnvironmentInfo(
    appVersion: "2.3.4",
    buildNumber: "99",
    systemVersion: SystemVersion(major: 15, minor: 1, patch: 0)
)

private func line(_ timestamp: Double, _ message: String) -> SupportLogEntry {
    SupportLogEntry(timestamp: timestamp, category: "app", message: message)
}

/// The subject over fakes: the support logs and the host environment are the ones the test gives, so the
/// subject resolves these and not the unimplemented defaults. Built inside `withDependencies`, as the
/// Repository resolves its dependencies when it is made.
private func makeSubject(logs: FakeSupportLogs, environment: HostEnvironmentInfo = host) -> SupportLogRepositoryImpl {
    withDependencies {
        $0.supportLogs = logs
        $0.hostEnvironment = FixedHostEnvironment(info: environment)
    } operation: {
        SupportLogRepositoryImpl()
    }
}

@Suite("SupportLogRepositoryImpl", .timeLimit(.minutes(1)))
struct SupportLogRepositoryTests {
    @Test("a SupportLogSnapshot keeps the environment, entries and logError it was made with")
    func snapshotKeepsItsFields() {
        let snapshot = SupportLogSnapshot(environment: host, entries: [line(1, "started")], logError: "denied")
        #expect(snapshot.environment == host)
        #expect(snapshot.entries == [line(1, "started")])
        #expect(snapshot.logError == "denied")
    }

    @Test("snapshot's environment is the hostEnvironment's info itself")
    func environmentIsTheHostInfo() {
        let subject = makeSubject(logs: FakeSupportLogs(), environment: host)
        #expect(subject.snapshot().environment == host)
    }

    @Test("snapshot's entries keep the order the DataSource gave them, and logError is nil")
    func entriesKeepTheDataSourceOrder() {
        let given = [line(30, "30"), line(10, "10"), line(20, "20")]
        let subject = makeSubject(logs: FakeSupportLogs(entries: given))
        let snapshot = subject.snapshot()
        #expect(snapshot.entries == given)
        #expect(snapshot.logError == nil)
    }

    @Test("snapshot does not throw when the log cannot be read: entries are empty and logError says why")
    func unreadableLogDoesNotThrow() {
        let failure = CocoaError(.fileReadNoPermission)
        let subject = makeSubject(logs: FakeSupportLogs(entriesFailure: failure))
        let snapshot = subject.snapshot()
        #expect(snapshot.entries.isEmpty)
        #expect(snapshot.logError == failure.localizedDescription)
        #expect(snapshot.environment == host)
    }

    @Test("save hands the report to SupportLogs and returns the path SupportLogs returned")
    func saveReturnsTheSavedPath() throws {
        let logs = FakeSupportLogs(savedPath: "/Users/test/Library/Application Support/host/Diagnostics/support-log.txt")
        let subject = makeSubject(logs: logs)
        let path = try subject.save("report body")
        #expect(path == "/Users/test/Library/Application Support/host/Diagnostics/support-log.txt")
        #expect(logs.saved.values == ["report body"])
    }

    @Test("a save failure from SupportLogs is thrown unchanged")
    func saveFailureIsRethrown() {
        let logs = FakeSupportLogs(saveFailure: CocoaError(.fileWriteNoPermission))
        let subject = makeSubject(logs: logs)
        #expect(performing: { try subject.save("report body") }, throws: { ($0 as? CocoaError)?.code == .fileWriteNoPermission })
    }
}
