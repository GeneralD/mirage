import Dependencies
import Domain
import Foundation
import SupportLogDataSource
import TestDoubles
import TestSupport
import Testing

private let diagnostics = "/Users/test/Library/Application Support/host/Diagnostics"
private let reportPath = "/Users/test/Library/Application Support/host/Diagnostics/support-log.txt"

private func line(_ timestamp: Double, _ message: String) -> SupportLogEntry {
    SupportLogEntry(timestamp: timestamp, category: "app", message: message)
}

/// `count` lines with the timestamps 0..<count, read in a scrambled order. `index * 7` is a permutation of
/// 0..<count when `count` shares no factor with 7, so the newest lines are not the last ones read.
private func scrambled(_ count: Int) -> [SupportLogEntry] {
    (0..<count).map { index in
        let stamp = (index * 7) % count
        return line(Double(stamp), "line \(stamp)")
    }
}

/// The subject over fakes: the log store holds what the test gives it, the file system is in memory, and
/// the workspace and the developer log record what the subject did. Built inside `withDependencies`, so the
/// subject resolves these and not the unimplemented defaults.
private struct Rig {
    let store: FakeLogStoreGateway
    let files: InMemoryFileSystemGateway
    let workspace: FakeWorkspaceGateway
    let developer: RecordingLog
    let subject: SupportLogDataSourceImpl

    init(store: FakeLogStoreGateway = FakeLogStoreGateway(), files: InMemoryFileSystemGateway = InMemoryFileSystemGateway()) {
        let workspace = FakeWorkspaceGateway()
        let developer = RecordingLog()
        self.store = store
        self.files = files
        self.workspace = workspace
        self.developer = developer
        subject = withDependencies {
            $0.logStoreGateway = store
            $0.fileSystemGateway = files
            $0.workspaceGateway = workspace
            $0.appDirectories = FixedAppDirectories(effectsDirectory: "/effects", diagnosticsDirectory: diagnostics)
            $0.developerLog = developer
        } operation: {
            SupportLogDataSourceImpl()
        }
    }
}

@Suite("SupportLogDataSourceImpl", .timeLimit(.minutes(1)))
struct SupportLogDataSourceTests {
    @Test("entries come back in time order, whatever order the store read them in")
    func entriesAreSortedByTime() throws {
        let rig = Rig(store: FakeLogStoreGateway(entries: [line(30, "30"), line(10, "10"), line(20, "20")]))
        let entries = try rig.subject.entries()
        #expect(entries.map(\.message) == ["10", "20", "30"])
    }

    @Test("lines with the same timestamp keep the order they were read in")
    func sameTimestampKeepsReadOrder() throws {
        let rig = Rig(
            store: FakeLogStoreGateway(entries: [
                line(20, "20 first"), line(10, "10"), line(20, "20 second"), line(5, "5"), line(20, "20 third"), line(30, "30"),
            ]))
        let entries = try rig.subject.entries()
        #expect(entries.map(\.message) == ["5", "10", "20 first", "20 second", "20 third", "30"])
    }

    @Test("501 lines answer the newest 500 only, oldest first; the oldest line is the one dropped")
    func capsAtTheNewestFiveHundred() throws {
        let rig = Rig(store: FakeLogStoreGateway(entries: scrambled(501)))
        let entries = try rig.subject.entries()
        #expect(entries.map(\.message) == (1...500).map { "line \($0)" })
    }

    @Test("exactly 500 lines are all answered, oldest first")
    func fiveHundredLinesAreAllAnswered() throws {
        let rig = Rig(store: FakeLogStoreGateway(entries: scrambled(500)))
        let entries = try rig.subject.entries()
        #expect(entries.map(\.message) == (0..<500).map { "line \($0)" })
    }

    @Test("zero lines answer an empty array")
    func noLinesAnswerEmpty() throws {
        let rig = Rig()
        let entries = try rig.subject.entries()
        #expect(entries.isEmpty)
    }

    @Test("the log store is asked for this process's subsystem")
    func asksForTheProductSubsystem() throws {
        let rig = Rig()
        _ = try rig.subject.entries()
        #expect(rig.store.queries.values == [ProductIdentity.logSubsystem])
    }

    @Test("when the log store throws, entries throws the same error")
    func entriesRethrowsTheStoreError() {
        let rig = Rig(store: FakeLogStoreGateway(failure: CocoaError(.fileReadUnknown)))
        let error = #expect(throws: CocoaError.self) { try rig.subject.entries() }
        #expect(error?.code == .fileReadUnknown)
    }

    @Test("save writes support-log.txt in the diagnostics folder, returns its path and reads back the same text")
    func saveWritesTheReportFile() throws {
        let rig = Rig()
        let path = try rig.subject.save("report text")
        #expect(path == reportPath)
        #expect(rig.files.writtenPaths.values == [reportPath])
        #expect(try rig.files.readString(reportPath) == "report text")
    }

    @Test("save creates the diagnostics folder once before it writes")
    func saveCreatesTheDiagnosticsFolderOnce() throws {
        let rig = Rig()
        _ = try rig.subject.save("report text")
        #expect(rig.files.createdDirectories.values == [diagnostics])
    }

    @Test("a second save replaces the text of the same file")
    func secondSaveReplacesTheText() throws {
        let rig = Rig()
        _ = try rig.subject.save("first")
        let path = try rig.subject.save("second")
        #expect(path == reportPath)
        #expect(try rig.files.readString(reportPath) == "second")
    }

    @Test("a successful save opens the diagnostics folder once")
    func successfulSaveOpensTheFolderOnce() throws {
        let rig = Rig()
        _ = try rig.subject.save("report text")
        #expect(rig.workspace.opened.values == [diagnostics])
    }

    @Test("a successful save logs one developer line")
    func successfulSaveLogsOnce() throws {
        let rig = Rig()
        _ = try rig.subject.save("report text")
        #expect(rig.developer.messages(in: .app) == ["support log saved"])
    }

    @Test("a diagnostics folder that cannot be made makes save throw the same error and keeps Finder closed")
    func unmakableFolderThrowsAndDoesNotOpen() {
        let files = InMemoryFileSystemGateway()
        files.failCreateDirectory(of: diagnostics, with: CocoaError(.fileWriteNoPermission))
        let rig = Rig(files: files)
        let error = #expect(throws: CocoaError.self) { try rig.subject.save("report text") }
        #expect(error?.code == .fileWriteNoPermission)
        #expect(rig.files.writtenPaths.values.isEmpty)
        #expect(rig.workspace.opened.values.isEmpty)
        #expect(rig.developer.messages(in: .app).isEmpty)
    }

    @Test("a report file that cannot be written makes save throw the same error and keeps Finder closed")
    func unwritableFileThrowsAndDoesNotOpen() {
        let files = InMemoryFileSystemGateway()
        files.failWriteString(of: reportPath, with: CocoaError(.fileWriteOutOfSpace))
        let rig = Rig(files: files)
        let error = #expect(throws: CocoaError.self) { try rig.subject.save("report text") }
        #expect(error?.code == .fileWriteOutOfSpace)
        #expect(rig.workspace.opened.values.isEmpty)
        #expect(rig.developer.messages(in: .app).isEmpty)
    }
}
