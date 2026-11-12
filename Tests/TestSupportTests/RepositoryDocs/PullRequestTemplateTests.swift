import TestSupport
import Testing

/// The pull request template is the Git workflow of `.claude/CLAUDE.md` as a checklist. These tests keep its commands and paths real and
/// its rules from being edited out.
@Suite("Pull request template")
struct PullRequestTemplateTests {
    private static func template() throws -> String { try repositoryText(".github/pull_request_template.md") }

    @Test("the template asks for the issue the pull request completes, with a closing keyword")
    func asksForTheIssue() throws {
        #expect(try Self.template().contains("Closes #"))
    }

    @Test("every make target the template names is a target of the Makefile, and format, lint, check and test are among them")
    func targetsExist() throws {
        let named = makeTargets(named: try Self.template())
        let missing = named.subtracting(try makefileTargets())

        #expect(named.isSuperset(of: ["format", "lint", "check", "test"]))
        #expect(missing.isEmpty, "not in the Makefile: \(missing.sorted())")
    }

    @Test("the template carries the Conventional Commit rule and the version bump")
    func carriesTheRules() throws {
        let text = try Self.template()

        for phrase in ["Conventional Commit", "`version.txt`", "screenshot"] {
            #expect(text.contains(phrase), "the template lacks: \(phrase)")
        }
    }

    @Test("every repository path the template names exists")
    func pathsExist() throws {
        let paths = repositoryPaths(in: try Self.template())

        #expect(!paths.isEmpty)
        #expect(paths.filter { !repositoryHas($0) }.isEmpty, "missing: \(paths.filter { !repositoryHas($0) })")
    }

    @Test("the template leaves the product name to the three files that may spell it")
    func keepsTheProductNameOut() throws {
        let name = try productName()

        #expect(!(try Self.template()).lowercased().contains(name.lowercased()))
    }
}
