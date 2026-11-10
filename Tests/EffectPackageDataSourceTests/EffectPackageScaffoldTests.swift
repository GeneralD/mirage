import Dependencies
import Domain
import EffectPackageDataSource
import Foundation
import TestDoubles
import Testing

/// The scaffold of a `.lens` package, proven over `InMemoryFileSystemGateway`: the package is written only
/// through the gateway, its two files are the template's, and a package the scaffold wrote reads back as
/// ready. A write the disk would refuse is scripted with `failWriteData` or `failCreateDirectory`.
@Suite("EffectPackageDataSource scaffold", .timeLimit(.minutes(1)))
struct EffectPackageScaffoldTests {
    private typealias Rig = PackageRig

    private static let work = "/work"
    private static let packagePath = "/work/My Glitch.lens"
    private static let manifestPath = "/work/My Glitch.lens/manifest.json"
    private static let shaderPath = "/work/My Glitch.lens/effect.metal"

    @Test("scaffold(named:in:) writes manifest.json and effect.metal under the name and answers the package's path")
    func answersThePackagePath() async throws {
        let rig = Rig()

        let answer = await rig.subject.scaffold(named: "My Glitch", in: Self.work)

        let manifest = try rig.files.readString(Self.manifestPath)
        let shader = try rig.files.readString(Self.shaderPath)
        #expect(answer == .success(Self.packagePath))
        #expect(manifest == EffectScaffoldTemplate.manifest(named: "My Glitch"))
        #expect(shader == EffectScaffoldTemplate.effectSource)
    }

    @Test("a folder that is not there is made on the way, and the package's directory is the one made")
    func missingFolderIsMade() async {
        let rig = Rig()

        _ = await rig.subject.scaffold(named: "My Glitch", in: Self.work)

        #expect(rig.files.createdDirectories.values == [Self.packagePath])
        #expect(rig.files.isDirectory(Self.work))
    }

    @Test("a folder given with a trailing slash answers the same path, with no doubled slash")
    func trailingSlashIsDropped() async {
        let rig = Rig()

        let answer = await rig.subject.scaffold(named: "My Glitch", in: "/work/")

        #expect(answer == .success(Self.packagePath))
        #expect(rig.files.createdDirectories.values == [Self.packagePath])
    }

    @Test("the root as the folder answers a path directly under it")
    func rootFolderGivesPathUnderRoot() async {
        let rig = Rig()

        let answer = await rig.subject.scaffold(named: "My Glitch", in: "/")

        #expect(answer == .success("/My Glitch.lens"))
        #expect(rig.files.createdDirectories.values == ["/My Glitch.lens"])
    }

    @Test(
        "a name the template refuses is answered as invalid, and nothing is made or written",
        arguments: ["", " a", "a/b", "..", "日本語", String(repeating: "a", count: 65)])
    func invalidNameIsRefused(name: String) async {
        let rig = Rig()

        let answer = await rig.subject.scaffold(named: name, in: Self.work)

        #expect(answer == .failure(.invalidName(name)))
        #expect(rig.files.createdDirectories.values.isEmpty)
        #expect(rig.files.dataWrites.values.isEmpty)
    }

    @Test("a second scaffold of the same name is refused as already there, and writes nothing more")
    func secondScaffoldIsRefused() async {
        let rig = Rig()
        _ = await rig.subject.scaffold(named: "My Glitch", in: Self.work)
        let writesBefore = rig.files.dataWrites.values.count

        let answer = await rig.subject.scaffold(named: "My Glitch", in: Self.work)

        #expect(answer == .failure(.alreadyExists(path: Self.packagePath)))
        #expect(rig.files.dataWrites.values.count == writesBefore)
    }

    @Test("an empty directory of that name is refused as already there, and nothing is written")
    func emptyDirectoryIsRefused() async {
        let rig = Rig()
        rig.files.makeDirectory(Self.packagePath)

        let answer = await rig.subject.scaffold(named: "My Glitch", in: Self.work)

        #expect(answer == .failure(.alreadyExists(path: Self.packagePath)))
        #expect(rig.files.dataWrites.values.isEmpty)
    }

    @Test("a package of that name that is there keeps its content: nothing is written over it")
    func existingContentIsKept() async throws {
        let rig = Rig()
        rig.files.write(Self.manifestPath, "mine")

        let answer = await rig.subject.scaffold(named: "My Glitch", in: Self.work)

        let manifest = try rig.files.readString(Self.manifestPath)
        #expect(answer == .failure(.alreadyExists(path: Self.packagePath)))
        #expect(manifest == "mine")
        #expect(rig.files.dataWrites.values.isEmpty)
    }

    @Test("a directory that cannot be made is refused as unwritable at the package's directory, and nothing is written")
    func directoryThatCannotBeMade() async {
        let rig = Rig()
        rig.files.failCreateDirectory(of: Self.packagePath, with: CocoaError(.fileWriteNoPermission))

        let answer = await rig.subject.scaffold(named: "My Glitch", in: Self.work)

        #expect(answer == .failure(.unwritable(path: Self.packagePath)))
        #expect(rig.files.dataWrites.values.isEmpty)
    }

    @Test("a shader that cannot be written is refused as unwritable at that file, and the manifest is not written")
    func shaderThatCannotBeWritten() async {
        let rig = Rig()
        rig.files.failWriteData(of: Self.shaderPath, with: CocoaError(.fileWriteNoPermission))

        let answer = await rig.subject.scaffold(named: "My Glitch", in: Self.work)

        #expect(answer == .failure(.unwritable(path: Self.shaderPath)))
        #expect(rig.files.dataWrites.values.map(\.path) == [Self.shaderPath])
    }

    @Test("a manifest that cannot be written is refused as unwritable at that file, with the shader already written")
    func manifestThatCannotBeWritten() async throws {
        let rig = Rig()
        rig.files.failWriteData(of: Self.manifestPath, with: CocoaError(.fileWriteNoPermission))

        let answer = await rig.subject.scaffold(named: "My Glitch", in: Self.work)

        let shader = try rig.files.readString(Self.shaderPath)
        #expect(answer == .failure(.unwritable(path: Self.manifestPath)))
        #expect(shader == EffectScaffoldTemplate.effectSource)
    }

    @Test("a package whose manifest could not be written reads as broken for want of its manifest")
    func packageWithoutManifestIsBroken() async {
        let rig = Rig()
        rig.files.failWriteData(of: Self.manifestPath, with: CocoaError(.fileWriteNoPermission))

        _ = await rig.subject.scaffold(named: "My Glitch", in: Self.work)
        let listing = await rig.subject.package(atPath: Self.packagePath)

        #expect(listing == .broken(EffectID(origin: .package, key: "My Glitch"), .manifestMissing))
    }

    @Test("a package the scaffold wrote reads back as ready, with its name, one parameter and the template's shader")
    func writtenPackageIsReady() async {
        let rig = Rig()
        _ = await rig.subject.scaffold(named: "My Glitch", in: Self.work)

        let listing = await rig.subject.package(atPath: Self.packagePath)

        guard case .ready(let package) = listing else {
            Issue.record("the scaffolded package does not read as ready: \(String(describing: listing))")
            return
        }
        #expect(package.manifest.name == "My Glitch")
        #expect(package.manifest.parameters.count == 1)
        #expect(package.source.source == EffectScaffoldTemplate.effectSource)
    }
}
