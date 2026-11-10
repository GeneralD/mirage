import Dependencies
import Domain
import Foundation
import TestDoubles
import Testing

@testable import SupportLogUseCase

private let supportEnvironment = HostEnvironmentInfo(
    appVersion: "1.2.3",
    buildNumber: "45",
    systemVersion: SystemVersion(major: 15, minor: 1, patch: 0)
)

private func supportSnapshot(entries: [SupportLogEntry] = [], logError: String? = nil) -> SupportLogSnapshot {
    SupportLogSnapshot(environment: supportEnvironment, entries: entries, logError: logError)
}

private func supportLine(_ message: String) -> SupportLogEntry {
    SupportLogEntry(timestamp: 0, category: "app", message: message)
}

private struct DiskFullError: LocalizedError {
    var errorDescription: String? { "disk full" }
}

private struct StubSupportLogUseCase: SupportLogUseCase {
    let outcome: SupportLogExportOutcome

    func export(_ context: SupportReportContext) async -> SupportLogExportOutcome {
        outcome
    }
}

@Suite("SupportLogUseCaseImpl", .timeLimit(.minutes(1)))
struct SupportLogUseCaseTests {
    private struct Harness {
        let repository: FakeSupportLogRepository
        let errors: RecordingLog
        let developer: RecordingLog
        let subject: SupportLogUseCaseImpl
    }

    private func makeHarness(
        _ snapshot: SupportLogSnapshot,
        savedPath: String = "/fake/support-log.txt",
        saveFailure: (any Error)? = nil
    ) -> Harness {
        let repository = FakeSupportLogRepository(snapshot: snapshot, savedPath: savedPath, saveFailure: saveFailure)
        let errors = RecordingLog()
        let developer = RecordingLog()
        let subject = withDependencies {
            $0.supportLogRepository = repository
            $0.errorLog = errors
            $0.developerLog = developer
        } operation: {
            SupportLogUseCaseImpl()
        }
        return Harness(repository: repository, errors: errors, developer: developer, subject: subject)
    }

    @Test("a report that saves returns saved with the path the repository gave, the snapshot's line count and its log error")
    func savedOutcome() async {
        let harness = makeHarness(supportSnapshot(entries: [supportLine("started"), supportLine("ready")]), savedPath: "/tmp/report.txt")
        let outcome = await harness.subject.export(SupportReportContext(install: .installed))
        #expect(outcome == .saved(path: "/tmp/report.txt", lineCount: 2, logError: nil))
    }

    @Test("the saved text starts with the product's support report line and carries the context's effect status and compiler message")
    func savedTextCarriesContext() async {
        let harness = makeHarness(supportSnapshot())
        _ = await harness.subject.export(
            SupportReportContext(install: .installed, effectStatus: "compile failed", compilerMessage: "error: unknown type")
        )
        #expect(harness.repository.saved.count == 1)
        let text = harness.repository.saved.last ?? ""
        #expect(text.hasPrefix("\(ProductIdentity.displayName) support report"))
        #expect(text.contains("Effect: compile failed"))
        #expect(text.contains("error: unknown type"))
    }

    @Test("a snapshot with a log error is still saved, and the saved outcome carries the same reason")
    func logErrorStillSaves() async {
        let harness = makeHarness(supportSnapshot(logError: "denied"))
        let outcome = await harness.subject.export(SupportReportContext(install: .notInstalled))
        #expect(harness.repository.saved.count == 1)
        #expect(outcome == .saved(path: "/fake/support-log.txt", lineCount: 0, logError: "denied"))
    }

    @Test("a save that throws returns failed with the error's description and logs one line to the error log")
    func saveFailureReturnsFailed() async {
        let harness = makeHarness(supportSnapshot(), saveFailure: DiskFullError())
        let outcome = await harness.subject.export(SupportReportContext(install: .installed))
        #expect(outcome == .failed(description: "disk full"))
        #expect(harness.repository.saved.count == 1)
        #expect(harness.errors.messages(in: .app).count == 1)
        #expect(harness.errors.contains("support log could not be saved"))
    }

    @Test("a successful save writes nothing to the error log")
    func successWritesNoErrorLine() async {
        let harness = makeHarness(supportSnapshot(entries: [supportLine("a")]))
        _ = await harness.subject.export(SupportReportContext(install: .installed))
        #expect(harness.errors.entries.count == 0)
    }

    @Test("a successful save records its line count in the developer log")
    func successRecordsDeveloperLine() async {
        let harness = makeHarness(supportSnapshot(entries: [supportLine("a"), supportLine("b")]))
        _ = await harness.subject.export(SupportReportContext(install: .installed))
        #expect(harness.developer.messages(in: .app) == ["support log saved: 2 lines"])
    }

    @Test("the supportLogUseCase dependency hands back the use case it was set to")
    func dependencyKeyHandsBackValue() async {
        let resolved = withDependencies {
            $0.supportLogUseCase = StubSupportLogUseCase(outcome: .failed(description: "stub"))
        } operation: {
            @Dependency(\.supportLogUseCase) var useCase
            return useCase
        }
        #expect(await resolved.export(SupportReportContext(install: .installed)) == .failed(description: "stub"))
    }
}
