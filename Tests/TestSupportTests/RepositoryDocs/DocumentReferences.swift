import Foundation
import TestSupport

/// The names `make` accepts as targets in the repository's `Makefile`: the word before the colon of every line that starts a rule.
/// `.PHONY` and the recipe lines (which start with a tab) are not rules.
func makefileTargets() throws -> Set<String> {
    Set(
        try repositoryText("Makefile").matches(of: #/^([A-Za-z][A-Za-z0-9_-]*):/#.anchorsMatchLineEndings())
            .map { String($0.output.1) })
}

/// The targets a document tells the reader to run: `make <target>` inside backticks, or at the start of a line (a line of a code
/// block). Prose such as "make a change" names no target.
func makeTargets(named text: String) -> Set<String> {
    let inline = text.matches(of: #/`make ([a-z][a-z0-9-]*)/#).map { String($0.output.1) }
    let block = text.matches(of: #/^make ([a-z][a-z0-9-]*)/#.anchorsMatchLineEndings()).map { String($0.output.1) }
    return Set(inline + block)
}

/// The repository paths a document points at, in the order they appear: a token in backticks that starts with one of the repository's
/// top-level directories (`docs/`, `.claude/`, `.github/`, `scripts/`, `Sources/`, `Tests/`, `Examples/`) or is one of the top-level
/// files, and the target of a relative Markdown link. A token with a space, a `*`, a `<` or a `{` is a pattern, not a path.
func repositoryPaths(in text: String) -> [String] {
    let tokens = text.matches(of: #/`([^`\s*<>{}]+)`/#).map { String($0.output.1) }
    let links = text.matches(of: #/\]\(([^)#\s:]+)\)/#).map { String($0.output.1) }
    let directories = ["docs/", ".claude/", ".github/", "scripts/", "Sources/", "Tests/", "Examples/"]
    let files = ["README.md", "AGENTS.md", "CONTRIBUTING.md", "LICENSE", "Makefile", "Package.swift", "project.yml", "version.txt"]
    return tokens.filter { token in directories.contains { token.hasPrefix($0) } || files.contains(token) } + links
}

/// The product's name as `project.yml` spells it (its `name:` key), so a suite can keep the name out of a document without spelling it.
func productName() throws -> String {
    let match = try repositoryText("project.yml").firstMatch(of: #/^name:[ \t]*"?([^"\s]+)"?/#.anchorsMatchLineEndings())
    guard let match else { throw MissingProductName() }
    return String(match.output.1)
}

struct MissingProductName: Error {}
