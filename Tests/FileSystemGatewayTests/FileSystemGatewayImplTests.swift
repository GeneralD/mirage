import Foundation
import Testing

@testable import FileSystemGateway

/// Smoke of the live gateway against the real file system, under a UUID-named
/// temporary directory that each test removes. What a package is, and how a failure
/// is recovered from, is `EffectPackageDataSource`'s and is proven against the fake.
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

    @Test("listing a path that does not exist throws")
    func listingMissingThrows() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }

        #expect(throws: (any Error).self) { try gateway.contentsOfDirectory(scratch.appending("missing")) }
    }

    @Test("listing a file throws")
    func listingFileThrows() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        try Data().write(to: URL(fileURLWithPath: scratch.appending("file")))

        #expect(throws: (any Error).self) { try gateway.contentsOfDirectory(scratch.appending("file")) }
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

    @Test("reading a path that does not exist throws")
    func readingMissingThrows() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }

        #expect(throws: (any Error).self) { try gateway.readString(scratch.appending("missing")) }
    }

    @Test("reading a directory throws")
    func readingDirectoryThrows() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }

        #expect(throws: (any Error).self) { try gateway.readString(scratch.path) }
    }

    @Test("bytes that are not UTF-8 throw instead of reading as garbled text")
    func readingInvalidUTF8Throws() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        try Data([0xC3, 0x28]).write(to: URL(fileURLWithPath: scratch.appending("bad")))

        #expect(throws: (any Error).self) { try gateway.readString(scratch.appending("bad")) }
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

    @Test("a file in the way, at the path or above it, throws")
    func fileInTheWayThrows() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        try Data().write(to: URL(fileURLWithPath: scratch.appending("file")))

        #expect(throws: (any Error).self) { try gateway.createDirectory(scratch.appending("file")) }
        #expect(throws: (any Error).self) { try gateway.createDirectory(scratch.appending("file/below")) }
        #expect(!gateway.isDirectory(scratch.appending("file")))
    }
}
