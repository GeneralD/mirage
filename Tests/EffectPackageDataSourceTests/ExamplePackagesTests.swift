import Domain
import EffectPackageDataSource
import Foundation
import TestDoubles
import Testing

/// The packages under `Examples/` are what the README's Packaging section describes, so each
/// must read as ready through the same DataSource an author's folder goes through. The files are
/// the repository's own and are copied into the in-memory tree: the subject still sees no disk.
/// That the kernel compiles against the prelude is a real-device matter (the Lane 1 check of
/// `.claude/rules/dev-verification.md`); only the shape is pinned here.
@Suite("Example packages", .timeLimit(.minutes(1)))
struct ExamplePackagesTests {
    private static let examples = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Examples", directoryHint: .isDirectory)

    /// The folder names of the packages in `Examples/`.
    private static func packageNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: examples.path).filter { $0.hasSuffix(".lens") }.sorted()
    }

    private static func text(of file: String, in package: String) throws -> String {
        try String(contentsOf: examples.appending(path: package).appending(path: file), encoding: .utf8)
    }

    @Test("every package under Examples/ is ready, listed under its folder name, with a name and a kernel called `effect`")
    func examplesAreReady() async throws {
        let names = try Self.packageNames()
        let rig = PackageRig()
        for name in names {
            rig.files.write("\(PackageRig.folder)/\(name)/manifest.json", try Self.text(of: "manifest.json", in: name))
            rig.files.write("\(PackageRig.folder)/\(name)/effect.metal", try Self.text(of: "effect.metal", in: name))
        }

        let inventory = await rig.subject.packages()

        #expect(!names.isEmpty, "Examples/ holds no package")
        #expect(inventory.listings.map(\.id) == names.map { .package(String($0.dropLast(".lens".count))) })
        for listing in inventory.listings {
            guard case .ready(let package) = listing else {
                Issue.record("\(listing.id.key) is not ready: \(listing)")
                continue
            }
            #expect(package.manifest.formatVersion == EffectManifestDecoding.supportedFormatVersion)
            #expect(package.source.name == package.manifest.name)
            #expect(package.source.source.contains("kernel void effect("), "\(package.id.key) has no `effect` kernel")
            #expect(!package.source.source.contains("struct Uniforms"), "\(package.id.key) redefines the prelude's Uniforms")
        }
    }
}
