import Foundation
import Testing

@testable import FileSystemGateway

/// Smoke of `writeData` on the live gateway against the real file system, under a UUID-named
/// temporary directory that each test removes. The codes pinned here are the ones
/// `InMemoryFileSystemGatewayWriteTests` answers with; the DataSource proves its behaviour against the fake.
@Suite("FileSystemGatewayWrite")
struct FileSystemGatewayWriteTests {
    private let gateway = FileSystemGatewayImpl()

    @Test("the bytes written read back the same with readData")
    func writtenBytesReadBack() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0xFF, 0xC3, 0x28])

        try gateway.writeData(bytes, to: scratch.appending("thumbnail.png"))

        #expect(try gateway.readData(scratch.appending("thumbnail.png"), upTo: 1_000) == bytes)
    }

    @Test("an existing file is replaced whole, so a shorter write leaves none of the earlier tail behind")
    func replacesWholeFile() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        try Data("a longer first version".utf8).write(to: URL(fileURLWithPath: scratch.appending("file")))

        try gateway.writeData(Data("short".utf8), to: scratch.appending("file"))

        #expect(try gateway.readData(scratch.appending("file"), upTo: 1_000) == Data("short".utf8))
    }

    @Test("empty data written makes an empty file")
    func emptyDataMakesEmptyFile() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }

        try gateway.writeData(Data(), to: scratch.appending("empty"))

        #expect(try gateway.contentsOfDirectory(scratch.path) == ["empty"])
        #expect(try gateway.readData(scratch.appending("empty"), upTo: 8).isEmpty)
    }

    @Test("writing into a missing directory throws a no-such-file error, and the directory is not made")
    func missingParentThrows() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }

        let error = #expect(throws: CocoaError.self) { try gateway.writeData(Data([1]), to: scratch.appending("missing/file")) }

        #expect(error?.code == .fileNoSuchFile)
        #expect(!gateway.isDirectory(scratch.appending("missing")))
    }

    @Test("writing over a directory throws an unknown-write error and leaves the directory as it is")
    func overDirectoryThrows() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        try FileManager.default.createDirectory(atPath: scratch.appending("dir"), withIntermediateDirectories: false)

        let error = #expect(throws: CocoaError.self) { try gateway.writeData(Data([1]), to: scratch.appending("dir")) }

        #expect(error?.code == .fileWriteUnknown)
        #expect(gateway.isDirectory(scratch.appending("dir")))
    }

    @Test("writing below a file throws an unknown-write error and leaves the file as it was")
    func belowFileThrows() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        try Data("kept".utf8).write(to: URL(fileURLWithPath: scratch.appending("file")))

        let error = #expect(throws: CocoaError.self) { try gateway.writeData(Data([1]), to: scratch.appending("file/child")) }

        #expect(error?.code == .fileWriteUnknown)
        #expect(try gateway.readString(scratch.appending("file")) == "kept")
    }

    @Test("after a successful write the directory lists only the file written, with no temporary file left beside it")
    func noTemporaryFileLeftBehind() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }

        try gateway.writeData(Data([1, 2, 3]), to: scratch.appending("written.bin"))

        #expect(try gateway.contentsOfDirectory(scratch.path) == ["written.bin"])
    }
}
