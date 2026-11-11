import TestSupport
import Testing

/// CONTRIBUTING.md tells a newcomer which commands to run and which documents to read. A command that was renamed or a document that was
/// moved leaves it promising something that is not there, and nothing else would notice: these tests hold it to the repository.
@Suite("Contributing guide")
struct ContributingGuideTests {
    private static func guide() throws -> String { try repositoryText("CONTRIBUTING.md") }

    @Test("every make target the guide names is a target of the Makefile")
    func targetsExist() throws {
        let missing = makeTargets(named: try Self.guide()).subtracting(try makefileTargets())

        #expect(missing.isEmpty, "not in the Makefile: \(missing.sorted())")
    }

    @Test("the guide names the commands a contributor runs: build, test, test-gpu, lint, format and check")
    func namesTheCommands() throws {
        #expect(makeTargets(named: try Self.guide()).isSuperset(of: ["build", "test", "test-gpu", "lint", "format", "check"]))
    }

    @Test("every repository path the guide names or links exists")
    func pathsExist() throws {
        let paths = repositoryPaths(in: try Self.guide())

        #expect(paths.count >= 10, "found only \(paths)")
        #expect(paths.filter { !repositoryHas($0) }.isEmpty, "missing: \(paths.filter { !repositoryHas($0) })")
    }

    @Test("the guide states the Git workflow: no commit to main, Conventional Commits, a closing keyword and the version bump")
    func statesTheWorkflow() throws {
        let text = try Self.guide()

        for phrase in ["Never commit to `main`", "Conventional Commit", "`Closes #", "`version.txt`"] {
            #expect(text.contains(phrase), "the guide lacks: \(phrase)")
        }
    }

    @Test("the guide leaves the product name to the three files that may spell it")
    func keepsTheProductNameOut() throws {
        let name = try productName()

        #expect(!(try Self.guide()).lowercased().contains(name.lowercased()))
    }
}
