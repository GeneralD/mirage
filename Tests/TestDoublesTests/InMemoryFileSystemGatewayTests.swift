import Domain
import Foundation
import TestDoubles
import TestSupport
import Testing

@Suite("InMemoryFileSystemGateway")
struct InMemoryFileSystemGatewayTests {
    private struct Denied: Error, Equatable {}

    private let fileSystem = InMemoryFileSystemGateway()

    @Test("write makes the file and the directories above it, and lists them by name, sorted")
    func writeMakesParents() throws {
        fileSystem.write("/effects/glitch.lens/manifest.json", "{}")
        fileSystem.write("/effects/glitch.lens/effect.metal", "kernel")
        fileSystem.write("/effects/blur.lens/manifest.json", "{}")

        #expect(try fileSystem.contentsOfDirectory("/effects") == ["blur.lens", "glitch.lens"])
        #expect(try fileSystem.contentsOfDirectory("/effects/glitch.lens") == ["effect.metal", "manifest.json"])
        #expect(try fileSystem.contentsOfDirectory("/") == ["effects"])
        #expect(fileSystem.isDirectory("/effects/glitch.lens"))
        #expect(!fileSystem.isDirectory("/effects/glitch.lens/effect.metal"), "a file is not a directory")
        #expect(try fileSystem.readString("/effects/glitch.lens/effect.metal") == "kernel")
    }

    @Test("write over a file is an in-place save: the content is replaced, the listing is unchanged")
    func writeReplaces() throws {
        fileSystem.write("/effects/a.lens/effect.metal", "v1")
        fileSystem.write("/effects/a.lens/effect.metal", "v2")
        #expect(try fileSystem.readString("/effects/a.lens/effect.metal") == "v2")
        #expect(try fileSystem.contentsOfDirectory("/effects/a.lens") == ["effect.metal"])
    }

    @Test("write over a directory is a mistake in the test: it is reported and the tree is left as it was")
    func writeOverADirectory() throws {
        fileSystem.write("/effects/a.lens/manifest.json", "{}")

        withKnownIssue("a directory cannot be written as a file") { fileSystem.write("/effects/a.lens", "x") }

        #expect(fileSystem.isDirectory("/effects/a.lens"), "still a directory")
        #expect(try fileSystem.contentsOfDirectory("/effects/a.lens") == ["manifest.json"])
        let readDirectory = #expect(throws: CocoaError.self) { try fileSystem.readString("/effects/a.lens") }
        #expect(readDirectory?.code == .fileReadUnknown, "and not a file as well")
    }

    @Test("write or makeDirectory below a file is reported and leaves the tree as it was: a path is never both a file and a directory")
    func nothingBelowAFile() throws {
        fileSystem.write("/a/file", "x")

        withKnownIssue("a file has nothing under it") { fileSystem.write("/a/file/child", "y") }
        withKnownIssue("a file has nothing under it") { fileSystem.makeDirectory("/a/file/sub/deeper") }

        #expect(!fileSystem.isDirectory("/a/file"), "the file did not become a directory")
        #expect(try fileSystem.readString("/a/file") == "x")
        #expect(try fileSystem.contentsOfDirectory("/a") == ["file"])
        #expect(throws: CocoaError.self) { try fileSystem.contentsOfDirectory("/a/file") }
        #expect(!fileSystem.isDirectory("/a/file/sub"))
    }

    @Test("makeDirectory over a file is reported and leaves the file; over a directory it is a no-op")
    func makeDirectoryOverAFile() throws {
        fileSystem.write("/a/file", "x")
        fileSystem.makeDirectory("/a")
        #expect(try fileSystem.contentsOfDirectory("/a") == ["file"], "a directory that is there stays, with what is in it")

        withKnownIssue("a file cannot be made a directory") { fileSystem.makeDirectory("/a/file") }

        #expect(!fileSystem.isDirectory("/a/file"))
        #expect(try fileSystem.readString("/a/file") == "x")
    }

    @Test("remove takes away a file, or a directory with everything under it, and nothing there is not an error")
    func removeFileOrTree() throws {
        fileSystem.write("/effects/a.lens/manifest.json", "{}")
        fileSystem.write("/effects/a.lens/effect.metal", "k")
        fileSystem.write("/effects/ab.lens/manifest.json", "{}")

        fileSystem.remove("/effects/a.lens/effect.metal")
        #expect(try fileSystem.contentsOfDirectory("/effects/a.lens") == ["manifest.json"])

        fileSystem.remove("/effects/a.lens")
        #expect(try fileSystem.contentsOfDirectory("/effects") == ["ab.lens"], "a sibling that shares the name's prefix stays")
        #expect(!fileSystem.isDirectory("/effects/a.lens"))

        fileSystem.remove("/effects/never-there")
        #expect(try fileSystem.contentsOfDirectory("/effects") == ["ab.lens"])
    }

