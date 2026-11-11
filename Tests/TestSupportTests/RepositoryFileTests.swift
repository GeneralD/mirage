import Foundation
import TestSupport
import Testing

@Suite("Repository files")
struct RepositoryFileTests {
    @Test("the root is the directory that holds Package.swift and Sources")
    func rootHoldsThePackage() {
        #expect(repositoryHas("Package.swift"))
        #expect(repositoryHas("Sources"))
    }

    @Test("text reads a file below the root: version.txt is a three-part version")
    func textReadsAFile() throws {
        let version = try repositoryText("version.txt").trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(version.wholeMatch(of: #/\d+\.\d+\.\d+/#) != nil, "version.txt reads \(version)")
    }

    @Test("text of a path that is not there throws")
    func textOfAMissingPathThrows() {
        #expect(throws: (any Error).self) { try repositoryText("no/such/file.txt") }
    }

    @Test("has is false for a path that is not there and true for a directory")
    func hasTellsFilesFromNothing() {
        #expect(!repositoryHas("no/such/file.txt"))
        #expect(repositoryHas("Tests/TestSupport"))
    }

    @Test("the testing rules name the suites that read the repository from disk")
    func testingRulesNameTheDocumentSuites() throws {
        let rules = try repositoryText(".claude/rules/testing.md")

        #expect(rules.contains("Tests/TestSupportTests/RepositoryDocs/"))
        #expect(rules.contains("repositoryText"))
    }
}
