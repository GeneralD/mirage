import Domain
import Testing

@testable import SupportLogUseCase

private let host = HostEnvironmentInfo(
    appVersion: "1.2.3",
    buildNumber: "45",
    systemVersion: SystemVersion(major: 15, minor: 1, patch: 0)
)

private func makeSnapshot(
    environment: HostEnvironmentInfo = host,
    entries: [SupportLogEntry] = [],
    logError: String? = nil
) -> SupportLogSnapshot {
    SupportLogSnapshot(environment: environment, entries: entries, logError: logError)
}

private func entry(_ timestamp: Double, _ category: String, _ message: String) -> SupportLogEntry {
    SupportLogEntry(timestamp: timestamp, category: category, message: message)
}

/// The report over the given state, with the app named `Example`. Its defaults are a report with no
/// compiler output and no log lines, the Camera Extension installed and no effect status.
private func reportText(
    _ snapshot: SupportLogSnapshot = makeSnapshot(),
    install: InstallStatus = .installed,
    effect: String? = nil,
    compiler: String? = nil
) -> String {
    supportReportText(
        snapshot,
        context: SupportReportContext(install: install, effectStatus: effect, compilerMessage: compiler),
        appName: "Example")
}

/// The first line of `text` that starts with `prefix`, or `nil` when no line does.
private func line(starting prefix: String, in text: String) -> String? {
    text.split(separator: "\n").map(String.init).first { $0.hasPrefix(prefix) }
}

struct InstallRow: Sendable, CustomTestStringConvertible {
    let label: String
    let status: InstallStatus
    let words: String
    var testDescription: String { label }

    static let all: [InstallRow] = [
        InstallRow(label: "notInstalled", status: .notInstalled, words: "not installed"),
        InstallRow(label: "installing", status: .installing, words: "installing"),
        InstallRow(label: "needsApproval", status: .needsApproval, words: "waiting for approval"),
        InstallRow(label: "installed", status: .installed, words: "installed"),
        InstallRow(label: "rebootRequired", status: .rebootRequired, words: "restart required"),
        InstallRow(label: "failed(denied)", status: .failed(.denied), words: "failed (denied)"),
        InstallRow(label: "failed(canceled)", status: .failed(.canceled), words: "failed (canceled)"),
        InstallRow(label: "failed(invalidBuild)", status: .failed(.invalidBuild(code: 4)), words: "failed (invalid build, code 4)"),
        InstallRow(label: "failed(other)", status: .failed(.other(code: 9, description: "boom")), words: "failed (code 9: boom)"),
    ]
}

struct VersionRow: Sendable, CustomTestStringConvertible {
    let label: String
    let appVersion: String?
    let buildNumber: String?
    let shown: String
    var testDescription: String { label }

    static let all: [VersionRow] = [
        VersionRow(label: "version and build", appVersion: "1.2.3", buildNumber: "45", shown: "1.2.3 (45)"),
        VersionRow(label: "version without build", appVersion: "1.2.3", buildNumber: nil, shown: "1.2.3"),
        VersionRow(label: "build without version", appVersion: nil, buildNumber: "45", shown: "unknown"),
        VersionRow(label: "neither version nor build", appVersion: nil, buildNumber: nil, shown: "unknown"),
    ]
}

struct CompilerRow: Sendable, CustomTestStringConvertible {
    let label: String
    let message: String?
    var testDescription: String { label }

    static let blank: [CompilerRow] = [
        CompilerRow(label: "missing", message: nil),
        CompilerRow(label: "empty", message: ""),
        CompilerRow(label: "whitespace only", message: " \n\t "),
    ]
}

