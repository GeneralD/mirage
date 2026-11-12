import TestDoubles
import Testing

@Suite("RecordingConsole records each stream apart")
struct RecordingConsoleTests {
    @Test("lines and errorLines record their calls in call order and never mix")
    func linesAndErrorLinesRecordInCallOrderApart() {
        let console = RecordingConsole()
        console.line("a")
        console.errorLine("e1")
        console.line("b")
        console.errorLine("e2")
        #expect(console.lines.values == ["a", "b"])
        #expect(console.errorLines.values == ["e1", "e2"])
    }

    @Test("an empty text is recorded like any other text")
    func emptyTextIsRecorded() {
        let console = RecordingConsole()
        console.line("")
        console.errorLine("")
        #expect(console.lines.values == [""])
        #expect(console.errorLines.values == [""])
    }
}