    @Test("an atomic save is a remove then a write: between the two the directory is empty, afterwards the file is back")
    func atomicSave() throws {
        fileSystem.write("/effects/a.lens/effect.metal", "v1")
        fileSystem.remove("/effects/a.lens/effect.metal")
        #expect(try fileSystem.contentsOfDirectory("/effects/a.lens").isEmpty)
        fileSystem.write("/effects/a.lens/effect.metal", "v2")
        #expect(try fileSystem.readString("/effects/a.lens/effect.metal") == "v2")
    }

    @Test("makeDirectory makes the directory and its parents, and an empty one lists as empty")
    func makeDirectory() throws {
        fileSystem.makeDirectory("/support/app/Effects/")
        #expect(fileSystem.isDirectory("/support/app/Effects"), "a trailing slash names the same directory")
        #expect(fileSystem.isDirectory("/support/app"))
        #expect(try fileSystem.contentsOfDirectory("/support/app/Effects").isEmpty)
        #expect(fileSystem.isDirectory("/"), "the root is always there")
    }

    @Test("a path that is not there fails the way FileManager does, and a file is not a directory nor the reverse")
    func missingAndMismatched() {
        fileSystem.write("/a/file", "x")
        let missingListing = #expect(throws: CocoaError.self) { try fileSystem.contentsOfDirectory("/nope") }
        let missingRead = #expect(throws: CocoaError.self) { try fileSystem.readString("/nope") }
        let listFile = #expect(throws: CocoaError.self) { try fileSystem.contentsOfDirectory("/a/file") }
        let readDirectory = #expect(throws: CocoaError.self) { try fileSystem.readString("/a") }
        #expect(missingListing?.code == .fileReadNoSuchFile)
        #expect(missingRead?.code == .fileReadNoSuchFile)
        #expect(listFile?.code == .fileReadUnknown)
        #expect(readDirectory?.code == .fileReadUnknown)
    }

    @Test("failRead scripts the error of reading a file and of listing a directory until it is cleared")
    func failRead() throws {
        fileSystem.write("/effects/a.lens/manifest.json", "{}")
        fileSystem.write("/effects/b.lens/manifest.json", "{}")

        fileSystem.failRead(of: "/effects/a.lens/manifest.json", with: CocoaError(.fileReadNoPermission))
        fileSystem.failRead(of: "/effects/b.lens", with: Denied())

        let denied = #expect(throws: CocoaError.self) { try fileSystem.readString("/effects/a.lens/manifest.json") }
        #expect(denied?.code == .fileReadNoPermission)
        #expect(throws: Denied.self) { try fileSystem.contentsOfDirectory("/effects/b.lens") }
        #expect(try fileSystem.readString("/effects/b.lens/manifest.json") == "{}", "only the scripted path fails, not what is under it")
        #expect(fileSystem.isDirectory("/effects/b.lens"), "isDirectory does not throw and keeps answering from the tree")

        fileSystem.failRead(of: "/effects/a.lens/manifest.json", with: nil)
        fileSystem.failRead(of: "/effects/b.lens", with: nil)
        #expect(try fileSystem.readString("/effects/a.lens/manifest.json") == "{}")
        #expect(try fileSystem.contentsOfDirectory("/effects/b.lens") == ["manifest.json"])
    }

    @Test("failRead stands for a vanished or half-written file too: the scripted error wins over a path that is not there")
    func failReadOfAMissingPath() {
        fileSystem.failRead(of: "/effects/gone.lens/effect.metal", with: Denied())
        #expect(throws: Denied.self) { try fileSystem.readString("/effects/gone.lens/effect.metal") }
    }

    @Test(
        "createDirectory makes the directory and its parents, may be repeated, and refuses a file in the way, on the path or above it, as FileManager does"
    )
    func createDirectory() throws {
        try fileSystem.createDirectory("/support/app/Effects")
        try fileSystem.createDirectory("/support/app/Effects")
        #expect(fileSystem.isDirectory("/support/app/Effects"))

        fileSystem.write("/support/file", "x")
        let inTheWay = #expect(throws: CocoaError.self) { try fileSystem.createDirectory("/support/file") }
        #expect(inTheWay?.code == .fileWriteFileExists)

        let aboveIt = #expect(throws: CocoaError.self) { try fileSystem.createDirectory("/support/file/sub") }
        #expect(aboveIt?.code == .fileWriteUnknown, "a file above the path is in the way as well, with FileManager's code for it")
        #expect(!fileSystem.isDirectory("/support/file"), "and the tree is as it was")
        #expect(!fileSystem.isDirectory("/support/file/sub"))
    }

    @Test("failCreateDirectory scripts the error of making a directory until it is cleared")
    func failCreateDirectory() throws {
        fileSystem.failCreateDirectory(of: "/support/app/Effects", with: CocoaError(.fileWriteNoPermission))
        let denied = #expect(throws: CocoaError.self) { try fileSystem.createDirectory("/support/app/Effects") }
        #expect(denied?.code == .fileWriteNoPermission)
        #expect(!fileSystem.isDirectory("/support/app/Effects"), "nothing was made")

        fileSystem.failCreateDirectory(of: "/support/app/Effects", with: nil)
        try fileSystem.createDirectory("/support/app/Effects")
        #expect(fileSystem.isDirectory("/support/app/Effects"))
    }

