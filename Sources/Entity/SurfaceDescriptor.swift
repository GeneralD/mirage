/// The geometry and layout of one pixel surface. The camera output, the surface
/// pools on both sides of the process boundary and the extension's declared
/// stream format all carry one of these; a frame whose descriptor differs from
/// the stream's is dropped, never converted.
public struct SurfaceDescriptor: Sendable, Hashable {
    public let width: Int
    public let height: Int
    public let pixelFormat: PixelFormat
    public let bytesPerRow: Int

    public init(width: Int, height: Int, pixelFormat: PixelFormat, bytesPerRow: Int) {
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        self.bytesPerRow = bytesPerRow
    }
}

extension SurfaceDescriptor {
    /// Tightly packed BGRA (`bytesPerRow == width * 4`). As a request this is a
    /// minimum: IOSurface keeps an explicit stride exactly as given, so the live
    /// `IOSurfaceGateway` aligns it up for the OS before allocating (Metal binds
    /// only 16-byte-aligned rows) and reports the stride it allocated.
    public static func bgra(width: Int, height: Int) -> SurfaceDescriptor {
        SurfaceDescriptor(width: width, height: height, pixelFormat: .bgra32, bytesPerRow: width * 4)
    }

    /// The M0 format: 1280×720 BGRA, declared by the extension stream and
    /// requested from the camera unchanged.
    public static let hd720 = bgra(width: 1280, height: 720)

    public var byteCount: Int { bytesPerRow * height }

    /// Same dimensions and format; the row stride may differ (alignment padding).
    public func matchesGeometry(of other: SurfaceDescriptor) -> Bool {
        width == other.width && height == other.height && pixelFormat == other.pixelFormat
    }
}
