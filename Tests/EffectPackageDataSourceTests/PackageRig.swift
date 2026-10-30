import Dependencies
import Domain
import EffectPackageDataSource
import Foundation
import TestDoubles

/// The subject over an in-memory effects folder: the tree the test builds, the workspace that
/// records what it was asked to open, and one log per sink so a test can tell an error from a
/// developer line. The subject is built inside `withDependencies`, so it resolves these and
/// not the unimplemented defaults.
struct PackageRig {
    static let folder = "/Users/test/Library/Application Support/host/Effects"

    let files: InMemoryFileSystemGateway
    let workspace = FakeWorkspaceGateway()
    let errors = RecordingLog()
    let developer = RecordingLog()
    let subject: EffectPackageDataSourceImpl

    init(files: InMemoryFileSystemGateway = InMemoryFileSystemGateway(), listing: (any FileSystemGateway)? = nil) {
        self.files = files
        let workspace = workspace
        let errors = errors
        let developer = developer
        subject = withDependencies {
            $0.fileSystemGateway = listing ?? files
            $0.appDirectories = FixedAppDirectories(effectsDirectory: Self.folder)
            $0.workspaceGateway = workspace
            $0.errorLog = errors
            $0.developerLog = developer
        } operation: {
            EffectPackageDataSourceImpl()
        }
    }

    // MARK: Building the folder

    static func directory(_ key: String) -> String { "\(folder)/\(key).lens" }
    static func manifest(_ key: String) -> String { "\(directory(key))/manifest.json" }
    static func shader(_ key: String) -> String { "\(directory(key))/effect.metal" }

    /// The file at `path` inside the package `key`, as the subject joins it.
    static func file(_ key: String, _ path: String) -> String { "\(directory(key))/\(path)" }

    static let validManifest = #"{"formatVersion": 1, "name": "Glitch"}"#
    static let validShader = "kernel void effect() {}\n"
    /// Bytes that begin as a PNG and as a JPEG do, and then differ.
    static let png = Data(EffectThumbnailFormat.png.leadingBytes + Array("IHDR".utf8))
    static let jpeg = Data(EffectThumbnailFormat.jpeg.leadingBytes + Array("JFIF".utf8))

    /// A package that reads as ready, named `name` in the menu, its manifest naming `thumbnail` when one is given
    /// (the image file is the test's to write).
    func writePackage(_ key: String, name: String? = nil, shader: String = PackageRig.validShader, thumbnail: String? = nil) {
        files.write(Self.manifest(key), Self.manifestText(name: name ?? key, thumbnail: thumbnail))
        files.write(Self.shader(key), shader)
    }

    /// A valid manifest as JSON, the thumbnail's path escaped as JSON escapes it whatever it holds.
    static func manifestText(name: String, thumbnail: String? = nil) -> String {
        let manifest = EffectManifest(formatVersion: 1, name: name, thumbnail: thumbnail)
        return (try? JSONEncoder().encode(manifest)).map { String(decoding: $0, as: UTF8.self) } ?? "not encodable"
    }
}

/// A `FileSystemGateway` over another, listing in the reverse of the order it gives: the live
/// gateway promises no order and `InMemoryFileSystemGateway` always sorts, so only this proves that the
/// subject puts the packages in order itself.
struct ReversingFileSystemGateway: FileSystemGateway {
    let base: InMemoryFileSystemGateway

    func contentsOfDirectory(_ path: String) throws -> [String] { try base.contentsOfDirectory(path).reversed() }
    func isDirectory(_ path: String) -> Bool { base.isDirectory(path) }
    func readString(_ path: String) throws -> String { try base.readString(path) }
    func readData(_ path: String, upTo maxLength: Int) throws -> Data { try base.readData(path, upTo: maxLength) }
    func createDirectory(_ path: String) throws { try base.createDirectory(path) }
}

/// An `AppDirectoriesProvider` whose folder the test moves between two calls.
final class MovableDirectories: AppDirectoriesProvider, Sendable {
    private let path: Locked<String>

    init(_ path: String) {
        self.path = Locked(path)
    }

    var effectsDirectory: String { path.current }

    func move(to newPath: String) {
        path.set(newPath)
    }
}
