import Dependencies
import Domain
import Foundation

/// The effects folder as `.lens` packages (epic #42, D1 / D2 / D3): a folder named `<id>.lens`
/// holding a `manifest.json` and an `effect.metal`. It lists the folder, reads each package and
/// answers `.ready` with the shader as an `EffectSource` (default compile options), or `.broken`
/// with the reason; a package it cannot use is never left out. Everything it touches comes
/// through `FileSystemGateway`, `WorkspaceGateway` and `AppDirectoriesProvider`, and the
/// effects folder's path is asked of the provider on each call, never kept.
///
/// - **Which entries are packages.** Only a directory whose name ends in `.lens`, under a
///   non-empty id; any other file or directory in the folder is ignored. The listing is in id
///   order whatever order the gateway lists in (the live one promises none).
/// - **What is broken.** Both files of a package are read every time. The first problem in
///   this order is the one reported: `manifest.json` missing, unreadable, then undecodable
///   (`EffectManifestDecoding`), then `effect.metal` missing, then unreadable. A file that
///   cannot be found is *missing*, told by the `CocoaError` code and never by a message;
///   any other failure to read it (permissions, text that is not UTF-8, a path that is a
///   directory) is *unreadable*.
/// - **The thumbnail** (#12) is read by `packages()` only, for a package that is ready and whose
///   manifest names one. `EffectThumbnailReading` decides from the path's text whether it can be
///   read at all. A directory on its way that is not there, or is a file, makes the file missing,
///   and a directory where the file should be is refused, both found by asking `isDirectory`
///   before anything is read, since `FileHandle`'s codes for them would say otherwise. Then the
///   file is read through `readData` with that type's bound, and the bytes become the package's
///   `thumbnail` or are refused. A thumbnail that cannot be used leaves the package ready without
///   one: a file that is there and cannot be read is logged as an error, any other reason (a path
///   that is refused, a file that is missing, a directory, too large or not an image) as a
///   developer line. A value of `thumbnail` that is neither a string nor `null` is a manifest of
///   the wrong shape, as it is for `author`, and the package is broken.
/// - **What to watch** (`EffectWatchSet`). The folder and the directory of every package,
///   ready or broken, as directories; and every `manifest.json` / `effect.metal` that is
///   there, as files. A file that is missing is not named (it cannot be watched), but the
///   package directory is, so creating it is noticed and the next listing watches it. The
///   shader of a package whose manifest is broken is watched as well, so fixing the manifest
///   in place is noticed either way. A thumbnail that was read, or that would have been had
///   it been there, adds its file when it is there, and every directory on its way below the
///   package directory that is there, whether the file is or not, so an atomic save in a
///   subdirectory is heard and so is creating the file or a directory on its way.
/// - **The folder.** Listing, and opening, make it when it is not there. A folder that cannot
///   be made is logged and gives no listing and nothing to watch; one that cannot be listed
///   is logged and gives no listing, with the folder still watched, so a later change to it
///   is noticed.
/// - **`package(_:)`** is the same read for one id, less the thumbnail: `nil` for an id that is not a package's,
///   or whose key is not one path component (it comes back from a persisted selection and is
///   joined into a path, so `../x` must not leave the folder), or whose directory is not
///   there. It never makes the folder. It is the read a source is prepared from, so it answers a
///   ready package without its thumbnail (`nil`): the picture travels with `packages()`, and
///   reading it here as well would read it again, and log again why it cannot be used, on every
///   listing and every choice.
public struct EffectPackageDataSourceImpl: Sendable {
    @Dependency(\.fileSystemGateway) private var fileSystem
    @Dependency(\.appDirectories) private var appDirectories
    @Dependency(\.workspaceGateway) private var workspace
    @Dependency(\.errorLog) private var errorLog
    @Dependency(\.developerLog) private var developerLog

    private static let packageSuffix = ".lens"
    private static let manifestFileName = "manifest.json"
    private static let sourceFileName = "effect.metal"

    public init() {}
}

extension EffectPackageDataSourceImpl: EffectPackages {
    public func packages() async -> EffectPackageInventory {
        let folder = appDirectories.effectsDirectory
        guard makeFolderIfAbsent(folder) else { return .empty }
        guard let names = listFolder(folder) else { return Self.inventory(of: [], in: folder) }
        let reads = names.compactMap(Self.key(ofDirectoryNamed:)).sorted()
            .filter { fileSystem.isDirectory(Self.directory(of: $0, in: folder)) }
            .map { read($0, in: folder, includingThumbnail: true) }
        return Self.inventory(of: reads, in: folder)
    }

    public func package(_ id: EffectID) async -> EffectPackageListing? {
        guard id.origin == .package, Self.isPackageKey(id.key) else { return nil }
        let folder = appDirectories.effectsDirectory
        guard fileSystem.isDirectory(Self.directory(of: id.key, in: folder)) else { return nil }
        return read(id.key, in: folder, includingThumbnail: false).listing
    }

