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

    @Test("createDirectory makes the directory and its parents, may be repeated, and refuses a file in the way")
    func createDirectory() throws {
        try fileSystem.createDirectory("/support/app/Effects")
        try fileSystem.createDirectory("/support/app/Effects")
        #expect(fileSystem.isDirectory("/support/app/Effects"))

        fileSystem.write("/support/file", "x")
        let inTheWay = #expect(throws: CocoaError.self) { try fileSystem.createDirectory("/support/file") }
        #expect(inTheWay?.code == .fileWriteFileExists)
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
        try fileSystem.createDirectory("/effects")

        #expect(fileSystem.listings.values == ["/effects", "/nope"], "a trailing slash is the same path")
        #expect(fileSystem.reads.values == ["/effects/a.lens/manifest.json", "/effects/a.lens/effect.metal"])
        #expect(fileSystem.createdDirectories.values == ["/effects"])
    }
}
