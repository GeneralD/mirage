import Domain
import TestSupport

/// Records every text the subject writes to the two streams, in call order: `lines` for `line` calls and
/// `errorLines` for `errorLine` calls. A test checks that a result reached standard output and a failure
/// reached standard error, and that the two never mix.
public final class RecordingConsole: ConsoleWriter, Sendable {
    public let lines = Collector<String>()
    public let errorLines = Collector<String>()

    public init() {}

    public func line(_ text: String) {
        lines.append(text)
    }

    public func errorLine(_ text: String) {
        errorLines.append(text)
    }
}
