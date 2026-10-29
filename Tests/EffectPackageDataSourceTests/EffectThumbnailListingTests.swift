import Dependencies
import Domain
import EffectPackageDataSource
import Foundation
import TestDoubles
import Testing

/// What a package's thumbnail lists as (#12), proven over `InMemoryFileSystemGateway`: a picture that can
/// be used is carried by the ready package and watched, and one that cannot costs the package its picture
/// and nothing else, with the reason in the log. The path rules themselves are `EffectThumbnailReadingTests`.
@Suite("EffectPackageDataSource thumbnails", .timeLimit(.minutes(1)))
struct EffectThumbnailListingTests {
    private typealias Rig = PackageRig

    /// The ready package `p` as the rig writes it, its manifest naming `thumbnail`, read with `picture`.
    private static func package(thumbnail: String?, picture: EffectThumbnail? = nil) -> EffectPackage {
        EffectPackage(
            id: .package("p"),
            manifest: EffectManifest(formatVersion: 1, name: "p", thumbnail: thumbnail),
            source: EffectSource(name: "p", source: Rig.validShader),
            thumbnail: picture)
    }

    // MARK: A picture that can be used

    @Test("a ready package carries the picture its manifest names, read once with the bound, and its file is watched")
    func pictureIsCarried() async {
        let rig = Rig()
        rig.writePackage("p", thumbnail: "thumbnail.png")
        rig.files.write(Rig.file("p", "thumbnail.png"), bytes: Rig.png)

        let inventory = await rig.subject.packages()

        let picture = EffectThumbnail(data: Rig.png, format: .png)
        #expect(inventory.listings == [.ready(Self.package(thumbnail: "thumbnail.png", picture: picture))])
        #expect(
            rig.files.dataReads.values == [.init(path: Rig.file("p", "thumbnail.png"), maxLength: EffectThumbnailReading.readLength)])
        #expect(rig.files.reads.values == [Rig.manifest("p"), Rig.shader("p"), Rig.file("p", "thumbnail.png")])
        #expect(
            inventory.watchSet
                == EffectWatchSet(
                    directories: [Rig.folder, Rig.directory("p")], files: [Rig.manifest("p"), Rig.shader("p"), Rig.file("p", "thumbnail.png")]))
        #expect(rig.errors.entries.values.isEmpty)
        #expect(rig.developer.entries.values.isEmpty)
    }

    @Test("a picture in a subdirectory is read from there, and every directory on its way is watched, as directories")
    func pictureInASubdirectory() async {
        let rig = Rig()
        rig.writePackage("p", thumbnail: "./images/small/thumb.JPG")
        rig.files.write(Rig.file("p", "images/small/thumb.JPG"), bytes: Rig.jpeg)

        let inventory = await rig.subject.packages()

        let picture = EffectThumbnail(data: Rig.jpeg, format: .jpeg)
        #expect(inventory.listings == [.ready(Self.package(thumbnail: "./images/small/thumb.JPG", picture: picture))])
        #expect(
            inventory.watchSet.directories == [Rig.folder, Rig.directory("p"), Rig.file("p", "images"), Rig.file("p", "images/small")])
        #expect(inventory.watchSet.files == [Rig.manifest("p"), Rig.shader("p"), Rig.file("p", "images/small/thumb.JPG")])
    }

    @Test("a manifest that names no thumbnail reads nothing more and watches nothing more")
    func noThumbnail() async {
        let rig = Rig()
        rig.writePackage("p")
        rig.files.write(Rig.file("p", "thumbnail.png"), bytes: Rig.png)

        let inventory = await rig.subject.packages()

        #expect(inventory.listings == [.ready(Self.package(thumbnail: nil))])
        #expect(rig.files.dataReads.values.isEmpty, "a file is not a thumbnail for its name alone")
        #expect(inventory.watchSet.files == [Rig.manifest("p"), Rig.shader("p")])
    }

    // MARK: A picture that cannot be used

    enum Sink: Sendable { case developer, error }

    struct Unusable: Sendable, CustomTestStringConvertible {
        let name: String
        let path: String
        let arrange: @Sendable (InMemoryFileSystemGateway) -> Void
        /// What the log says after `package p: thumbnail <the path, quoted>`.
        let reason: String
        let sink: Sink
        /// Whether the file was read at all: a path refused by its text never is.
        let read: Bool
        /// What the thumbnail adds to the package's watch set: directories below the package's, and the file.
        let watchedDirectories: [String]
        let watchedFiles: [String]

        var testDescription: String { name }
    }

    private static let thumbnail = Rig.file("p", "thumbnail.png")

    static let unusable: [Unusable] = [
        Unusable(
            name: "a path that leaves the package is not read, even when the file is there",
            path: "../thumbnail.png", arrange: { $0.write("\(Rig.folder)/thumbnail.png", bytes: Rig.png) },
            reason: "has a `..` component, which could leave the package", sink: .developer, read: false,
            watchedDirectories: [], watchedFiles: []),
        Unusable(
            name: "a `..` that would come back inside is refused all the same",
            path: "images/../thumbnail.png", arrange: { $0.write(Rig.file("p", "thumbnail.png"), bytes: Rig.png) },
            reason: "has a `..` component, which could leave the package", sink: .developer, read: false,
            watchedDirectories: [], watchedFiles: []),
        Unusable(
            name: "an absolute path is not read, even when the file is there",
            path: "/Users/test/thumbnail.png", arrange: { $0.write("/Users/test/thumbnail.png", bytes: Rig.png) },
            reason: "is an absolute path, not one relative to the package", sink: .developer, read: false,
            watchedDirectories: [], watchedFiles: []),
        Unusable(
            name: "an empty path", path: "", arrange: { _ in },
            reason: "is empty", sink: .developer, read: false, watchedDirectories: [], watchedFiles: []),
        Unusable(
            name: "a path with a NUL, quoted in the log as an escape", path: "thumbnail.png\u{0}.txt", arrange: { _ in },
            reason: "holds a NUL character", sink: .developer, read: false, watchedDirectories: [], watchedFiles: []),
        Unusable(
            name: "a name that is not an image's is not read, even when the file is a PNG",
            path: "thumbnail.gif", arrange: { $0.write(Rig.file("p", "thumbnail.gif"), bytes: Rig.png) },
            reason: "is not a .png, .jpg or .jpeg file", sink: .developer, read: false, watchedDirectories: [], watchedFiles: []),
        Unusable(
            name: "a file that is missing is not watched, its package directory is",
            path: "thumbnail.png", arrange: { _ in },
            reason: "is missing", sink: .developer, read: true, watchedDirectories: [], watchedFiles: []),
        Unusable(
            name: "a file missing from a directory that is there: the directory is watched, so creating the file is heard",
            path: "images/thumbnail.png", arrange: { $0.makeDirectory(Rig.file("p", "images")) },
            reason: "is missing", sink: .developer, read: true, watchedDirectories: [Rig.file("p", "images")], watchedFiles: []),
        Unusable(
            name: "a directory on its way that is missing is not watched: the package directory hears it made",
            path: "images/thumbnail.png", arrange: { _ in },
            reason: "is missing", sink: .developer, read: true, watchedDirectories: [], watchedFiles: []),
        Unusable(
            name: "a file is missing by readString's no-such-file code too, not only by FileHandle's",
            path: "thumbnail.png",
            arrange: {
                $0.write(Rig.file("p", "thumbnail.png"), bytes: Rig.png)
                $0.failRead(of: Rig.file("p", "thumbnail.png"), with: CocoaError(.fileReadNoSuchFile))
            },
            reason: "is missing", sink: .developer, read: true, watchedDirectories: [], watchedFiles: []),
        Unusable(
            name: "a file larger than 1 MiB is refused, read only one byte past the limit",
            path: "thumbnail.png",
            arrange: {
                let large = Rig.png + Data(count: EffectThumbnailReading.maximumByteCount + 100)
                $0.write(Rig.file("p", "thumbnail.png"), bytes: large)
            },
            reason: "is larger than 1048576 bytes", sink: .developer, read: true, watchedDirectories: [], watchedFiles: [thumbnail]),
        Unusable(
            name: "a file that is not an image",
            path: "thumbnail.png", arrange: { $0.write(Rig.file("p", "thumbnail.png"), "not a picture") },
            reason: "is not a PNG or JPEG image", sink: .developer, read: true, watchedDirectories: [], watchedFiles: [thumbnail]),
        Unusable(
            name: "an empty file",
            path: "thumbnail.png", arrange: { $0.write(Rig.file("p", "thumbnail.png"), bytes: Data()) },
            reason: "is not a PNG or JPEG image", sink: .developer, read: true, watchedDirectories: [], watchedFiles: [thumbnail]),
        Unusable(
            name: "a file that is there and cannot be read for lack of permission is an error",
            path: "thumbnail.png",
            arrange: {
                $0.write(Rig.file("p", "thumbnail.png"), bytes: Rig.png)
                $0.failRead(of: Rig.file("p", "thumbnail.png"), with: CocoaError(.fileReadNoPermission))
            },
            reason: "could not be read: permission denied", sink: .error, read: true, watchedDirectories: [], watchedFiles: [thumbnail]),
        Unusable(
            name: "a directory where the file should be is an error",
            path: "thumbnail.png", arrange: { $0.makeDirectory(Rig.file("p", "thumbnail.png")) },
            reason: "could not be read: Cocoa error \(CocoaError.Code.fileReadUnknown.rawValue)", sink: .error, read: true,
            watchedDirectories: [], watchedFiles: [thumbnail]),
        Unusable(
            name: "a read that fails with an error that is not a Cocoa error",
            path: "thumbnail.png", arrange: { $0.failRead(of: Rig.file("p", "thumbnail.png"), with: UnexpectedFailure()) },
            reason: "could not be read: unexpected error", sink: .error, read: true, watchedDirectories: [], watchedFiles: [thumbnail]),
    ]

    struct UnexpectedFailure: Error {}

    @Test("a thumbnail that cannot be used leaves the package ready without one, logs why, and watches what of it is there", arguments: unusable)
    func unusableThumbnail(_ row: Unusable) async {
        let rig = Rig()
        rig.writePackage("p", thumbnail: row.path)
        row.arrange(rig.files)

        let inventory = await rig.subject.packages()

        #expect(inventory.listings == [.ready(Self.package(thumbnail: row.path))])
        let line = "package p: thumbnail \(String(reflecting: row.path)) \(row.reason)"
        #expect(rig.developer.messages(in: .effect) == (row.sink == .developer ? [line] : []))
        #expect(rig.errors.messages(in: .effect) == (row.sink == .error ? [line] : []))
        #expect(rig.files.dataReads.values.map(\.maxLength) == (row.read ? [EffectThumbnailReading.readLength] : []))
        #expect(
            inventory.watchSet
                == EffectWatchSet(
                    directories: [Rig.folder, Rig.directory("p")] + row.watchedDirectories,
                    files: [Rig.manifest("p"), Rig.shader("p")] + row.watchedFiles))
    }

    @Test("the path is quoted in the log as Swift writes a string, so a NUL or a newline in it cannot pass for something else")
    func pathIsQuoted() async {
        let rig = Rig()
        rig.writePackage("p", thumbnail: "a\nb\u{0}.png")

        _ = await rig.subject.packages()

        #expect(rig.developer.messages(in: .effect) == [#"package p: thumbnail "a\nb\0.png" holds a NUL character"#])
    }

    @Test("a broken package's thumbnail is not read, and adds nothing to watch")
    func brokenPackageIsNotRead() async {
        let rig = Rig()
        rig.files.write(Rig.manifest("p"), Rig.manifestText(name: "p", thumbnail: "thumbnail.png"))
        rig.files.write(Rig.file("p", "thumbnail.png"), bytes: Rig.png)

        let inventory = await rig.subject.packages()

        #expect(inventory.listings == [.broken(.package("p"), .sourceMissing)])
        #expect(rig.files.dataReads.values.isEmpty)
        #expect(inventory.watchSet.files == [Rig.manifest("p")])
    }

    @Test("a thumbnail that is not a string is a manifest of the wrong shape: the package is broken, as for the author")
    func thumbnailOfTheWrongType() async {
        let rig = Rig()
        rig.files.write(Rig.manifest("p"), #"{"formatVersion": 1, "name": "p", "thumbnail": ["thumbnail.png"]}"#)
        rig.files.write(Rig.shader("p"), Rig.validShader)

        let inventory = await rig.subject.packages()

        #expect(inventory.listings == [.broken(.package("p"), .manifestInvalid(message: "\"thumbnail\" has the wrong type"))])
        #expect(rig.files.dataReads.values.isEmpty)
    }

    @Test("a package whose thumbnail cannot be used does not touch the one beside it")
    func neighboursAreKept() async {
        let rig = Rig()
        rig.writePackage("a", thumbnail: "missing.png")
        rig.writePackage("b", thumbnail: "thumbnail.png")
        rig.files.write(Rig.file("b", "thumbnail.png"), bytes: Rig.png)

        let inventory = await rig.subject.packages()

        #expect(inventory.listings.map(\.thumbnail) == [nil, EffectThumbnail(data: Rig.png, format: .png)])
    }

    // MARK: Read afresh

    @Test("the picture is read afresh: an edit in place, a file that appears and one that goes away all show in the next answer")
    func pictureIsReadAfresh() async {
        let rig = Rig()
        rig.writePackage("p", thumbnail: "thumbnail.png")

        let absent = await rig.subject.packages()
        rig.files.write(Rig.file("p", "thumbnail.png"), bytes: Rig.png)
        let appeared = await rig.subject.packages()
        rig.files.write(Rig.file("p", "thumbnail.png"), bytes: Rig.jpeg)
        let edited = await rig.subject.package(.package("p"))
        rig.files.remove(Rig.file("p", "thumbnail.png"))
        let removed = await rig.subject.packages()

        #expect(absent.listings.map(\.thumbnail) == [nil])
        #expect(absent.watchSet.files == [Rig.manifest("p"), Rig.shader("p")])
        #expect(appeared.listings.map(\.thumbnail) == [EffectThumbnail(data: Rig.png, format: .png)])
        #expect(appeared.watchSet.files == [Rig.manifest("p"), Rig.shader("p"), Rig.file("p", "thumbnail.png")], "watched from then on")
        #expect(edited?.thumbnail == EffectThumbnail(data: Rig.jpeg, format: .jpeg), "`package(_:)` reads it as the listing does")
        #expect(removed.listings.map(\.thumbnail) == [nil])
    }
}

extension EffectPackageListing {
    /// The picture of a ready package, `nil` for a broken one.
    fileprivate var thumbnail: EffectThumbnail? {
        guard case .ready(let package) = self else { return nil }
        return package.thumbnail
    }
}