@Suite("supportReportText")
struct SupportReportFormatTests {
    @Test("a report with a compiler output and two log lines is the whole text the layout asks for")
    func wholeReportWithCompilerOutputAndLines() {
        let snapshot = makeSnapshot(entries: [
            entry(0, "install", "extension install status: needsApproval"),
            entry(31_539_661, "effect", "Ripple: compile failed"),
        ])
        let expected = """
            Example support report
            App version: 1.2.3 (45)
            macOS: 15.1.0
            Camera extension: waiting for approval
            Effect: Ripple: compile failed

            Compiler output:
            error: expected ';'

            Log: 2 lines, oldest first
            1970-01-01T00:00:00Z [install] extension install status: needsApproval
            1971-01-01T01:01:01Z [effect] Ripple: compile failed

            """

        let text = reportText(snapshot, install: .needsApproval, effect: "Ripple: compile failed", compiler: "error: expected ';'")

        #expect(text == expected)
    }

    @Test("a report without a compiler output and with no log lines ends with `Log: no lines` and one line break")
    func wholeReportWithNoLines() {
        let expected = """
            Example support report
            App version: 1.2.3 (45)
            macOS: 15.1.0
            Camera extension: installed
            Effect: no problem reported

            Log: no lines

            """

        #expect(reportText() == expected)
    }

    @Test("a log that could not be read says why in one line and shows none of its entries")
    func unreadableLogShowsOnlyTheReason() {
        let snapshot = makeSnapshot(entries: [entry(0, "app", "started")], logError: "denied")
        let expected = """
            Example support report
            App version: 1.2.3 (45)
            macOS: 15.1.0
            Camera extension: installed
            Effect: no problem reported

            Log: unavailable (denied)

            """

        let text = reportText(snapshot)

        #expect(text == expected)
        #expect(!text.contains("[app]"))
    }

    @Test("a log of one line is headed `1 line`, not `1 lines`")
    func oneLineHeading() {
        let text = reportText(makeSnapshot(entries: [entry(0, "app", "started")]))

        #expect(text.hasSuffix("\n\nLog: 1 line, oldest first\n1970-01-01T00:00:00Z [app] started\n"))
    }

