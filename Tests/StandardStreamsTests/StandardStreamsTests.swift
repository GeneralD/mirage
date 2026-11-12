import Domain
import Foundation
import StandardStreams
import Testing

@Suite("StandardStreamsImpl writes to the standard streams")
struct StandardStreamsTests {
    /// Runs `body` against a console whose two streams are pipes, then returns what reached each stream.
    /// The write ends are closed before the read, so `readToEnd()` returns at end of file without waiting.
    private func capture(_ body: (any ConsoleWriter) -> Void) throws -> (output: String, error: String) {
        let output = Pipe()
        let error = Pipe()
        let console = StandardStreamsImpl(
            standardOutput: output.fileHandleForWriting,
            standardError: error.fileHandleForWriting
        )
        body(console)
        try output.fileHandleForWriting.close()
        try error.fileHandleForWriting.close()
        let outputText = String(decoding: try output.fileHandleForReading.readToEnd() ?? Data(), as: UTF8.self)
        let errorText = String(decoding: try error.fileHandleForReading.readToEnd() ?? Data(), as: UTF8.self)
        return (outputText, errorText)
    }

    @Test("line writes each text and one newline to standard output, and nothing to standard error")
    func lineWritesToStandardOutput() throws {
        let streams = try capture { console in
            console.line("a")
            console.line("b")
        }
        #expect(streams.output == "a\nb\n")
        #expect(streams.error == "")
    }

    @Test("errorLine writes the text and one newline to standard error, and nothing to standard output")
    func errorLineWritesToStandardError() throws {
        let streams = try capture { console in
            console.errorLine("e")
        }
        #expect(streams.error == "e\n")
        #expect(streams.output == "")
    }

    @Test("an empty line writes only the newline")
    func emptyLineWritesOnlyNewline() throws {
        let streams = try capture { console in
            console.line("")
        }
        #expect(streams.output == "\n")
    }

    @Test("a Japanese line is written as UTF-8 with one newline")
    func japaneseLineIsWrittenAsUTF8() throws {
        let streams = try capture { console in
            console.line("検証 OK")
        }
        #expect(streams.output == "検証 OK\n")
    }

    @Test("a line that holds a newline keeps it and gains one final newline")
    func embeddedNewlineIsKeptAndOneFinalNewlineAdded() throws {
        let streams = try capture { console in
            console.line("a\nb")
        }
        #expect(streams.output == "a\nb\n")
    }
}