    @Test("every listing, read and createDirectory is recorded in call order, failing ones included")
    func callsAreRecorded() throws {
        fileSystem.write("/effects/a.lens/manifest.json", "{}")
        _ = try? fileSystem.contentsOfDirectory("/effects/")
        _ = try? fileSystem.contentsOfDirectory("/nope")
        _ = try? fileSystem.readString("/effects/a.lens/manifest.json")
        _ = try? fileSystem.readString("/effects/a.lens/effect.metal")
        _ = try? fileSystem.readData("/effects/a.lens/thumbnail.png/", upTo: 9)
        try fileSystem.createDirectory("/effects")

        #expect(fileSystem.listings.values == ["/effects", "/nope"], "a trailing slash is the same path")
        #expect(
            fileSystem.reads.values == ["/effects/a.lens/manifest.json", "/effects/a.lens/effect.metal", "/effects/a.lens/thumbnail.png"],
            "a read as bytes is a read")
        #expect(fileSystem.dataReads.values == [.init(path: "/effects/a.lens/thumbnail.png", maxLength: 9)])
        #expect(fileSystem.createdDirectories.values == ["/effects"])
    }

    // MARK: Bytes

    @Test("a file holds bytes: text is stored as UTF-8, and bytes read back as written, the first maxLength of them")
    func bytesReadBack() throws {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF])
        fileSystem.write("/effects/a.lens/thumbnail.png", bytes: bytes)
        fileSystem.write("/effects/a.lens/manifest.json", "色")

        #expect(try fileSystem.readData("/effects/a.lens/thumbnail.png", upTo: 100) == bytes, "a shorter file is read whole")
        #expect(try fileSystem.readData("/effects/a.lens/thumbnail.png", upTo: 6) == bytes)
        #expect(try fileSystem.readData("/effects/a.lens/thumbnail.png", upTo: 2) == Data([0x89, 0x50]), "a longer one only that far")
        #expect(try fileSystem.readData("/effects/a.lens/manifest.json", upTo: 10) == Data("色".utf8))
        #expect(try fileSystem.contentsOfDirectory("/effects/a.lens") == ["manifest.json", "thumbnail.png"])
    }

    @Test("an empty file reads as no bytes, and as an empty string")
    func emptyFile() throws {
        fileSystem.write("/a/empty", bytes: Data())
        #expect(try fileSystem.readData("/a/empty", upTo: 4).isEmpty)
        #expect(try fileSystem.readString("/a/empty").isEmpty)
    }

    @Test("bytes that are not UTF-8 cannot be read as text, with the code the live gateway raises; as bytes they can")
    func bytesThatAreNotText() throws {
        fileSystem.write("/a/bad", bytes: Data([0xC3, 0x28]))

        let error = #expect(throws: CocoaError.self) { try fileSystem.readString("/a/bad") }

        #expect(error?.code == .fileReadCorruptFile)
        #expect(try fileSystem.readData("/a/bad", upTo: 8) == Data([0xC3, 0x28]))
    }

    @Test("reading bytes fails as the live gateway's does: a missing path with `FileHandle`'s code, a directory, and a scripted error")
    func readDataFailures() {
        fileSystem.makeDirectory("/a/dir")
        fileSystem.write("/a/locked", bytes: Data([1]))
        fileSystem.failRead(of: "/a/locked", with: CocoaError(.fileReadNoPermission))

        let missing = #expect(throws: CocoaError.self) { try fileSystem.readData("/a/nope", upTo: 1) }
        let directory = #expect(throws: CocoaError.self) { try fileSystem.readData("/a/dir", upTo: 1) }
        let locked = #expect(throws: CocoaError.self) { try fileSystem.readData("/a/locked", upTo: 1) }

        #expect(missing?.code == .fileNoSuchFile, "not readString's fileReadNoSuchFile: FileHandle raises this one")
        #expect(directory?.code == .fileReadUnknown)
        #expect(locked?.code == .fileReadNoPermission)
    }

    @Test("bytes cannot be written over a directory or below a file: reported, and the tree is left as it was")
    func bytesFollowTheTreeRules() throws {
        fileSystem.makeDirectory("/a/dir")
        fileSystem.write("/a/file", "x")

        withKnownIssue("a directory cannot be written as a file") { fileSystem.write("/a/dir", bytes: Data([1])) }
        withKnownIssue("a file has nothing under it") { fileSystem.write("/a/file/child", bytes: Data([1])) }

        #expect(fileSystem.isDirectory("/a/dir"))
        #expect(try fileSystem.readString("/a/file") == "x")
        #expect(try fileSystem.contentsOfDirectory("/a") == ["dir", "file"])
    }
}
