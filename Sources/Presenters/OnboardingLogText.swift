import Domain
import Foundation

// The words of the support-log notice and of the compiler message on the onboarding window (#222), as
// pure functions, so that the Presenter only moves them into its published values. The wording is
// English, like `OnboardingText`.

/// What the window says once the support log has been saved, or could not be.
func supportLogNotice(of outcome: SupportLogExportOutcome) -> OnboardingNotice {
    switch outcome {
    case .saved(let path, let lineCount, nil):
        OnboardingNotice(tone: .success, text: "Saved \(path) with \(lineCountText(of: lineCount)).")
    case .saved(let path, _, let logError?):
        OnboardingNotice(tone: .warning, text: "Saved \(path), but the system log could not be read: \(logError)")
    case .failed(let description):
        OnboardingNotice(tone: .failure, text: "Could not save the report: \(description)")
    }
}

/// How many log lines a saved report holds, in words.
private func lineCountText(of lineCount: Int) -> String {
    switch lineCount {
    case 0: "no log lines"
    case 1: "1 log line"
    default: "\(lineCount) log lines"
    }
}

/// The most Unicode scalars of a compiler message that the window shows.
private let compilerMessageLimit = 2000

/// The compiler's message for the window: without the whitespace and newlines around it, and cut to its
/// first `compilerMessageLimit` Unicode scalars with an ellipsis when it is longer. `nil` when there is no
/// message or it is blank. The count is in scalars and not in `Character`s, as `helpDescription` counts,
/// so a run of combining marks cannot make the message longer than the limit.
func compilerMessageExcerpt(of message: String?) -> String? {
    guard let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
    let scalars = trimmed.unicodeScalars
    guard scalars.count > compilerMessageLimit else { return trimmed }
    return String(String.UnicodeScalarView(scalars.prefix(compilerMessageLimit))) + "…"
}
