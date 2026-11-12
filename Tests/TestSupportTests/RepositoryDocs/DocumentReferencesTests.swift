import TestSupport
import Testing

@Suite("Document references")
struct DocumentReferencesTests {
    @Test("the Makefile's targets are the words before a colon, without .PHONY and without recipe lines")
    func makefileTargetsAreRules() throws {
        let targets = try makefileTargets()

        #expect(targets.isSuperset(of: ["build", "test", "test-gpu", "lint", "format", "check"]))
        #expect(!targets.contains(".PHONY"))
        #expect(!targets.contains("swift"))
    }

    @Test("a target named in backticks is found")
    func inlineTarget() {
        #expect(makeTargets(named: "Run `make test-gpu` before you push.") == ["test-gpu"])
    }

    @Test("a target at the start of a line of a code block is found, with its comment ignored")
    func blockTarget() {
        let text = """
            ```sh
            make build             # release build
            make lint
            ```
            """

        #expect(makeTargets(named: text) == ["build", "lint"])
    }

    @Test("prose that says make is not a target")
    func proseNamesNoTarget() {
        #expect(makeTargets(named: "Please make a small change, then make sure it builds.").isEmpty)
    }

    @Test("a path in backticks under a top-level directory, a top-level file, and a relative link are found in order")
    func pathsInOrder() {
        let text = "See `docs/ARCHITECTURE.md` and the [guide](Examples/Ripple.lens/manifest.json), then `README.md`."

        #expect(repositoryPaths(in: text) == ["docs/ARCHITECTURE.md", "README.md", "Examples/Ripple.lens/manifest.json"])
    }

    @Test("a pattern, a command, a word and an address are not paths")
    func notPaths() {
        let text = "`Sources/*/Impl.swift` `swift run dev-harness` `effect.metal` `/Applications` [site](https://example.com/a) [top](#top)"

        #expect(repositoryPaths(in: text).isEmpty)
    }

    @Test("the product name is the name: key of project.yml")
    func productNameIsRead() throws {
        let name = try productName()

        #expect(!name.isEmpty)
        #expect(try repositoryText("project.yml").contains("name: \(name)"))
    }
}
