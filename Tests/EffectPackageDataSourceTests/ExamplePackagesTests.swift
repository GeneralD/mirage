import Domain
import EffectPackageDataSource
import Foundation
import TestDoubles
import Testing

/// The packages under `Examples/` are what the README's Packaging section describes, so each
/// must read as ready through the same DataSource an author's folder goes through, with the
/// thumbnail its manifest names. Every file of a package is the repository's own and is copied,
/// byte for byte, into the in-memory tree: the subject still sees no disk.
/// That the kernel compiles against the prelude is a real-device matter (the Lane 1 check of
/// `.claude/rules/dev-verification.md`); only the shape is pinned here.
@Suite("Example packages", .timeLimit(.minutes(1)))
struct ExamplePackagesTests {
    private static let examples = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Examples", directoryHint: .isDirectory)

    private static let suffix = ".lens"

    /// The ids of the packages in `Examples/`, in the order the DataSource lists them: the folder's name
    /// without `.lens`, in plain string order. Sorting the folder names instead would not do: with
    /// `Ripple.lens` and `Ripple-b.lens` the names put `Ripple-b` first (`-` sorts before `.`) and the
    /// ids put `Ripple` first.
    private static func packageIDs() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: examples.path)
            .filter { $0.hasSuffix(suffix) }.map { String($0.dropLast(suffix.count)) }.sorted()
    }

    /// Every file under the package `id`, as a path relative to the package and its bytes.
    private static func files(in id: String) throws -> [(path: String, bytes: Data)] {
        let package = examples.appending(path: id + suffix)
        let paths = FileManager.default.subpaths(atPath: package.path) ?? []
        return try paths.sorted().compactMap { path in
            let url = package.appending(path: path)
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { return nil }
            return (path, try Data(contentsOf: url))
        }
    }

    @Test("every package under Examples/ is ready, listed under its folder name, with a name, a kernel called `effect` and its thumbnail")
    func examplesAreReady() async throws {
        let ids = try Self.packageIDs()
        let rig = PackageRig()
        for id in ids {
            for file in try Self.files(in: id) {
                rig.files.write("\(PackageRig.folder)/\(id)\(Self.suffix)/\(file.path)", bytes: file.bytes)
            }
        }

        let inventory = await rig.subject.packages()

        #expect(!ids.isEmpty, "Examples/ holds no package")
        #expect(inventory.listings.map(\.id) == ids.map { .package($0) })
        for listing in inventory.listings {
            guard case .ready(let package) = listing else {
                Issue.record("\(listing.id.key) is not ready: \(listing)")
                continue
            }
            #expect(package.manifest.formatVersion == EffectManifestDecoding.supportedFormatVersion)
            #expect(package.source.name == package.manifest.name)
            #expect(package.source.source.contains("kernel void effect("), "\(package.id.key) has no `effect` kernel")
            #expect(!package.source.source.contains("struct Uniforms"), "\(package.id.key) redefines the prelude's Uniforms")
            #expect(
                (package.thumbnail != nil) == (package.manifest.thumbnail != nil),
                "\(package.id.key) names a thumbnail that cannot be used: \(rig.developer.messages(in: .effect) + rig.errors.messages(in: .effect))")
        }
        let ripple = inventory.listings.compactMap { listing -> EffectPackage? in
            guard case .ready(let package) = listing, package.id == .package("Ripple") else { return nil }
            return package
        }.first
        #expect(ripple?.thumbnail?.format == .png, "Ripple names the thumbnail.png the README shows, and it is read")
        #expect(ripple?.manifest.description?.isEmpty == false, "Ripple carries the description the README shows, which the picker's hover adds")
        #expect(rig.errors.entries.values.isEmpty)
        #expect(rig.developer.entries.values.isEmpty)
    }
}
