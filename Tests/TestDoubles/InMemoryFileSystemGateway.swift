import Dependencies
import Domain
import Foundation
import TestSupport

/// `FileSystemGateway` over a tree in memory: the test builds the effects folder with
/// `write` / `makeDirectory`, edits it while the subject runs (`write` over a file is
/// an in-place save, `remove` then `write` an atomic one) and scripts what the real
/// disk would refuse with `failRead(of:with:)`. Paths are absolute strings and are
/// matched as written, trailing slashes aside; nothing resolves `.` or `..`. The root
/// `/` always exists.
///
/// Missing paths fail the way `FileManager` does, with a `CocoaError`
/// (`fileReadNoSuchFile`), so a subject that tells "missing" from "unreadable" by the
/// error type is exercised against the real shapes; a scripted error replaces that.
/// `contentsOfDirectory` lists names sorted, which the live gateway does not promise:
/// a subject must not depend on the order.
///
/// Every call is recorded (`listings`, `reads`, `createdDirectories`), failing ones
/// included, so a test can assert what the subject looked at and what it did not.
public final class InMemoryFileSystemGateway: FileSystemGateway, Sendable {
    private struct Tree {
        var directories: Set<String> = ["/"]
        var files: [String: String] = [:]
        var readFailures: [String: any Error] = [:]
        var createFailures: [String: any Error] = [:]
    }

    private let tree = Locked(Tree())
    /// The directory paths `contentsOfDirectory` was asked for, in call order.
    public let listings = Collector<String>()
    /// The file paths `readString` was asked for, in call order.
    public let reads = Collector<String>()
    /// The paths `createDirectory` was asked for, in call order.
    public let createdDirectories = Collector<String>()

    public init() {}

    // MARK: Hooks

    /// Writes `content` to the file at `path`, making the directories above it, and
    /// replacing what was there: an in-place save. A directory at `path` is a mistake in
    /// the test and is reported.
    public func write(_ path: String, _ content: String) {
        let path = Self.normalized(path)
        let isDirectory = tree.withLock { tree -> Bool in
            guard !tree.directories.contains(path) else { return true }
            Self.insertDirectories(above: path, into: &tree)
            tree.files[path] = content
            return false
        }
        if isDirectory { reportIssue("InMemoryFileSystemGateway.write: \(path) is a directory") }
    }

    /// Removes the file at `path`, or the directory and everything under it. Nothing
    /// there is not an error.
    public func remove(_ path: String) {
        let path = Self.normalized(path)
        tree.withLock { tree in
            let inside = { (candidate: String) in candidate == path || candidate.hasPrefix(path + "/") }
            tree.files = tree.files.filter { !inside($0.key) }
            tree.directories = tree.directories.filter { !inside($0) || $0 == "/" }
        }
    }

    /// Makes the directory at `path` and the ones above it.
    public func makeDirectory(_ path: String) {
        let path = Self.normalized(path)
        tree.withLock { tree in
            Self.insertDirectories(above: path, into: &tree)
            tree.directories.insert(path)
        }
    }

    /// Makes listing the directory at `path`, or reading the file at `path`, throw `error`
    /// (a `CocoaError` for a vanished, unreadable or forbidden path) until the next call
    /// with `nil` clears it. `isDirectory` does not throw and keeps answering from the tree.
    public func failRead(of path: String, with error: (any Error)?) {
        let path = Self.normalized(path)
        tree.withLock { $0.readFailures[path] = error }
    }

    /// Makes `createDirectory` of `path` throw `error` until the next call with `nil`.
    public func failCreateDirectory(of path: String, with error: (any Error)?) {
        let path = Self.normalized(path)
        tree.withLock { $0.createFailures[path] = error }
    }

    // MARK: FileSystemGateway

    public func contentsOfDirectory(_ path: String) throws -> [String] {
        let path = Self.normalized(path)
        listings.append(path)
        return try tree.withLock { tree in
            if let failure = tree.readFailures[path] { throw failure }
            guard tree.directories.contains(path) else {
                throw tree.files[path] == nil ? CocoaError(.fileReadNoSuchFile) : CocoaError(.fileReadUnknown)
            }
            return tree.directories.union(tree.files.keys).filter { Self.parent(of: $0) == path }.map(Self.name(of:)).sorted()
        }
    }

    public func isDirectory(_ path: String) -> Bool {
        let path = Self.normalized(path)
        return tree.withLock { $0.directories.contains(path) }
    }

    public func readString(_ path: String) throws -> String {
        let path = Self.normalized(path)
        reads.append(path)
        return try tree.withLock { tree in
            if let failure = tree.readFailures[path] { throw failure }
            guard let content = tree.files[path] else {
                throw tree.directories.contains(path) ? CocoaError(.fileReadUnknown) : CocoaError(.fileReadNoSuchFile)
            }
            return content
        }
    }

    public func createDirectory(_ path: String) throws {
        let path = Self.normalized(path)
        createdDirectories.append(path)
        try tree.withLock { tree in
            if let failure = tree.createFailures[path] { throw failure }
            guard tree.files[path] == nil else { throw CocoaError(.fileWriteFileExists) }
            Self.insertDirectories(above: path, into: &tree)
            tree.directories.insert(path)
        }
    }

    // MARK: Paths

    private static func normalized(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? normalized(String(path.dropLast())) : path
    }

    private static func parent(of path: String) -> String? {
        guard path != "/", let slash = path.lastIndex(of: "/") else { return nil }
        return slash == path.startIndex ? "/" : String(path[..<slash])
    }

    private static func name(of path: String) -> String {
        path.lastIndex(of: "/").map { String(path[path.index(after: $0)...]) } ?? path
    }

    private static func insertDirectories(above path: String, into tree: inout Tree) {
        guard let parent = parent(of: path) else { return }
        tree.directories.insert(parent)
        insertDirectories(above: parent, into: &tree)
    }
}
