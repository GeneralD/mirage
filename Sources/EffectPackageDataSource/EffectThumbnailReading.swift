import Domain
import Foundation

/// How a manifest's `thumbnail` becomes an `EffectThumbnail`, or the reason it cannot (#12).
/// Pure functions: reading the file is `EffectPackageDataSourceImpl`'s. A thumbnail that cannot
/// be used costs the package its picture and nothing else: the package is still `.ready`, and
/// the reason is logged.
///
/// - **The path** is relative to the package directory and stays inside it, which is decided from
///   its text before anything is read. It is refused when it is empty, absolute (it starts with
///   `/`), holds a NUL, or has a `..` component, even one that would come back inside: the check
///   resolves nothing. `.` and empty components (`./thumbnail.png`, `images//a.png`) are dropped.
///   The text is split at the byte `/`, the one the file system splits at, and never by
///   `Character`, which would keep a `/` followed by a combining mark (`../\u{301}x`) inside one
///   component and so hide the `..` before it. A symbolic link inside the package is followed,
///   as it is for `manifest.json` and `effect.metal`: the bytes never leave the process, and they
///   must still be an image (below).
/// - **The name** ends in `.png`, `.jpg` or `.jpeg`, in any case. Anything else is refused before
///   it is read.
/// - **The bytes** are read `readLength` at most, one past `maximumByteCount`, so a file over the
///   limit is told from one at it without being read whole; and they begin with the PNG or the
///   JPEG signature, which decides the format: a `.png` that holds a JPEG is a JPEG, while a text
///   file, an empty one or anything else under an image name is refused. Nothing more of the image
///   is checked, so whoever decodes it must still expect it to fail.
public enum EffectThumbnailReading {
    /// The largest thumbnail kept: 1 MiB. A cell of the picker is a few hundred points wide, which a
    /// 512 × 512 PNG fills; the limit bounds what each package adds to what a listing reads and to
    /// what a published catalog state holds, so both grow with the number of packages and no faster.
    public static let maximumByteCount = 1 << 20

    /// How many bytes a thumbnail is read with.
    public static let readLength = maximumByteCount + 1

    /// Why a thumbnail cannot be used. The text is what the log shows after the path.
    public enum Problem: Error, Sendable, Hashable, CustomStringConvertible {
        case empty
        case absolute
        case nulCharacter
        case outsidePackage
        case unsupportedType
        case missing
        /// A directory is where the file should be.
        case directory
        /// The file is there and cannot be read; the reason is in words that do not depend on the locale.
        case unreadable(reason: String)
        case tooLarge
        case notAnImage

        public var description: String {
            switch self {
            case .empty: "is empty"
            case .absolute: "is an absolute path, not one relative to the package"
            case .nulCharacter: "holds a NUL character"
            case .outsidePackage: "has a `..` component, which could leave the package"
            case .unsupportedType: "is not a .png, .jpg or .jpeg file"
            case .missing: "is missing"
            case .directory: "is a directory, not a file"
            case .unreadable(let reason): "could not be read: \(reason)"
            case .tooLarge: "is larger than \(maximumByteCount) bytes"
            case .notAnImage: "is not a PNG or JPEG image"
            }
        }
    }

    /// The path's components below the package directory, or why the path is refused. A path that
    /// is accepted has at least one component, the file's name, last.
    public static func components(of path: String) -> Result<[String], Problem> {
        let bytes = Array(path.utf8)
        guard !bytes.isEmpty else { return .failure(.empty) }
        guard bytes.first != slash else { return .failure(.absolute) }
        guard !bytes.contains(0) else { return .failure(.nulCharacter) }
        let components = bytes.split(separator: slash).filter { !$0.elementsEqual([dot]) }
        guard !components.contains(where: { $0.elementsEqual([dot, dot]) }) else { return .failure(.outsidePackage) }
        // Each piece is whole UTF-8: the text was, and it was cut only at an ASCII byte.
        let names = components.map { String(decoding: $0, as: UTF8.self) }
        guard let name = names.last, hasImageExtension(name) else { return .failure(.unsupportedType) }
        return .success(names)
    }

    /// The thumbnail the bytes read from its file make, or why they make none.
    public static func thumbnail(from data: Data) -> Result<EffectThumbnail, Problem> {
        guard data.count <= maximumByteCount else { return .failure(.tooLarge) }
        guard let format = signatures.first(where: { data.starts(with: $0.bytes) })?.format else { return .failure(.notAnImage) }
        return .success(EffectThumbnail(data: data, format: format))
    }

    private static let slash = UInt8(ascii: "/")
    private static let dot = UInt8(ascii: ".")
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg"]

    /// The first bytes of each format: PNG's eight-byte signature, and JPEG's start-of-image marker
    /// followed by the first byte of the next marker. A signature is not a whole image: bytes that begin
    /// with one may still fail to decode.
    private static let signatures: [(format: EffectThumbnailFormat, bytes: [UInt8])] = [
        (.png, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        (.jpeg, [0xFF, 0xD8, 0xFF]),
    ]

    private static func hasImageExtension(_ name: String) -> Bool {
        name.lastIndex(of: ".").map { imageExtensions.contains(name[name.index(after: $0)...].lowercased()) } ?? false
    }
}
