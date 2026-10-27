import Dependencies
import Domain
import EffectPackageDataSource
import Foundation
import TestDoubles
import Testing

/// What the effects folder lists as, proven over `InMemoryFileSystemGateway`: no disk, no Finder.
/// The folder's whole life is the test's: it builds the tree, edits it between two calls and
/// scripts the errors a real disk would raise.
@Suite("EffectPackageDataSource listing", .timeLimit(.minutes(1)))
struct EffectPackageDataSourceTests {
    private typealias Rig = PackageRig

    // MARK: The folder

    @Test("a folder that is not there is made, and lists as empty with the folder itself to watch")
    func missingFolderIsMade() async {
        let rig = Rig()

        let inventory = await rig.subject.packages()

        #expect(rig.files.createdDirectories.values == [Rig.folder])
        #expect(rig.files.isDirectory(Rig.folder))
        #expect(inventory == EffectPackageInventory(listings: [], watchSet: EffectWatchSet(directories: [Rig.folder], files: [])))
    }

    @Test("a folder that is there is not made again")
    func existingFolderIsLeftAlone() async {
        let rig = Rig()
        rig.files.makeDirectory(Rig.folder)

        let inventory = await rig.subject.packages()

        #expect(rig.files.createdDirectories.values.isEmpty)
        #expect(inventory.listings.isEmpty)
    }

    @Test("a folder that cannot be made lists as nothing and nothing to watch, and the error is logged")
    func folderThatCannotBeMade() async {
        let rig = Rig()
        rig.files.failCreateDirectory(of: Rig.folder, with: CocoaError(.fileWriteNoPermission))

        let inventory = await rig.subject.packages()

        #expect(inventory == .empty)
        #expect(rig.errors.messages(in: .effect) == ["the effects folder cannot be made: permission denied"])
    }

    @Test("a file where the folder should be lists as nothing and nothing to watch, and the error is logged")
    func fileInPlaceOfTheFolder() async {
        let rig = Rig()
        rig.files.write(Rig.folder, "not a folder")

        let inventory = await rig.subject.packages()

        #expect(inventory == .empty)
        #expect(rig.errors.messages(in: .effect).count == 1)
        #expect(rig.files.listings.values.isEmpty)
    }

    @Test("a folder that cannot be listed lists as nothing, the folder still watched, and the error is logged")
    func folderThatCannotBeListed() async {
        let rig = Rig()
        rig.files.makeDirectory(Rig.folder)
        rig.files.failRead(of: Rig.folder, with: CocoaError(.fileReadNoPermission))

        let inventory = await rig.subject.packages()

        #expect(inventory == EffectPackageInventory(listings: [], watchSet: EffectWatchSet(directories: [Rig.folder], files: [])))
        #expect(rig.errors.messages(in: .effect) == ["the effects folder cannot be listed: permission denied"])
    }

    @Test("the folder is asked of the provider on each call: a folder that moves is followed")
    func folderIsAskedEachTime() async {
        let files = InMemoryFileSystemGateway()
        let directories = MovableDirectories("/first")
        let subject = withDependencies {
            $0.fileSystemGateway = files
            $0.appDirectories = directories
        } operation: {
            EffectPackageDataSourceImpl()
        }
        files.write("/first/a.lens/manifest.json", Rig.validManifest)
        files.write("/second/b.lens/manifest.json", Rig.validManifest)

        let first = await subject.packages()
        directories.move(to: "/second")
        let second = await subject.packages()

        #expect(first.listings.map(\.id) == [.package("a")])
        #expect(second.listings.map(\.id) == [.package("b")])
        #expect(second.watchSet.directories == ["/second", "/second/b.lens"])
    }

    // MARK: Which entries are packages

    @Test("a ready package carries its manifest and its shader as the source to compile, under the manifest's name")
    func readyPackage() async {
        let rig = Rig()
        let manifest = #"{"formatVersion": 1, "name": "  Glitch ", "author": "Ada", "description": "Tears the frame"}"#
        let shader = "kernel void effect() {}\n// the whole file, newline and all\n"
        rig.files.write(Rig.manifest("glitch"), manifest)
        rig.files.write(Rig.shader("glitch"), shader)

        let inventory = await rig.subject.packages()

        let expected = EffectPackage(
            id: .package("glitch"),
            manifest: EffectManifest(formatVersion: 1, name: "Glitch", author: "Ada", description: "Tears the frame"),
            source: EffectSource(name: "Glitch", source: shader, options: ShaderCompileOptions()))
        #expect(inventory.listings == [.ready(expected)])
        #expect(rig.errors.entries.values.isEmpty)
        #expect(rig.developer.entries.values.isEmpty)
    }

