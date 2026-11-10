/// The size of a still image in pixels.
public struct StillImageSize: Sendable, Hashable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// A still image in the form the frame path takes: 8 bit BGRA, alpha premultiplied, rows packed
/// with no padding (one row is `width * 4` bytes), so `bgra` holds `width * height * 4` bytes.
/// The length is not checked here: Entity holds no logic, and the decoder that builds the image
/// is the one that guarantees it.
public struct StillImage: Sendable, Hashable {
    public let width: Int
    public let height: Int
    public let bgra: [UInt8]

    public init(width: Int, height: Int, bgra: [UInt8]) {
        self.width = width
        self.height = height
        self.bgra = bgra
    }
}

/// Why a still image could not be read or written. Closed so that every consumer enumerates it.
public enum StillImageProblem: Error, Sendable, Hashable {
    /// The file at `path` exists but cannot be read.
    case unreadable(path: String)
    /// The file's bytes are more than `limit`, so it is refused before it is decoded.
    case tooLarge(limit: Int)
    /// The file at `path` can be read but is not an image this build decodes.
    case notAnImage(path: String)
    /// The width or the height is below 1 or above the decoder's upper limit, which the decoder owns.
    case dimensionsOutOfRange(width: Int, height: Int)
    /// The image cannot be written to `path` (a missing folder, or no permission).
    case unwritable(path: String)
}
