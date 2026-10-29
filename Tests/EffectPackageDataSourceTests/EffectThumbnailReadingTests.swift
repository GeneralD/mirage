import Domain
import EffectPackageDataSource
import Foundation
import TestDoubles
import Testing

/// The pure half of reading a thumbnail: which paths are refused before anything is read, and
/// which bytes are kept. Every path row is one an author could write in a manifest.
@Suite("EffectThumbnailReading", .timeLimit(.minutes(1)))
struct EffectThumbnailReadingTests {
    typealias Problem = EffectThumbnailReading.Problem

    struct PathRow: Sendable, CustomTestStringConvertible {
        let name: String
        let path: String
        let expected: Result<[String], Problem>

        var testDescription: String { name }
    }

    static let pathRows: [PathRow] = [
        // What is read, and from where.
        PathRow(name: "a file beside the manifest", path: "thumbnail.png", expected: .success(["thumbnail.png"])),
        PathRow(name: "a file in a subdirectory", path: "images/small/thumb.jpg", expected: .success(["images", "small", "thumb.jpg"])),
        PathRow(name: "`.` and empty components are dropped", path: "./images//./thumb.jpeg", expected: .success(["images", "thumb.jpeg"])),
        PathRow(name: "a trailing slash is dropped", path: "thumb.png/", expected: .success(["thumb.png"])),
        PathRow(name: "the extension in any case", path: "Thumb.JpEg", expected: .success(["Thumb.JpEg"])),
        PathRow(name: "a name in any script, spaces included", path: "画像/サム ネイル.png", expected: .success(["画像", "サム ネイル.png"])),
        PathRow(name: "a `~` is a name like any other: nothing is expanded", path: "~/thumb.png", expected: .success(["~", "thumb.png"])),
        PathRow(name: "three dots are a name", path: ".../thumb.png", expected: .success(["...", "thumb.png"])),
        PathRow(
            name: "a component that only begins with two dots is a name: the bytes are compared, and the file system sees no `..` either",
            path: "..\u{301}/thumb.png", expected: .success(["..\u{301}", "thumb.png"])),
        PathRow(name: "a file whose whole name is the extension", path: ".png", expected: .success([".png"])),
        PathRow(name: "only the last extension counts", path: "thumb.tar.jpeg", expected: .success(["thumb.tar.jpeg"])),

        // What is refused, before anything is read.
        PathRow(name: "an empty path", path: "", expected: .failure(.empty)),
        PathRow(name: "an absolute path", path: "/Users/someone/thumb.png", expected: .failure(.absolute)),
        PathRow(name: "an absolute path is that even when it also climbs", path: "/../thumb.png", expected: .failure(.absolute)),
        PathRow(name: "a NUL, which a C path would end at", path: "thumb.png\u{0}.txt", expected: .failure(.nulCharacter)),
        PathRow(name: "a `..` that leaves the package", path: "../thumb.png", expected: .failure(.outsidePackage)),
        PathRow(name: "a `..` further down", path: "images/../../thumb.png", expected: .failure(.outsidePackage)),
        PathRow(name: "a `..` that would come back inside: nothing is resolved", path: "images/../thumb.png", expected: .failure(.outsidePackage)),
        PathRow(name: "a lone `..`", path: "..", expected: .failure(.outsidePackage)),
        PathRow(
            name: "a `/` that a combining mark follows still ends the `..` before it: the path is split at the byte",
            path: "../\u{301}thumb.png", expected: .failure(.outsidePackage)),
        PathRow(name: "a name with no extension", path: "thumbnail", expected: .failure(.unsupportedType)),
        PathRow(name: "an image type that is not PNG or JPEG", path: "thumb.gif", expected: .failure(.unsupportedType)),
        PathRow(name: "an image extension that is not the last one", path: "thumb.png.txt", expected: .failure(.unsupportedType)),
        PathRow(name: "a name that ends in a dot", path: "thumb.", expected: .failure(.unsupportedType)),
        PathRow(name: "the package directory itself", path: ".", expected: .failure(.unsupportedType)),
        PathRow(name: "a directory's name", path: "images/", expected: .failure(.unsupportedType)),
        PathRow(name: "only slashes are an absolute path", path: "//", expected: .failure(.absolute)),
    ]