    @Test("log lines keep the order they were given in, whatever their timestamps")
    func logLinesKeepTheGivenOrder() {
        let snapshot = makeSnapshot(entries: [entry(30, "app", "30"), entry(10, "app", "10"), entry(20, "app", "20")])

        let text = reportText(snapshot)

        #expect(
            text.split(separator: "\n").suffix(3).map(String.init) == [
                "1970-01-01T00:00:30Z [app] 30",
                "1970-01-01T00:00:10Z [app] 10",
                "1970-01-01T00:00:20Z [app] 20",
            ])
    }

    @Test("a log line is its time as UTC ISO 8601 to the whole second, its category in brackets and its message")
    func logLineFormat() {
        let text = reportText(makeSnapshot(entries: [entry(31_539_661, "effect", "Ripple: compile failed")]))

        #expect(text.hasSuffix("\n\nLog: 1 line, oldest first\n1971-01-01T01:01:01Z [effect] Ripple: compile failed\n"))
    }

    @Test("the first line is the app name as given, followed by `support report`")
    func firstLineNamesTheApp() {
        let text = supportReportText(makeSnapshot(), context: SupportReportContext(install: .installed), appName: "Sample")

        #expect(text.split(separator: "\n").first.map(String.init) == "Sample support report")
    }

    @Test("the App version line is the version and build, the version alone, or unknown", arguments: VersionRow.all)
    func appVersionLine(_ row: VersionRow) {
        let info = HostEnvironmentInfo(
            appVersion: row.appVersion,
            buildNumber: row.buildNumber,
            systemVersion: SystemVersion(major: 15, minor: 1, patch: 0))

        #expect(line(starting: "App version:", in: reportText(makeSnapshot(environment: info))) == "App version: \(row.shown)")
    }

    @Test("the macOS line is the three numbers of the system version")
    func macOSLine() {
        #expect(line(starting: "macOS:", in: reportText()) == "macOS: 15.1.0")
    }

    @Test("the Camera extension line says each install status in words", arguments: InstallRow.all)
    func cameraExtensionLine(_ row: InstallRow) {
        #expect(line(starting: "Camera extension:", in: reportText(install: row.status)) == "Camera extension: \(row.words)")
    }

    @Test("the Effect line is the effect status as given")
    func effectLineIsTheStatusAsGiven() {
        #expect(line(starting: "Effect:", in: reportText(effect: "Ripple: compile failed")) == "Effect: Ripple: compile failed")
    }

    @Test("the Effect line says no problem was reported when there is no effect status")
    func effectLineWithoutStatus() {
        #expect(line(starting: "Effect:", in: reportText()) == "Effect: no problem reported")
    }

    @Test("a compiler output that is missing or blank gives the same report as none", arguments: CompilerRow.blank)
    func blankCompilerOutputGivesNoSection(_ row: CompilerRow) {
        let text = reportText(compiler: row.message)

        #expect(text == reportText())
        #expect(!text.contains("Compiler output:"))
    }

    @Test("a compiler output is shown after a blank line, with the whitespace around it dropped")
    func compilerOutputIsTrimmed() {
        let text = reportText(compiler: "\n  error: expected ';'  \n")

        #expect(text == reportText(compiler: "error: expected ';'"))
        #expect(text.contains("\n\nCompiler output:\nerror: expected ';'\n\nLog: no lines\n"))
    }

    @Test("a compiler output of exactly 4000 characters is kept whole, even with whitespace around it")
    func compilerOutputAtTheLimitIsKept() {
        let limit = String(repeating: "a", count: 4000)

        #expect(reportText(compiler: "  " + limit + "\n") == reportText(compiler: limit))
        #expect(reportText(compiler: limit).contains("Compiler output:\n" + limit + "\n\nLog: no lines\n"))
    }

    @Test("a compiler output longer than 4000 characters is cut to 4000 and ends in an ellipsis")
    func compilerOutputOverTheLimitIsCut() {
        let limit = String(repeating: "a", count: 4000)

        let text = reportText(compiler: limit + "a")

        #expect(text.contains("Compiler output:\n" + limit + "…\n\nLog: no lines\n"))
        #expect(!text.contains(limit + "a"))
    }

    @Test("the compiler output limit counts characters, not Unicode scalars")
    func compilerOutputLimitCountsCharacters() {
        let accented = String(repeating: "e\u{301}", count: 4000)

        #expect(reportText(compiler: accented).contains("Compiler output:\n" + accented + "\n\nLog: no lines\n"))
        #expect(reportText(compiler: accented + "e\u{301}").contains("Compiler output:\n" + accented + "…\n\nLog: no lines\n"))
    }

    @Test("a log that could not be read is reported even when entries are present, as its reason alone")
    func unavailableLogIgnoresEntries() {
        let snapshot = makeSnapshot(entries: [entry(0, "install", "started")], logError: "permission denied")

        #expect(reportText(snapshot).hasSuffix("\n\nLog: unavailable (permission denied)\n"))
    }
}

@Suite("SupportReportContext and SupportLogExportOutcome")
struct SupportReportTypesTests {
    @Test("a SupportReportContext's effect status and compiler message are nil unless given")
    func contextDefaultsAreNil() {
        let context = SupportReportContext(install: .installed)

        #expect(context.install == .installed)
        #expect(context.effectStatus == nil)
        #expect(context.compilerMessage == nil)
    }

    @Test("a SupportLogExportOutcome saved keeps its path, line count and log error")
    func savedKeepsItsPayload() {
        let outcome = SupportLogExportOutcome.saved(path: "/tmp/report.txt", lineCount: 3, logError: "denied")

        #expect(outcome == .saved(path: "/tmp/report.txt", lineCount: 3, logError: "denied"))
        #expect(outcome != .saved(path: "/tmp/report.txt", lineCount: 3, logError: nil))
        #expect(outcome != .saved(path: "/tmp/other.txt", lineCount: 3, logError: "denied"))
    }

    @Test("a SupportLogExportOutcome failed keeps its description")
    func failedKeepsItsPayload() {
        #expect(SupportLogExportOutcome.failed(description: "disk full") == .failed(description: "disk full"))
        #expect(SupportLogExportOutcome.failed(description: "disk full") != .failed(description: "read only"))
    }
}
