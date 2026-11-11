import Domain
import Foundation

/// Live `ConsoleWriter`: writes each text as UTF-8 with one newline to the standard streams.
///
/// A write that fails (a pipe whose reader has closed, for one) is dropped without a report: a tool
/// whose standard streams are gone has no other channel left to report the failure on.
public struct StandardStreamsImpl: ConsoleWriter, Sendable {
    private let standardOutput: FileHandle
    private let standardError: FileHandle

    public init(standardOutput: FileHandle = .standardOutput, standardError: FileHandle = .standardError) {
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public func line(_ text: String) {
        write(text, to: standardOutput)
    }

    public func errorLine(_ text: String) {
        write(text, to: standardError)
    }

    private func write(_ text: String, to handle: FileHandle) {
        try? handle.write(contentsOf: Data((text + "\n").utf8))
    }
}
