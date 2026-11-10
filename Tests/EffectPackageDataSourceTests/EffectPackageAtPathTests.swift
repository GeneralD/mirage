import Domain
import EffectPackageDataSource
import Foundation
import TestDoubles
import Testing

/// `package(atPath:)`, the package read from any directory (#267), proven over `InMemoryFileSystemGateway`:
/// no disk, no Finder. The effects folder is neither made nor listed, nothing is opened, and the picture the
/// manifest names is left out, as it is for `package(_:)`.
@Suite("EffectPackageAtPath", .timeLimit(.minutes(1)))
struct EffectPackageAtPathTests {
    private typealias Rig = PackageRig

    /// The package `Fx` at `/work/Fx.lens` as `writeFx` writes it: named `Glitch`, with no picture.
    private static let readyFx = EffectPackage(
        id: .package("Fx"),
        manifest: EffectManifest(formatVersion: 1, name: "Glitch", thumbnail: nil),
        source: EffectSource(name: "Glitch", source: Rig.validShader),
        thumbnail: nil)

    /// Writes the valid manifest and shader of a package in `directory`.
    private static func writeFx(_ rig: Rig, at directory: String = "/work/Fx.lens") {
        rig.files.write("\(directory)/manifest.json", Rig.validManifest)
        rig.files.write("\(directory)/effect.metal", Rig.validShader)
    }

    @Test("a package in a directory outside the effects folder is ready, its id the folder name without .lens, and carries no picture")
    func outsidePackageIsReady() async {
        let rig = Rig()
        Self.writeFx(rig)

        let listing = await rig.subject.package(atPath: "/work/Fx.lens")

        #expect(listing == .ready(Self.readyFx))
    }

    @Test("a trailing slash in the path is ignored: the same listing, and each file read once")
    func trailingSlashIsIgnored() async {
        let rig = Rig()
        Self.writeFx(rig)

        let listing = await rig.subject.package(atPath: "/work/Fx.lens/")

        #expect(listing == .ready(Self.readyFx))
        #expect(rig.files.reads.values == ["/work/Fx.lens/manifest.json", "/work/Fx.lens/effect.metal"])
    }

    @Test("a directory whose name does not end in .lens is read all the same, its whole name is the id")
    func nameWithoutSuffixIsTheKey() async {
        let rig = Rig()
        Self.writeFx(rig, at: "/work/plain")

        let listing = await rig.subject.package(atPath: "/work/plain")

        #expect(listing?.id == EffectID.package("plain"))
    }

    @Test("a relative path is read from where it leads, and its id is the name without .lens")
    func relativePathIsRead() async {
        let rig = Rig()
        Self.writeFx(rig, at: "Examples/Fx.lens")

        let listing = await rig.subject.package(atPath: "Examples/Fx.lens")

        #expect(listing == .ready(Self.readyFx))
    }

    @Test(
        "a path that does not exist, a path that is a file, an empty path and `/` each answer nil",
        arguments: ["/work/absent.lens", "/work/notAFolder.lens", "", "/"])
    func pathThatIsNotAPackageIsNil(path: String) async {
        let rig = Rig()
        rig.files.write("/work/notAFolder.lens", "a file")

        #expect(await rig.subject.package(atPath: path) == nil)
    }

    @Test("a package outside the folder without manifest.json is broken as manifestMissing, under its id")
    func outsideWithoutManifestIsBroken() async {
        let rig = Rig()
        rig.files.write("/work/Fx.lens/effect.metal", Rig.validShader)

        let listing = await rig.subject.package(atPath: "/work/Fx.lens")

        #expect(listing == .broken(.package("Fx"), .manifestMissing))
    }

    @Test("a package outside the folder whose manifest.json is not JSON is broken as manifestInvalid, with the reason")
    func outsideWithBrokenManifestIsBroken() async {
        let rig = Rig()
        rig.files.write("/work/Fx.lens/manifest.json", "{ not json")
        rig.files.write("/work/Fx.lens/effect.metal", Rig.validShader)

        let listing = await rig.subject.package(atPath: "/work/Fx.lens")

        #expect(listing == .broken(.package("Fx"), .manifestInvalid(message: "not valid JSON")))
    }

    @Test("a package outside the folder without effect.metal is broken as sourceMissing")
    func outsideWithoutShaderIsBroken() async {
        let rig = Rig()
        rig.files.write("/work/Fx.lens/manifest.json", Rig.validManifest)

        let listing = await rig.subject.package(atPath: "/work/Fx.lens")

        #expect(listing == .broken(.package("Fx"), .sourceMissing))
    }

    @Test("the effects folder is neither made nor listed, and nothing is opened, when a package is read from a path")
    func effectsFolderIsUntouched() async {
        let rig = Rig()
        Self.writeFx(rig)

        _ = await rig.subject.package(atPath: "/work/Fx.lens")

        #expect(rig.files.createdDirectories.values.isEmpty)
        #expect(rig.files.listings.values.isEmpty)
        #expect(rig.workspace.opened.values.isEmpty)
        #expect(!rig.files.isDirectory(Rig.folder))
    }

    @Test("a package read from a path leaves its picture out, though its manifest names one that is there")
    func pictureIsLeftOut() async {
        let rig = Rig()
        rig.files.write("/work/Fx.lens/manifest.json", Rig.manifestText(name: "Glitch", thumbnail: "thumbnail.png"))
        rig.files.write("/work/Fx.lens/effect.metal", Rig.validShader)
        rig.files.write("/work/Fx.lens/thumbnail.png", bytes: Rig.png)

        let listing = await rig.subject.package(atPath: "/work/Fx.lens")

        let expected = EffectPackage(
            id: .package("Fx"),
            manifest: EffectManifest(formatVersion: 1, name: "Glitch", thumbnail: "thumbnail.png"),
            source: EffectSource(name: "Glitch", source: Rig.validShader),
            thumbnail: nil)
        #expect(listing == .ready(expected))
        #expect(rig.files.dataReads.values.isEmpty)
    }

    @Test("a package of the effects folder, read by its path, is the same listing as read by its id")
    func folderPackageByPathIsTheSame() async {
        let rig = Rig()
        rig.writePackage("p")

        let byID = await rig.subject.package(.package("p"))
        let byPath = await rig.subject.package(atPath: PackageRig.directory("p"))

        #expect(byID != nil)
        #expect(byPath == byID)
    }
}
