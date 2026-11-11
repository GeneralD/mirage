import Foundation

/// The repository's root directory, found from this file's own path (`Tests/TestSupport/RepositoryFile.swift`), so it is the same
/// wherever the checkout lives. Read-only: the suites that use it hold a document, a workflow or a template to what the code says,
/// write nothing, and never hand the disk to the subject under test.
public let repositoryRoot: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// The UTF-8 text of the file at `path`, given relative to the repository root. Throws when the file is missing or is not UTF-8.
public func repositoryText(_ path: String) throws -> String {
    try String(contentsOf: repositoryRoot.appending(path: path), encoding: .utf8)
}

/// Whether a file or a directory exists at `path`, given relative to the repository root.
public func repositoryHas(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: repositoryRoot.appending(path: path).path)
}
