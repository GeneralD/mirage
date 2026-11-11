import Foundation
import TestSupport
import Testing

/// Comments and rule documents that said what the code did until the parameter work landed: a manifest's `parameters` was read past, and
/// the compile cache was keyed by the source and the options alone. Each sentence below is now untrue, and a comment is not compiled, so
/// only a test keeps it from coming back.
@Suite("Stale statements")
struct StaleStatementTests {
    struct Statement: CustomTestStringConvertible, Sendable {
        let phrase: String
        let instead: String

        var testDescription: String { phrase }
    }

    static let statements = [
        Statement(
            phrase: "(source, compile options)",
            instead: "the cache key also carries the parameter layout: `(source, compile options, parameter layout)`"),
        Statement(
            phrase: "one source and options share one compiled library",
            instead: "one source, options and parameter layout share one compiled library"),
        Statement(
            phrase: "until MVP-C interprets it",
            instead: "`parameters` is read and validated now: it is not one of the keys that are ignored"),
    ]

    /// Every Swift file under `Sources/` and `Tests/` and every rule document, with its lines, except this file (which spells the phrases).
    private static let corpus: [(path: String, lines: [String])] = {
        let swift = ["Sources", "Tests"].flatMap { files(under: $0, suffix: ".swift") }
        return (swift + files(under: ".claude/rules", suffix: ".md"))
            .filter { !$0.hasSuffix("StaleStatementTests.swift") }
            .map { ($0, ((try? repositoryText($0)) ?? "").components(separatedBy: "\n")) }
    }()

    private static func files(under directory: String, suffix: String) -> [String] {
        (FileManager.default.subpaths(atPath: repositoryRoot.appending(path: directory).path) ?? [])
            .filter { $0.hasSuffix(suffix) }.map { "\(directory)/\($0)" }
    }

    @Test("no comment or rule document still says what the parameter work made untrue", arguments: statements)
    func isGone(_ statement: Statement) {
        let hits = Self.corpus.flatMap { file in
            file.lines.enumerated().filter { $0.element.contains(statement.phrase) }.map { "\(file.path):\($0.offset + 1)" }
        }

        #expect(hits.isEmpty, "\(hits) still say `\(statement.phrase)`; it is now \(statement.instead)")
    }

    @Test("the scan reaches the Swift files, the tests and the rule documents")
    func scansTheRepository() {
        let paths = Self.corpus.map(\.path)

        #expect(paths.contains("Sources/Entity/EffectSource.swift"))
        #expect(paths.contains("Tests/TestSupport/RepositoryFile.swift"))
        #expect(paths.contains(".claude/rules/testing.md"))
        #expect(!paths.contains { $0.hasSuffix("StaleStatementTests.swift") })
    }
}
