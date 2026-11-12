import TestSupport
import Testing

@Suite("Markdown fences")
struct MarkdownFencesTests {
    @Test("a sh fence has language sh, no attributes, and text with a newline after each of its lines")
    func shFenceHasLanguageAndText() {
        let fences = MarkdownFences.all(in: ["```sh", "make build", "make test", "```"].joined(separator: "\n"))

        #expect(fences == [MarkdownFence(language: "sh", attributes: [:], text: "make build\nmake test\n", line: 1)])
    }

    @Test("a fence with no info string has an empty language")
    func noInfoStringHasNoLanguage() {
        #expect(MarkdownFences.all(in: ["```", "x", "```"].joined(separator: "\n")).map(\.language) == [""])
    }

    @Test("an empty fence has empty text")
    func emptyFenceHasEmptyText() {
        #expect(MarkdownFences.all(in: ["```sh", "```"].joined(separator: "\n")).map(\.text) == [""])
    }

    @Test("the words after the language are key=value attributes, a word without = has an empty value")
    func infoStringWordsAreAttributes() {
        let info = "```json file=a/b.json invalid=parameters[0].default flag"
        let fences = MarkdownFences.all(in: [info, "```"].joined(separator: "\n"))

        #expect(fences.map(\.language) == ["json"])
        #expect(fences.map(\.attributes) == [["file": "a/b.json", "invalid": "parameters[0].default", "flag": ""]])
    }

    @Test("a first word that holds = is an attribute, so the language is empty")
    func firstKeyValueWordIsNoLanguage() {
        let fences = MarkdownFences.all(in: ["```file=x", "```"].joined(separator: "\n"))

        #expect(fences.map(\.language) == [""])
        #expect(fences.map(\.attributes) == [["file": "x"]])
    }

    @Test("when a key appears twice, the later value wins")
    func laterKeyWins() {
        let fences = MarkdownFences.all(in: ["```sh key=1 key=2", "```"].joined(separator: "\n"))

        #expect(fences.map(\.attributes) == [["key": "2"]])
    }

    @Test("two fences come back in document order, and line is the 1-based number of the line each opens on")
    func fencesComeInOrderWithTheirLines() {
        let document = [
            "# Title", "", "```sh", "one", "```", "", "prose", "", "```json", "{}", "```",
        ].joined(separator: "\n")
        let fences = MarkdownFences.all(in: document)

        #expect(fences.map(\.line) == [3, 9])
        #expect(fences.map(\.language) == ["sh", "json"])
        #expect(fences.map(\.text) == ["one\n", "{}\n"])
    }

    @Test("a document with no fence has no fences")
    func noFenceNoFences() {
        #expect(MarkdownFences.all(in: "# Title\n\nprose\n").isEmpty)
    }

    @Test("a four-backtick fence keeps a three-backtick line as its text and closes only at four or more backticks")
    func longerFenceKeepsShorterFenceLines() {
        let document = ["````md", "```sh", "inside", "```", "````"].joined(separator: "\n")

        #expect(MarkdownFences.all(in: document) == [MarkdownFence(language: "md", attributes: [:], text: "```sh\ninside\n```\n", line: 1)])
    }

    @Test("a tilde fence keeps a backtick line as its text")
    func tildeFenceKeepsBacktickLines() {
        let document = ["~~~", "```", "x", "~~~"].joined(separator: "\n")

        #expect(MarkdownFences.all(in: document).map(\.text) == ["```\nx\n"])
    }

    @Test("a fence that is never closed runs to the end of the document, and the closed fence before it is still returned")
    func unclosedFenceRunsToTheEnd() {
        let document = ["```a", "1", "```", "text", "```b", "2", "3"].joined(separator: "\n")
        let fences = MarkdownFences.all(in: document)

        #expect(fences.map(\.language) == ["a", "b"])
        #expect(fences.map(\.text) == ["1\n", "2\n3\n"])
        #expect(fences.map(\.line) == [1, 5])
    }

    @Test("a fence indented by three spaces is a fence, and up to three leading spaces are removed from its lines")
    func threeSpaceIndentedFence() {
        let document = ["   ```sh", "   one", "      two", "   ```"].joined(separator: "\n")

        #expect(MarkdownFences.all(in: document).map(\.text) == ["one\n   two\n"])
    }

    @Test("a line indented by four spaces is not a fence")
    func fourSpaceIndentedLineIsNoFence() {
        let document = ["    ```sh", "    code", "    ```"].joined(separator: "\n")

        #expect(MarkdownFences.all(in: document).isEmpty)
    }

    @Test("a line that does not start with a backtick, and a line whose info string holds a backtick, do not open a fence")
    func notEveryBacktickLineOpens() {
        let document = ["Use ```sh to start", "```a`b", "x"].joined(separator: "\n")

        #expect(MarkdownFences.all(in: document).isEmpty)
    }

    @Test("a line with an info string does not close an open fence and becomes its text")
    func infoStringLineDoesNotClose() {
        let document = ["```sh", "```sh", "x", "```"].joined(separator: "\n")

        #expect(MarkdownFences.all(in: document).map(\.text) == ["```sh\nx\n"])
    }

    @Test("trailing spaces are allowed on the closing line")
    func trailingSpacesOnClosingLine() {
        let document = ["```", "x", "```   "].joined(separator: "\n")

        #expect(MarkdownFences.all(in: document).map(\.text) == ["x\n"])
    }

    @Test("a closing line with fewer backticks than the opening line does not close it")
    func fewerBackticksDoNotClose() {
        let document = ["````", "```", "x", "````"].joined(separator: "\n")

        #expect(MarkdownFences.all(in: document).map(\.text) == ["```\nx\n"])
    }

    @Test("a document with CRLF line endings reads the same as one with LF line endings")
    func crlfReadsAsLf() {
        let lf = "```sh\nmake build\n```\n"
        let crlf = "```sh\r\nmake build\r\n```\r\n"

        #expect(MarkdownFences.all(in: crlf) == MarkdownFences.all(in: lf))
        #expect(MarkdownFences.all(in: crlf).map(\.text) == ["make build\n"])
    }

    @Test("read of Package.swift finds the repository root from this suite and returns the manifest")
    func readFindsTheRoot() throws {
        let manifest = try MarkdownFences.read("Package.swift")

        #expect(manifest.contains("swift-tools-version"))
    }

    @Test("read of a path that is not there throws unreadable with that path")
    func readOfAMissingFileThrows() {
        #expect(throws: MarkdownFenceError.unreadable("no/such/file.md")) {
            try MarkdownFences.read("no/such/file.md")
        }
    }

    @Test("read from a source file with no Package.swift above it throws noRepositoryRoot with that file")
    func readWithoutARepositoryThrows() {
        #expect(throws: MarkdownFenceError.noRepositoryRoot("/nonexistent/dir/File.swift")) {
            try MarkdownFences.read("Package.swift", from: "/nonexistent/dir/File.swift")
        }
    }
}