    public func openFolder() {
        let folder = appDirectories.effectsDirectory
        guard makeFolderIfAbsent(folder) else { return }
        workspace.open(folder)
    }
}

// MARK: - The folder

extension EffectPackageDataSourceImpl {
    /// `true` when the folder is a directory, after making it if it was not there.
    private func makeFolderIfAbsent(_ folder: String) -> Bool {
        guard !fileSystem.isDirectory(folder) else { return true }
        do {
            try fileSystem.createDirectory(folder)
            return true
        } catch {
            errorLog.record(.effect, "the effects folder cannot be made: \(Self.reason(of: error))")
            return false
        }
    }

    private func listFolder(_ folder: String) -> [String]? {
        do {
            return try fileSystem.contentsOfDirectory(folder)
        } catch {
            errorLog.record(.effect, "the effects folder cannot be listed: \(Self.reason(of: error))")
            return nil
        }
    }

    private static func inventory(of reads: [PackageRead], in folder: String) -> EffectPackageInventory {
        EffectPackageInventory(
            listings: reads.map(\.listing),
            watchSet: EffectWatchSet(directories: [folder] + reads.flatMap(\.directories), files: reads.flatMap(\.files)))
    }
}

// MARK: - One package

extension EffectPackageDataSourceImpl {
    /// A package as read: what it is, and which of its directories and files to watch.
    private struct PackageRead {
        let listing: EffectPackageListing
        let directories: [String]
        let files: [String]
    }

    /// What reading a package's thumbnail gives: the picture, when it can be used, and the directories
    /// and the file to watch for it.
    private struct ThumbnailRead {
        let picture: EffectThumbnail?
        let directories: [String]
        let file: String?

        static let nothing = ThumbnailRead(picture: nil, directories: [], file: nil)
    }

    private enum FileRead {
        case text(String)
        case missing
        case unreadable(EffectPackageProblem)

        var exists: Bool {
            if case .missing = self { return false }
            return true
        }
    }

    /// The package `key`, with its thumbnail read as well when `includingThumbnail`.
    private func read(_ key: String, in folder: String, includingThumbnail: Bool) -> PackageRead {
        let directory = Self.directory(of: key, in: folder)
        let manifestPath = Self.join(directory, Self.manifestFileName)
        let sourcePath = Self.join(directory, Self.sourceFileName)
        let manifestRead = readFile(manifestPath, named: Self.manifestFileName)
        let sourceRead = readFile(sourcePath, named: Self.sourceFileName)
        let files = [(manifestPath, manifestRead), (sourcePath, sourceRead)].filter(\.1.exists).map(\.0)

        let id = EffectID(origin: .package, key: key)
        switch Self.contents(manifest: manifestRead, source: sourceRead) {
        case .failure(let problem):
            report(problem, of: id)
            return PackageRead(listing: .broken(id, problem), directories: [directory], files: files)
        case .success(let (manifest, source)):
            let thumbnail = includingThumbnail ? readThumbnail(manifest.thumbnail, of: id, in: directory) : .nothing
            return PackageRead(
                listing: .ready(EffectPackage(id: id, manifest: manifest, source: source, thumbnail: thumbnail.picture)),
                directories: [directory] + thumbnail.directories,
                files: files + [thumbnail.file].compactMap { $0 })
        }
    }

    /// The manifest and the shader of a package that can be used, or the first problem in the documented order.
    private static func contents(
        manifest: FileRead, source: FileRead
    ) -> Result<(EffectManifest, EffectSource), EffectPackageProblem> {
        switch manifest {
        case .missing: return .failure(.manifestMissing)
        case .unreadable(let problem): return .failure(problem)
        case .text(let manifestText):
            switch EffectManifestDecoding.decode(manifestText) {
            case .failure(let problem): return .failure(problem)
            case .success(let decoded):
                switch source {
                case .missing: return .failure(.sourceMissing)
                case .unreadable(let problem): return .failure(problem)
                case .text(let sourceText): return .success((decoded, EffectSource(name: decoded.name, source: sourceText)))
                }
            }
        }
    }

    private func readFile(_ path: String, named name: String) -> FileRead {
        do {
            return .text(try fileSystem.readString(path))
        } catch  where Self.isMissing(error) {
            return .missing
        } catch {
            return .unreadable(.unreadable(message: "\(name) could not be read: \(Self.reason(of: error))"))
        }
    }

    /// The picture a ready package's manifest names at `path`, when it can be used, and what to watch
    /// for it. A manifest that names none adds nothing.
    private func readThumbnail(_ path: String?, of id: EffectID, in directory: String) -> ThumbnailRead {
        guard let path else { return .nothing }
        switch EffectThumbnailReading.components(of: path) {
        case .failure(let problem):
            report(problem, of: id, at: path)
            return .nothing
        case .success(let components):
            let file = components.reduce(directory, Self.join)
            let parents = components.indices.dropLast().map { components[...$0].reduce(directory, Self.join) }
            let directories = Array(parents.prefix { fileSystem.isDirectory($0) })
            // A directory on the way that is not one, missing or a file, leaves no file to read: below a file
            // `FileHandle` fails with `fileWriteUnknown`, which would read as a file that cannot be read.
            let bytes: Result<Data, EffectThumbnailReading.Problem> =
                directories.count < parents.count ? .failure(.missing) : readBytes(file)
            return ThumbnailRead(
                picture: usable(bytes.flatMap(EffectThumbnailReading.thumbnail(from:)), of: id, at: path),
                directories: directories,
                file: Self.isThere(bytes) ? file : nil)
        }
    }

