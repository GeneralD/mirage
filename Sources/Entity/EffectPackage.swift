/// A `.lens` package that was read: who it is, what its manifest says and the shader
/// source, in the form the runtime takes (`EffectRuntimeRepository.prepare`).
public struct EffectPackage: Sendable, Hashable {
    public let id: EffectID
    public let manifest: EffectManifest
    public let source: EffectSource

    public init(id: EffectID, manifest: EffectManifest, source: EffectSource) {
        self.id = id
        self.manifest = manifest
        self.source = source
    }
}

/// Why a package in the effects folder cannot be used. Closed so that every consumer
/// enumerates it; the menu shows the package as a disabled item with this reason
/// (epic #42, D3), so an author sees what is wrong instead of a package that vanished.
/// An `Error` so that `source(of:)` can answer with it in a `Result`.
public enum EffectPackageProblem: Error, Sendable, Hashable {
    /// The package folder has no `manifest.json`.
    case manifestMissing
    /// `manifest.json` is not valid JSON, lacks a required key or has one of the wrong type.
    case manifestInvalid(message: String)
    /// `formatVersion` is one this build does not read.
    case unsupportedFormatVersion(Int)
    /// The package folder has no `effect.metal`.
    case sourceMissing
    /// A file is there but could not be read (permissions, encoding, a file that went away mid-read).
    case unreadable(message: String)
}

/// One entry of the effects folder: a package that is ready, or one that is not and why.
public enum EffectPackageListing: Sendable, Hashable {
    case ready(EffectPackage)
    case broken(EffectID, EffectPackageProblem)

    public var id: EffectID {
        switch self {
        case .ready(let package): package.id
        case .broken(let id, _): id
        }
    }
}

/// What to watch so that a change to the folder's packages is noticed. The folder and
/// each package's directory are watched as directories (an editor's atomic save
/// renames the file, which only the directory sees); the manifest and the shader as
/// files (an in-place overwrite changes no directory entry). Epic #42, D4.
public struct EffectWatchSet: Sendable, Hashable {
    public let directories: [String]
    public let files: [String]

    public init(directories: [String], files: [String]) {
        self.directories = directories
        self.files = files
    }

    public static let empty = EffectWatchSet(directories: [], files: [])
}

/// A listing of the effects folder together with what to watch to learn that it changed.
public struct EffectPackageInventory: Sendable, Hashable {
    public let listings: [EffectPackageListing]
    public let watchSet: EffectWatchSet

    public init(listings: [EffectPackageListing], watchSet: EffectWatchSet) {
        self.listings = listings
        self.watchSet = watchSet
    }

    public static let empty = EffectPackageInventory(listings: [], watchSet: .empty)
}