    @Test(
        "only a directory named for a `.lens` package is one: a plain file, a file with the suffix, other directories and a bare suffix are ignored without being looked into"
    )
    func onlyLensDirectoriesAreListed() async {
        let rig = Rig()
        rig.writePackage("glitch")
        rig.files.write("\(Rig.folder)/notes.txt", "hello")
        rig.files.write("\(Rig.folder)/flat.lens", "a file that only has the suffix")
        rig.files.write("\(Rig.folder)/draft/manifest.json", Rig.validManifest)
        rig.files.write("\(Rig.folder)/draft/effect.metal", Rig.validShader)
        rig.files.write("\(Rig.folder)/.lens/manifest.json", Rig.validManifest)
        rig.files.write("\(Rig.folder)/.lens/effect.metal", Rig.validShader)
        rig.files.write("\(Rig.folder)/.DS_Store", "")

        let inventory = await rig.subject.packages()

        #expect(inventory.listings.map(\.id) == [.package("glitch")])
        #expect(inventory.watchSet.directories == [Rig.folder, Rig.directory("glitch")])
        #expect(rig.files.listings.values == [Rig.folder])
        #expect(rig.files.reads.values == [Rig.manifest("glitch"), Rig.shader("glitch")])
    }

    @Test("the packages come in id order whatever order the gateway lists them in, plainly sorted, and the watch set follows")
    func packagesAreInIdOrder() async {
        let files = InMemoryFileSystemGateway()
        let rig = Rig(files: files, listing: ReversingFileSystemGateway(base: files))
        for key in ["b", "a-b", "a", "B", "c"] { rig.writePackage(key) }

        let inventory = await rig.subject.packages()

        let ids = ["B", "a", "a-b", "b", "c"]
        #expect(inventory.listings.map(\.id) == ids.map { .package($0) })
        #expect(inventory.watchSet.directories == [Rig.folder] + ids.map(Rig.directory))
        #expect(inventory.watchSet.files == ids.flatMap { [Rig.manifest($0), Rig.shader($0)] })
    }

    // MARK: What is broken

    struct Breakage: Sendable, CustomTestStringConvertible {
        let name: String
        let arrange: @Sendable (InMemoryFileSystemGateway) -> Void
        let problem: EffectPackageProblem
        /// What of the package's files is there to be watched, in order.
        let watched: [String]

        var testDescription: String { name }
    }