    /// The thumbnail, or `nil` with the reason logged.
    private func usable(
        _ thumbnail: Result<EffectThumbnail, EffectThumbnailReading.Problem>, of id: EffectID, at path: String
    ) -> EffectThumbnail? {
        switch thumbnail {
        case .success(let thumbnail):
            return thumbnail
        case .failure(let problem):
            report(problem, of: id, at: path)
            return nil
        }
    }

    /// The bytes of the file at `path`, or why there are none. A directory there is found by asking, before
    /// anything is read: `FileHandle` has been seen to fail on one with `fileNoSuchFile`, `fileWriteUnknown`
    /// and `fileWriteNoPermission`, so its code would make it missing or unreadable by chance.
    private func readBytes(_ path: String) -> Result<Data, EffectThumbnailReading.Problem> {
        guard !fileSystem.isDirectory(path) else { return .failure(.directory) }
        do {
            return .success(try fileSystem.readData(path, upTo: EffectThumbnailReading.readLength))
        } catch  where Self.isMissing(error) {
            return .failure(.missing)
        } catch {
            return .failure(.unreadable(reason: Self.reason(of: error)))
        }
    }

    /// Whether the thumbnail's file is there to be watched: it is, unless it is missing or a directory,
    /// whose change the directory it is in hears.
    private static func isThere(_ bytes: Result<Data, EffectThumbnailReading.Problem>) -> Bool {
        switch bytes {
        case .failure(.missing), .failure(.directory): false
        case .success, .failure: true
        }
    }

    /// A thumbnail that cannot be used is logged with the path as written (quoted and escaped, so a
    /// newline or a NUL in it reads as an escape), as an error when the file is there and cannot be read.
    private func report(_ problem: EffectThumbnailReading.Problem, of id: EffectID, at path: String) {
        let message = "package \(id.key): thumbnail \(String(reflecting: path)) \(problem)"
        switch problem {
        case .unreadable: errorLog.record(.effect, message)
        case .empty, .absolute, .nulCharacter, .outsidePackage, .unsupportedType, .missing, .directory, .tooLarge, .notAnImage:
            developerLog.record(.effect, message)
        }
    }

    /// A broken package reaches the menu with its reason; the logs carry it too, the operational
    /// failures (a file that exists and cannot be read) among the errors.
    private func report(_ problem: EffectPackageProblem, of id: EffectID) {
        switch problem {
        case .unreadable(let message): errorLog.record(.effect, "package \(id.key): \(message)")
        case .manifestMissing, .manifestInvalid, .unsupportedFormatVersion, .sourceMissing:
            developerLog.record(.effect, "package \(id.key) is broken: \(problem)")
        }
    }
}

// MARK: - Names, paths and errors

extension EffectPackageDataSourceImpl {
    /// The id of the package a directory named `name` would be, or `nil` when it is not a `.lens` name.
    private static func key(ofDirectoryNamed name: String) -> String? {
        guard name.hasSuffix(packageSuffix) else { return nil }
        let key = String(name.dropLast(packageSuffix.count))
        return isPackageKey(key) ? key : nil
    }

    /// An id is a directory name without its suffix: one path component, never empty.
    private static func isPackageKey(_ key: String) -> Bool {
        !key.isEmpty && !key.contains("/")
    }

    private static func directory(of key: String, in folder: String) -> String {
        join(folder, key + packageSuffix)
    }

    private static func join(_ directory: String, _ name: String) -> String {
        directory + "/" + name
    }

    /// The file is not there: `fileReadNoSuchFile`, which the live and the in-memory gateway raise for
    /// `readString`, or `fileNoSuchFile`, which they raise for `readData` (`FileHandle` reports a missing
    /// file with it). Every other error, whatever its type, is a file that is there and cannot be read.
    private static func isMissing(_ error: any Error) -> Bool {
        let code = (error as? CocoaError)?.code
        return code == .fileReadNoSuchFile || code == .fileNoSuchFile
    }

    /// Why an operation failed, in words that do not depend on the locale.
    private static func reason(of error: any Error) -> String {
        switch (error as? CocoaError)?.code {
        case .fileReadCorruptFile?: "it is not valid UTF-8 text"
        case .fileReadNoPermission?, .fileWriteNoPermission?: "permission denied"
        case let code?: "Cocoa error \(code.rawValue)"
        case nil: "unexpected error"
        }
    }
}
