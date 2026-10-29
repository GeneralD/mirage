/// Live `FileSystemGateway`: one `FileManager` / `String` / `FileHandle` call per method. Wraps Foundation.
/// Thin by rule: what a `.lens` package is, and what to do when a read fails, are
/// `EffectPackageDataSource`'s, proven against `InMemoryFileSystemGateway`.
import Domain
import Foundation

public struct FileSystemGatewayImpl: FileSystemGateway {
    public init() {}

    public func contentsOfDirectory(_ path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)  // allow-physical: FileSystemGateway
    }

    /// Symlinks are resolved first: `resourceValues` alone answers `false` for a symlink to a
    /// directory, while `contentsOfDirectory` lists it, so a linked package would be listed but skipped.
    public func isDirectory(_ path: String) -> Bool {
        (try? URL(fileURLWithPath: path).resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    public func readString(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    /// `read(upToCount:)` stops at `maxLength`, so a larger file is never read whole; it answers `nil` for a
    /// file that has nothing to read, which is no bytes here, settled by the expression as `isDirectory` settles its own.
    public func readData(_ path: String, upTo maxLength: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        return try handle.read(upToCount: maxLength) ?? Data()
    }

    public func createDirectory(_ path: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)  // allow-physical: FileSystemGateway
    }
}
