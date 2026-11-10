import Domain
import Testing

@testable import Presenters

@Suite("OnboardingLogText")
struct OnboardingLogTextTests {
    // The expectations are written out as literals, not read from the constants, so that changing a
    // word turns these red.

    @Test(
        "a saved report names its path and its line count in words, with a success tone",
        arguments: [
            (0, "Saved /tmp/report.txt with no log lines."),
            (1, "Saved /tmp/report.txt with 1 log line."),
            (3, "Saved /tmp/report.txt with 3 log lines."),
        ])
    func savedReportNamesLineCount(lineCount: Int, text: String) {
        #expect(
            supportLogNotice(of: .saved(path: "/tmp/report.txt", lineCount: lineCount, logError: nil))
                == OnboardingNotice(tone: .success, text: text))
    }

    @Test("a saved report whose system log could not be read is a warning that says why")
    func savedReportWithLogErrorIsWarning() {
        #expect(
            supportLogNotice(of: .saved(path: "/tmp/report.txt", lineCount: 3, logError: "denied"))
                == OnboardingNotice(tone: .warning, text: "Saved /tmp/report.txt, but the system log could not be read: denied"))
    }

    @Test("a report that could not be written is a failure that gives its description")
    func failedReportIsFailure() {
        #expect(
            supportLogNotice(of: .failed(description: "disk full"))
                == OnboardingNotice(tone: .failure, text: "Could not save the report: disk full"))
    }

    @Test("no message, or a blank one, has no excerpt")
    func blankMessageHasNoExcerpt() {
        #expect(compilerMessageExcerpt(of: nil) == nil)
        #expect(compilerMessageExcerpt(of: "") == nil)
        #expect(compilerMessageExcerpt(of: " ") == nil)
        #expect(compilerMessageExcerpt(of: " \n\t ") == nil)
    }

    @Test("the whitespace and newlines around a message are not part of its excerpt")
    func surroundingWhitespaceIsDropped() {
        #expect(compilerMessageExcerpt(of: "  \nerror: missing return\n\n") == "error: missing return")
    }

    @Test("a message of exactly 2000 scalars is shown whole, even with whitespace around it")
    func exactlyLimitIsNotCut() {
        let message = String(repeating: "a", count: 2000)
        #expect(compilerMessageExcerpt(of: " \n" + message + "\n ") == message)
    }

    @Test("a message of 2001 scalars is cut to its first 2000 scalars and an ellipsis")
    func oneOverLimitIsCut() {
        let excerpt = compilerMessageExcerpt(of: String(repeating: "a", count: 2001))
        #expect(excerpt == String(repeating: "a", count: 2000) + "…")
        #expect(excerpt?.unicodeScalars.count == 2001)
    }

    @Test("a run of combining marks is counted in scalars, so the cut keeps 1999 of them after the base letter")
    func combiningMarksCountAsScalars() {
        let excerpt = compilerMessageExcerpt(of: "e" + String(repeating: "\u{0301}", count: 2001))
        #expect(excerpt == "e" + String(repeating: "\u{0301}", count: 1999) + "…")
        #expect(excerpt?.unicodeScalars.count == 2001)
    }
}