    @Test("a path is split into what to read below the package, or refused for the reason that comes first", arguments: pathRows)
    func components(_ row: PathRow) {
        #expect(EffectThumbnailReading.components(of: row.path) == row.expected)
    }

    struct BytesRow: Sendable, CustomTestStringConvertible {
        let name: String
        let bytes: [UInt8]
        let expected: Result<EffectThumbnailFormat, Problem>

        var testDescription: String { name }
    }

    static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    static let bytesRows: [BytesRow] = [
        BytesRow(name: "a PNG", bytes: pngSignature + Array("IHDR".utf8), expected: .success(.png)),
        BytesRow(name: "the PNG signature alone", bytes: pngSignature, expected: .success(.png)),
        BytesRow(name: "a JFIF JPEG", bytes: [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10], expected: .success(.jpeg)),
        BytesRow(name: "an Exif JPEG", bytes: [0xFF, 0xD8, 0xFF, 0xE1, 0x12, 0x34], expected: .success(.jpeg)),
        BytesRow(name: "no bytes at all", bytes: [], expected: .failure(.notAnImage)),
        BytesRow(name: "text", bytes: Array("not a picture".utf8), expected: .failure(.notAnImage)),
        BytesRow(name: "a PNG signature cut short", bytes: Array(pngSignature.dropLast()), expected: .failure(.notAnImage)),
        BytesRow(
            name: "a PNG signature with one byte wrong", bytes: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0B], expected: .failure(.notAnImage)),
        BytesRow(name: "a JPEG start marker without the next marker", bytes: [0xFF, 0xD8], expected: .failure(.notAnImage)),
        BytesRow(name: "a GIF", bytes: Array("GIF89a".utf8), expected: .failure(.notAnImage)),
        BytesRow(name: "a signature that is not at the start", bytes: [0x00] + pngSignature, expected: .failure(.notAnImage)),
    ]

    @Test("bytes are kept as a thumbnail of the format their signature says, or refused", arguments: bytesRows)
    func signature(_ row: BytesRow) {
        let data = Data(row.bytes)
        #expect(EffectThumbnailReading.thumbnail(from: data) == row.expected.map { EffectThumbnail(data: data, format: $0) })
    }

    @Test("the format is the bytes', not the name's: what the reading is handed is only bytes")
    func formatComesFromTheBytes() {
        let jpeg = Data(EffectThumbnailFormat.jpeg.leadingBytes)
        #expect(EffectThumbnailReading.thumbnail(from: jpeg) == .success(EffectThumbnail(data: jpeg, format: .jpeg)))
    }

    @Test("a thumbnail of exactly 1 MiB is kept and one a byte larger is refused as too large, before its signature is looked at")
    func sizeLimit() {
        let limit = EffectThumbnailReading.maximumByteCount
        let atTheLimit = Data(Self.pngSignature + [UInt8](repeating: 0, count: limit - Self.pngSignature.count))
        let overTheLimit = atTheLimit + Data([0])

        #expect(limit == 1_048_576)
        #expect(EffectThumbnailReading.readLength == limit + 1, "one byte more than is kept is read, so too large is told from at the limit")
        #expect(EffectThumbnailReading.thumbnail(from: atTheLimit) == .success(EffectThumbnail(data: atTheLimit, format: .png)))
        #expect(EffectThumbnailReading.thumbnail(from: overTheLimit) == .failure(.tooLarge))
        #expect(EffectThumbnailReading.thumbnail(from: Data(count: limit + 1)) == .failure(.tooLarge), "not an image either, and too large first")
    }

    @Test("each problem reads as what the log shows after the path")
    func descriptions() {
        let texts: [(Problem, String)] = [
            (.empty, "is empty"),
            (.absolute, "is an absolute path, not one relative to the package"),
            (.nulCharacter, "holds a NUL character"),
            (.outsidePackage, "has a `..` component, which could leave the package"),
            (.unsupportedType, "is not a .png, .jpg or .jpeg file"),
            (.missing, "is missing"),
            (.unreadable("permission denied"), "could not be read: permission denied"),
            (.tooLarge, "is larger than 1048576 bytes"),
            (.notAnImage, "is not a PNG or JPEG image"),
        ]
        for (problem, text) in texts {
            #expect(problem.description == text)
        }
    }
}
