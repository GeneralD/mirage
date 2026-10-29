import Dependencies
import Foundation

/// Thin pass-through to the file system (live: `FileManager`, a UTF-8 read and a
/// bounded `FileHandle` read), the
/// only way the effect packages and the effects folder are touched. Paths are plain
/// strings; nothing here interprets them, decides what a `.lens` package is or
/// recovers from an error: that is `EffectPackageDataSource`'s, against
/// `InMemoryFileSystemGateway`.
public protocol FileSystemGateway: Sendable {
    /// The names (not the paths) of what is in the directory at `path`, in no
    /// particular order. Throws when `path` does not exist, is not a directory or
    /// cannot be read.
    func contentsOfDirectory(_ path: String) throws -> [String]

    /// `true` only when `path` exists and is a directory.
    func isDirectory(_ path: String) -> Bool

    /// The UTF-8 contents of the file at `path`. Throws when it does not exist,
    /// cannot be read or is not valid text.
    func readString(_ path: String) throws -> String

    /// The first `maxLength` bytes of the file at `path`, or all of them when it is shorter
    /// (none for an empty file): a longer file is read only that far, so a caller that bounds
    /// what it keeps never holds more. Throws when it does not exist or cannot be read.
    func readData(_ path: String, upTo maxLength: Int) throws -> Data

    /// Makes the directory at `path` and any missing parents. A directory that is
    /// already there is not an error; a file in the way is.
    func createDirectory(_ path: String) throws
}

public enum FileSystemGatewayKey: TestDependencyKey {
    public static let testValue: any FileSystemGateway = UnimplementedFileSystemGateway()
}

extension DependencyValues {
    public var fileSystemGateway: any FileSystemGateway {
        get { self[FileSystemGatewayKey.self] }
        set { self[FileSystemGatewayKey.self] = newValue }
    }
}

private struct UnimplementedFileSystemGateway: FileSystemGateway {
    func contentsOfDirectory(_ path: String) throws -> [String] {
        reportIssue("FileSystemGateway.contentsOfDirectory not implemented")
        throw CocoaError(.fileReadNoSuchFile)
    }

    func isDirectory(_ path: String) -> Bool {
        reportIssue("FileSystemGateway.isDirectory not implemented")
        return false
    }

    func readString(_ path: String) throws -> String {
        reportIssue("FileSystemGateway.readString not implemented")
        throw CocoaError(.fileReadNoSuchFile)
    }

    func readData(_ path: String, upTo maxLength: Int) throws -> Data {
        reportIssue("FileSystemGateway.readData not implemented")
        throw CocoaError(.fileReadNoSuchFile)
    }

    func createDirectory(_ path: String) throws {
        reportIssue("FileSystemGateway.createDirectory not implemented")
        throw CocoaError(.fileWriteUnknown)
    }
}
