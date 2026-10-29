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

    static let validManifest = #"{"formatVersion": 1, "name": "Glitch"}"#
    static let validShader = "kernel void effect() {}\n"

    /// A package that reads as ready, named `name` in the menu.
    func writePackage(_ key: String, name: String? = nil, shader: String = PackageRig.validShader) {
        files.write(Self.manifest(key), #"{"formatVersion": 1, "name": "\#(name ?? key)"}"#)
        files.write(Self.shader(key), shader)
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
