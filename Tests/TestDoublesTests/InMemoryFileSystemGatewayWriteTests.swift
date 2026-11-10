import Domain
import Foundation
import TestDoubles
import TestSupport
import Testing

@Suite("InMemoryFileSystemGatewayWrite")
struct InMemoryFileSystemGatewayWriteTests {
    private struct Denied: Error, Equatable {}

    private let fileSystem = InMemoryFileSystemGateway()

    @Test("the bytes written read back with readData, and as text with readString when they are UTF-8")
    func writtenBytesReadBack() throws {
        fileSystem.makeDirectory("/effects/a.lens")

        try fileSystem.writeData(Data("色".utf8), to: "/effects/a.lens/manifest.json")
        try fileSystem.writeData(Data([0x89, 0x50, 0x00, 0xFF]), to: "/effects/a.lens/thumbnail.png")

        #expect(try fileSystem.readData("/effects/a.lens/manifest.json", upTo: 100) == Data("色".utf8))
        #expect(try fileSystem.readString("/effects/a.lens/manifest.json") == "色")
        #expect(try fileSystem.readData("/effects/a.lens/thumbnail.png", upTo: 100) == Data([0x89, 0x50, 0x00, 0xFF]))
    }

    @Test("writeData over a file replaces its content")
    func replacesFile() throws {
        fileSystem.write("/a/file", "v1")

        try fileSystem.writeData(Data("v2".utf8), to: "/a/file")

        #expect(try fileSystem.readString("/a/file") == "v2")
        #expect(try fileSystem.contentsOfDirectory("/a") == ["file"])
    }

    @Test("dataWrites holds the path and the data of every writeData in call order, failing ones included")
    func dataWritesRecorded() {
        fileSystem.makeDirectory("/a")
        fileSystem.failWriteData(of: "/a/denied", with: Denied())

        _ = try? fileSystem.writeData(Data([1]), to: "/a/first/")
        _ = try? fileSystem.writeData(Data([2]), to: "/a/denied")
        _ = try? fileSystem.writeData(Data([3]), to: "/nowhere/file")

        #expect(
            fileSystem.dataWrites.values == [
                .init(path: "/a/first", data: Data([1])),
                .init(path: "/a/denied", data: Data([2])),
                .init(path: "/nowhere/file", data: Data([3])),
            ], "a trailing slash is the same path")
    }

    @Test(
        "writeData into a missing directory throws a no-such-file error, and below a file or over a directory an unknown-write error, and the tree is left as it was"
    )
    func refusesTheTree() throws {
        fileSystem.write("/a/file", "x")
        fileSystem.makeDirectory("/a/dir")

        let missingParent = #expect(throws: CocoaError.self) { try fileSystem.writeData(Data([1]), to: "/a/missing/child") }
        let fileAbove = #expect(throws: CocoaError.self) { try fileSystem.writeData(Data([1]), to: "/a/file/child") }
        let throughMissing = #expect(throws: CocoaError.self) { try fileSystem.writeData(Data([1]), to: "/a/file/missing/child") }
        let overDirectory = #expect(throws: CocoaError.self) { try fileSystem.writeData(Data([1]), to: "/a/dir") }

        #expect(missingParent?.code == .fileNoSuchFile)
        #expect(fileAbove?.code == .fileWriteUnknown)
        #expect(throughMissing?.code == .fileWriteUnknown)
        #expect(overDirectory?.code == .fileWriteUnknown)
        #expect(!fileSystem.isDirectory("/a/missing"), "the parent is not made")
        #expect(try fileSystem.readString("/a/file") == "x")
        #expect(fileSystem.isDirectory("/a/dir"))
        #expect(try fileSystem.contentsOfDirectory("/a") == ["dir", "file"])
    }

    @Test("failWriteData throws its error for that path until nil clears it, and does not touch other paths")
    func failWriteDataScriptsTheError() throws {
        fileSystem.makeDirectory("/a")
        fileSystem.failWriteData(of: "/a/file", with: Denied())

        #expect(throws: Denied.self) { try fileSystem.writeData(Data([1]), to: "/a/file") }
        #expect(throws: Denied.self) { try fileSystem.writeData(Data([1]), to: "/a/file") }
        try fileSystem.writeData(Data([2]), to: "/a/other")
        let missing = #expect(throws: CocoaError.self) { try fileSystem.readData("/a/file", upTo: 8) }
        #expect(missing?.code == .fileNoSuchFile, "the refused write left nothing behind")

        fileSystem.failWriteData(of: "/a/file", with: nil)
        try fileSystem.writeData(Data([3]), to: "/a/file")
        #expect(try fileSystem.readData("/a/file", upTo: 8) == Data([3]))
    }
}
