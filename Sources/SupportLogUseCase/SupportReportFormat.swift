import Domain
import Foundation

// The support report's wording, as a pure function of what the report is written from, so that the
// report reads the same wherever it is saved or sent. One fact to a line; the compiler's output and
// the log each follow a blank line.

/// The most `Character`s of the compiler's output the report keeps. A longer output is cut to this many
/// and ends in an ellipsis; one of exactly this many is kept whole.
private let compilerOutputLimit = 4000

/// The support report: the app and its environment, the Camera Extension and the selected effect, the
/// compiler's output when there is one, and the log lines in the order they were given. The text ends
/// in one line break.
func supportReportText(_ snapshot: SupportLogSnapshot, context: SupportReportContext, appName: String) -> String {
    let head = [
        "\(appName) support report",
        "App version: \(appVersionText(of: snapshot.environment))",
        "macOS: \(systemVersionText(of: snapshot.environment.systemVersion))",
        "Camera extension: \(installText(of: context.install))",
        "Effect: \(context.effectStatus ?? "no problem reported")",
    ]
    return (head + compilerSection(of: context.compilerMessage) + [""] + logSection(of: snapshot))
        .joined(separator: "\n") + "\n"
}

/// `1.2.3 (45)` when the bundle names a build, `1.2.3` when it does not, and `unknown` when it names no
/// version, whatever its build number.
private func appVersionText(of environment: HostEnvironmentInfo) -> String {
    switch (environment.appVersion, environment.buildNumber) {
    case (let version?, let build?): "\(version) (\(build))"
    case (let version?, nil): version
    case (nil, _): "unknown"
    }
}

private func systemVersionText(of version: SystemVersion) -> String {
    "\(version.major).\(version.minor).\(version.patch)"
}

/// The words for the Camera Extension's install status. A failure names its class, and an unclassified
/// one its code and description.
private func installText(of status: InstallStatus) -> String {
    switch status {
    case .notInstalled: "not installed"
    case .installing: "installing"
    case .needsApproval: "waiting for approval"
    case .installed: "installed"
    case .rebootRequired: "restart required"
    case .failed(.denied): "failed (denied)"
    case .failed(.canceled): "failed (canceled)"
    case .failed(.invalidBuild(code: let code)): "failed (invalid build, code \(code))"
    case .failed(.other(code: let code, description: let description)): "failed (code \(code): \(description))"
    }
}

/// The compiler's output as a section, with the whitespace around it dropped and the text cut at
/// `compilerOutputLimit`. No section when there is no output to show, whether it is missing or blank.
private func compilerSection(of message: String?) -> [String] {
    guard let output = message?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty else { return [] }
    let body = output.count > compilerOutputLimit ? String(output.prefix(compilerOutputLimit)) + "…" : output
    return ["", "Compiler output:", body]
}

/// The log's heading and lines. A log that could not be read says why and nothing else; an empty one says
/// `no lines`; otherwise each line follows the heading as `<time> [<category>] <message>`.
private func logSection(of snapshot: SupportLogSnapshot) -> [String] {
    if let logError = snapshot.logError {
        return ["Log: unavailable (\(logError))"]
    }
    guard !snapshot.entries.isEmpty else { return ["Log: no lines"] }
    let count = snapshot.entries.count
    return ["Log: \(count) \(count == 1 ? "line" : "lines"), oldest first"] + snapshot.entries.map(logLine(of:))
}

/// The time is the whole seconds of the UTC ISO 8601 form, such as `1970-01-01T00:00:00Z`.
private func logLine(of entry: SupportLogEntry) -> String {
    let time = Date(timeIntervalSince1970: entry.timestamp).formatted(.iso8601)
    return "\(time) [\(entry.category)] \(entry.message)"
}