    static let breakages: [Breakage] = [
        Breakage(
            name: "no manifest.json",
            arrange: { $0.write(Rig.shader("p"), Rig.validShader) },
            problem: .manifestMissing, watched: [Rig.shader("p")]),
        Breakage(
            name: "no files at all",
            arrange: { $0.makeDirectory(Rig.directory("p")) },
            problem: .manifestMissing, watched: []),
        Breakage(
            name: "manifest.json is not JSON",
            arrange: {
                $0.write(Rig.manifest("p"), "{ not json")
                $0.write(Rig.shader("p"), Rig.validShader)
            },
            problem: .manifestInvalid(message: "not valid JSON"), watched: [Rig.manifest("p"), Rig.shader("p")]),
        Breakage(
            name: "the name is empty",
            arrange: {
                $0.write(Rig.manifest("p"), #"{"formatVersion": 1, "name": "   "}"#)
                $0.write(Rig.shader("p"), Rig.validShader)
            },
            problem: .manifestInvalid(message: "\"name\" is empty"), watched: [Rig.manifest("p"), Rig.shader("p")]),
        Breakage(
            name: "a format version this build does not read",
            arrange: {
                $0.write(Rig.manifest("p"), #"{"formatVersion": 2, "name": "P"}"#)
                $0.write(Rig.shader("p"), Rig.validShader)
            },
            problem: .unsupportedFormatVersion(2), watched: [Rig.manifest("p"), Rig.shader("p")]),
        Breakage(
            name: "no effect.metal",
            arrange: { $0.write(Rig.manifest("p"), Rig.validManifest) },
            problem: .sourceMissing, watched: [Rig.manifest("p")]),
        Breakage(
            name: "manifest.json cannot be read for lack of permission",
            arrange: {
                $0.write(Rig.manifest("p"), Rig.validManifest)
                $0.write(Rig.shader("p"), Rig.validShader)
                $0.failRead(of: Rig.manifest("p"), with: CocoaError(.fileReadNoPermission))
            },
            problem: .unreadable(message: "manifest.json could not be read: permission denied"), watched: [Rig.manifest("p"), Rig.shader("p")]),
        Breakage(
            name: "manifest.json is not UTF-8 text",
            arrange: {
                $0.write(Rig.manifest("p"), Rig.validManifest)
                $0.write(Rig.shader("p"), Rig.validShader)
                $0.failRead(of: Rig.manifest("p"), with: CocoaError(.fileReadCorruptFile))
            },
            problem: .unreadable(message: "manifest.json could not be read: it is not valid UTF-8 text"),
            watched: [Rig.manifest("p"), Rig.shader("p")]),
        Breakage(
            name: "effect.metal is not UTF-8 text",
            arrange: {
                $0.write(Rig.manifest("p"), Rig.validManifest)
                $0.write(Rig.shader("p"), Rig.validShader)
                $0.failRead(of: Rig.shader("p"), with: CocoaError(.fileReadCorruptFile))
            },
            problem: .unreadable(message: "effect.metal could not be read: it is not valid UTF-8 text"),
            watched: [Rig.manifest("p"), Rig.shader("p")]),
        Breakage(
            name: "effect.metal is a directory",
            arrange: {
                $0.write(Rig.manifest("p"), Rig.validManifest)
                $0.makeDirectory(Rig.shader("p"))
            },
            problem: .unreadable(message: "effect.metal could not be read: Cocoa error \(CocoaError.Code.fileReadUnknown.rawValue)"),
            watched: [Rig.manifest("p"), Rig.shader("p")]),
        Breakage(
            name: "a read that fails with an error that is not a Cocoa error",
            arrange: {
                $0.write(Rig.manifest("p"), Rig.validManifest)
                $0.write(Rig.shader("p"), Rig.validShader)
                $0.failRead(of: Rig.shader("p"), with: UnexpectedFailure())
            },
            problem: .unreadable(message: "effect.metal could not be read: unexpected error"), watched: [Rig.manifest("p"), Rig.shader("p")]),
    ]

    struct UnexpectedFailure: Error {}

    @Test("a package that cannot be used is listed as broken with the reason, and what of it exists is watched", arguments: breakages)
    func brokenPackage(_ breakage: Breakage) async {
        let rig = Rig()
        breakage.arrange(rig.files)

        let inventory = await rig.subject.packages()

        #expect(inventory.listings == [.broken(.package("p"), breakage.problem)])
        #expect(inventory.watchSet == EffectWatchSet(directories: [Rig.folder, Rig.directory("p")], files: breakage.watched))
    }

    @Test(
        "both `no such file` codes mean a missing file, even for a path the tree holds: the code is read, never a message",
        arguments: [CocoaError.Code.fileReadNoSuchFile, .fileNoSuchFile])
    func missingIsToldByCode(_ code: CocoaError.Code) async {
        let rig = Rig()
        rig.writePackage("p")
        rig.files.failRead(of: Rig.shader("p"), with: CocoaError(code))

        let inventory = await rig.subject.packages()

        #expect(inventory.listings == [.broken(.package("p"), .sourceMissing)])
        #expect(inventory.watchSet.files == [Rig.manifest("p")])
    }

    @Test(
        "a package with several problems reports the first, manifest before shader, and a broken manifest does not stop the shader from being watched"
    )
    func firstProblemWins() async {
        let rig = Rig()
        rig.files.write(Rig.manifest("invalid"), "{")
        rig.files.write(Rig.shader("invalid"), Rig.validShader)
        rig.files.makeDirectory(Rig.directory("empty"))
        rig.files.write(Rig.manifest("both"), "[]")
        rig.files.failRead(of: Rig.shader("both"), with: CocoaError(.fileReadNoPermission))
        rig.files.write(Rig.shader("both"), Rig.validShader)

        let inventory = await rig.subject.packages()

        #expect(
            inventory.listings == [
                .broken(.package("both"), .manifestInvalid(message: "the manifest has the wrong type")),
                .broken(.package("empty"), .manifestMissing),
                .broken(.package("invalid"), .manifestInvalid(message: "not valid JSON")),
            ])
        #expect(
            inventory.watchSet.files == [
                Rig.manifest("both"), Rig.shader("both"),
                Rig.manifest("invalid"), Rig.shader("invalid"),
            ])
    }

    @Test("a broken package does not hide the ones beside it")
    func brokenBesideReady() async {
        let rig = Rig()
        rig.writePackage("a")
        rig.files.write(Rig.manifest("b"), "nope")
        rig.writePackage("c")

        let inventory = await rig.subject.packages()

        #expect(inventory.listings.map(\.id) == [.package("a"), .package("b"), .package("c")])
        #expect(inventory.listings.map(\.isReady) == [true, false, true])
    }

    // MARK: Logs

