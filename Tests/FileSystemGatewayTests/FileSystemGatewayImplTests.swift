import Foundation
import Testing

@testable import FileSystemGateway

/// Smoke of the live gateway against the real file system, under a UUID-named
/// temporary directory that each test removes. What a package is, and how a failure
/// is recovered from, is `EffectPackageDataSource`'s and is proven against the fake.
///
/// A failure is pinned by its `CocoaError` code, not only by "it throws": `InMemoryFileSystemGateway`
/// answers with these same codes, and a DataSource that tells a missing path from an unreadable one by
/// the error is proven against that fake, so the live gateway must agree with it on the shapes.
@Suite("FileSystemGatewayImpl")
struct FileSystemGatewayImplTests {
    private let gateway = FileSystemGatewayImpl()

    // MARK: contentsOfDirectory

    @Test("a listing holds the names, not the paths, of what the directory contains")
    func listsNames() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        try Data().write(to: URL(fileURLWithPath: scratch.appending("effect.metal")))
        try FileManager.default.createDirectory(atPath: scratch.appending("glow.lens"), withIntermediateDirectories: false)

        #expect(Set(try gateway.contentsOfDirectory(scratch.path)) == ["effect.metal", "glow.lens"])
    }

    @Test("an empty directory lists nothing")
    func listsNothingWhenEmpty() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }

        #expect(try gateway.contentsOfDirectory(scratch.path).isEmpty)
    }

    @Test("listing a path that does not exist throws a no-such-file error")
    func listingMissingThrows() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }

        let error = #expect(throws: CocoaError.self) { try gateway.contentsOfDirectory(scratch.appending("missing")) }

        #expect(error?.code == .fileReadNoSuchFile)
    }

    @Test("listing a file throws an unknown-read error, not a missing one")
    func listingFileThrows() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        try Data().write(to: URL(fileURLWithPath: scratch.appending("file")))

        let error = #expect(throws: CocoaError.self) { try gateway.contentsOfDirectory(scratch.appending("file")) }

        #expect(error?.code == .fileReadUnknown)
    }

    // MARK: isDirectory

    @Test("only a directory is a directory: not a file, not a path that is missing")
    func isDirectoryOnlyForDirectories() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        try Data().write(to: URL(fileURLWithPath: scratch.appending("file")))
        try FileManager.default.createDirectory(atPath: scratch.appending("dir"), withIntermediateDirectories: false)

        #expect(gateway.isDirectory(scratch.path))
        #expect(gateway.isDirectory(scratch.appending("dir")))
        #expect(!gateway.isDirectory(scratch.appending("file")))
        #expect(!gateway.isDirectory(scratch.appending("missing")))
    }

    @Test("a symlink to a directory is a directory, a symlink to a file or to nothing is not")
    func isDirectoryFollowsSymlinks() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        try FileManager.default.createDirectory(atPath: scratch.appending("dir"), withIntermediateDirectories: false)
        try Data().write(to: URL(fileURLWithPath: scratch.appending("file")))
        try FileManager.default.createSymbolicLink(atPath: scratch.appending("linked-dir"), withDestinationPath: scratch.appending("dir"))
        try FileManager.default.createSymbolicLink(atPath: scratch.appending("linked-file"), withDestinationPath: scratch.appending("file"))
        try FileManager.default.createSymbolicLink(atPath: scratch.appending("dangling"), withDestinationPath: scratch.appending("nowhere"))

        #expect(gateway.isDirectory(scratch.appending("linked-dir")))
        #expect(!gateway.isDirectory(scratch.appending("linked-file")))
        #expect(!gateway.isDirectory(scratch.appending("dangling")))
        #expect(try gateway.contentsOfDirectory(scratch.appending("linked-dir")).isEmpty)
    }

    // MARK: readString

    @Test("a file reads back as UTF-8 text, multibyte characters intact")
    func readsText() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let text = "{\"name\": \"色 and 🌈\"}\n"
        try Data(text.utf8).write(to: URL(fileURLWithPath: scratch.appending("manifest.json")))

        #expect(try gateway.readString(scratch.appending("manifest.json")) == text)
    }

    @Test("an empty file reads as an empty string")
    func readsEmptyFile() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        try Data().write(to: URL(fileURLWithPath: scratch.appending("empty")))

        #expect(try gateway.readString(scratch.appending("empty")).isEmpty)
    }

    @Test("reading a path that does not exist throws a no-such-file error")
    func readingMissingThrows() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }

        let error = #expect(throws: CocoaError.self) { try gateway.readString(scratch.appending("missing")) }

        #expect(error?.code == .fileReadNoSuchFile)
    }

    @Test("reading a directory throws an unknown-read error, not a missing one")
    func readingDirectoryThrows() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }

        let error = #expect(throws: CocoaError.self) { try gateway.readString(scratch.path) }

        #expect(error?.code == .fileReadUnknown)
    }

    @Test("bytes that are not UTF-8 throw a corrupt-file error instead of reading as garbled text")
    func readingInvalidUTF8Throws() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        try Data([0xC3, 0x28]).write(to: URL(fileURLWithPath: scratch.appending("bad")))

        // This is what the live gateway raises for such a file, and it is not a missing-file error; the fake raises the
        // same code for bytes written with `write(_:bytes:)` that are not UTF-8.
        let error = #expect(throws: CocoaError.self) { try gateway.readString(scratch.appending("bad")) }

        #expect(error?.code == .fileReadCorruptFile)
    }

    // MARK: readData

    @Test("bytes read back as written, whatever they are, when the file is shorter than the bound")
    func readsBytes() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0xFF, 0xC3, 0x28])
        try bytes.write(to: URL(fileURLWithPath: scratch.appending("thumbnail.png")))

        #expect(try gateway.readData(scratch.appending("thumbnail.png"), upTo: 1_000) == bytes)
        #expect(try gateway.readData(scratch.appending("thumbnail.png"), upTo: bytes.count) == bytes)
    }

    @Test("a file longer than the bound is read only that far")
    func readsOnlyUpToTheBound() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let bytes = Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0) })
        try bytes.write(to: URL(fileURLWithPath: scratch.appending("large")))

        #expect(try gateway.readData(scratch.appending("large"), upTo: 100_001) == bytes.prefix(100_001))
    }

    @Test("an empty file reads as no bytes")
    func readsEmptyFileAsNoBytes() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        try Data().write(to: URL(fileURLWithPath: scratch.appending("empty")))

        #expect(try gateway.readData(scratch.appending("empty"), upTo: 8).isEmpty)
    }

    @Test("reading the bytes of a path that does not exist throws FileHandle's no-such-file error, not readString's")
    func readingMissingBytesThrows() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }

        let error = #expect(throws: CocoaError.self) { try gateway.readData(scratch.appending("missing"), upTo: 8) }

        // `FileHandle` reports the missing file as `fileNoSuchFile` where `String(contentsOfFile:)` says
        // `fileReadNoSuchFile`; the DataSource takes either as missing, and the fake raises this one for `readData`.
        #expect(error?.code == .fileNoSuchFile)
    }

    @Test("reading the bytes of a directory throws, and not a missing-file error")
    func readingDirectoryBytesThrows() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }

        let error = #expect(throws: (any Error).self) { try gateway.readData(scratch.path, upTo: 8) }

        let code = (error as? CocoaError)?.code
        #expect(error != nil)
        #expect(code != .fileReadNoSuchFile && code != .fileNoSuchFile)
    }

    // MARK: createDirectory

    @Test("a directory is made together with every missing parent")
    func createsWithParents() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }

        try gateway.createDirectory(scratch.appending("a/b/c"))

        #expect(gateway.isDirectory(scratch.appending("a/b/c")))
    }

    @Test("a directory that is already there is left as it is, contents included")
    func existingDirectoryIsNotAnError() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        try gateway.createDirectory(scratch.appending("dir"))
        try Data("kept".utf8).write(to: URL(fileURLWithPath: scratch.appending("dir/file")))

        try gateway.createDirectory(scratch.appending("dir"))

        #expect(try gateway.readString(scratch.appending("dir/file")) == "kept")
    }

    @Test("a file in the way throws: a file-exists error at the path, an unknown-write error above it")
    func fileInTheWayThrows() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        try Data().write(to: URL(fileURLWithPath: scratch.appending("file")))

        let atThePath = #expect(throws: CocoaError.self) { try gateway.createDirectory(scratch.appending("file")) }
        let aboveIt = #expect(throws: CocoaError.self) { try gateway.createDirectory(scratch.appending("file/below")) }

        #expect(atThePath?.code == .fileWriteFileExists)
        #expect(aboveIt?.code == .fileWriteUnknown)
        #expect(!gateway.isDirectory(scratch.appending("file")))
    }
}