    @Test("a broken package is a developer line, one that exists and cannot be read an error, and a ready one neither")
    func logs() async {
        let rig = Rig()
        rig.writePackage("ready")
        rig.files.write(Rig.manifest("invalid"), "{")
        rig.files.write(Rig.shader("invalid"), Rig.validShader)
        rig.writePackage("locked")
        rig.files.failRead(of: Rig.shader("locked"), with: CocoaError(.fileReadNoPermission))

        _ = await rig.subject.packages()

        #expect(
            rig.developer.messages(in: .effect) == [#"package invalid is broken: manifestInvalid(message: "not valid JSON")"#])
        #expect(rig.errors.messages(in: .effect) == ["package locked: effect.metal could not be read: permission denied"])
    }

    // MARK: package(_:)

    @Test("one package is read afresh each time: an in-place save shows in the next answer, and the folder is not listed")
    func packageIsReadAfresh() async {
        let rig = Rig()
        rig.writePackage("glitch", shader: "// first\n")

        let first = await rig.subject.package(.package("glitch"))
        rig.files.write(Rig.shader("glitch"), "// second\n")
        let second = await rig.subject.package(.package("glitch"))

        #expect(first?.source == "// first\n")
        #expect(second?.source == "// second\n")
        #expect(rig.files.listings.values.isEmpty)
        #expect(rig.files.reads.values.count == 4)
    }

    @Test("a package that is broken answers as broken, the same as its listing does")
    func brokenPackageById() async {
        let rig = Rig()
        rig.files.write(Rig.manifest("p"), #"{"formatVersion": 3, "name": "P"}"#)

        let listing = await rig.subject.package(.package("p"))
        let inventory = await rig.subject.packages()

        #expect(listing == .broken(.package("p"), .unsupportedFormatVersion(3)))
        #expect(inventory.listings.first == listing)
    }

    @Test("an id the folder does not hold finds nothing, and asking never makes the folder")
    func unknownId() async {
        let rig = Rig()

        let absentFolder = await rig.subject.package(.package("glitch"))
        rig.files.makeDirectory(Rig.folder)
        let absentPackage = await rig.subject.package(.package("glitch"))
        rig.files.write("\(Rig.folder)/flat.lens", "a file")
        let aFile = await rig.subject.package(.package("flat"))

        #expect(absentFolder == nil)
        #expect(absentPackage == nil)
        #expect(aFile == nil)
        #expect(rig.files.createdDirectories.values.isEmpty)
        #expect(rig.files.reads.values.isEmpty)
    }

    @Test("a bundled id is not a package's: nothing is looked at, even when a package has that key")
    func bundledIdIsNotAPackage() async {
        let rig = Rig()
        rig.writePackage("Chromatic Grain")

        let listing = await rig.subject.package(.bundled("Chromatic Grain"))

        #expect(listing == nil)
        #expect(rig.files.reads.values.isEmpty)
        #expect(rig.files.listings.values.isEmpty)
    }

    @Test(
        "a key that is not one path component finds nothing and reads nothing: an id is joined into a path",
        arguments: ["", "a/b", "../outside", "/etc", "x/"])
    func keysThatLeaveTheFolder(_ key: String) async {
        // A package sits exactly where joining the key into the folder's path would look for it.
        let rig = Rig()
        rig.files.write("\(Rig.directory(key))/manifest.json", Rig.validManifest)
        rig.files.write("\(Rig.directory(key))/effect.metal", Rig.validShader)
        rig.files.makeDirectory(Rig.folder)

        let listing = await rig.subject.package(.package(key))

        #expect(listing == nil)
        #expect(rig.files.reads.values.isEmpty)
        #expect(rig.files.listings.values.isEmpty)
    }

    // MARK: openFolder()

    @Test("opening the folder shows exactly the effects folder, making it first when it is not there")
    func openMakesAndOpens() {
        let rig = Rig()

        rig.subject.openFolder()

        #expect(rig.files.createdDirectories.values == [Rig.folder])
        #expect(rig.workspace.opened.values == [Rig.folder])
    }

    @Test("opening a folder that is there makes nothing")
    func openExisting() {
        let rig = Rig()
        rig.files.makeDirectory(Rig.folder)

        rig.subject.openFolder()

        #expect(rig.files.createdDirectories.values.isEmpty)
        #expect(rig.workspace.opened.values == [Rig.folder])
    }

    @Test("a folder that cannot be made is not opened, and the error is logged")
    func openFolderThatCannotBeMade() {
        let rig = Rig()
        rig.files.failCreateDirectory(of: Rig.folder, with: CocoaError(.fileWriteNoPermission))

        rig.subject.openFolder()

        #expect(rig.workspace.opened.values.isEmpty)
        #expect(rig.errors.messages(in: .effect) == ["the effects folder cannot be made: permission denied"])
    }
}

extension EffectPackageListing {
    fileprivate var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    /// The shader of a ready package, `nil` for a broken one.
    fileprivate var source: String? {
        if case .ready(let package) = self { return package.source.source }
        return nil
    }
}
