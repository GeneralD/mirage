/// Pixel layouts the frame path understands. A closed set: the capture format,
/// the surface pool and the extension stream must agree on one of these, and
/// nothing converts between them (M0 pins everything to `bgra32`).
public enum PixelFormat: String, Sendable, Hashable, CaseIterable {
    /// 8-bit BGRA, single plane. CoreVideo's `kCVPixelFormatType_32BGRA`.
    case bgra32
}

extension PixelFormat {
    /// The FourCC CoreVideo / IOSurface use for this format ('BGRA' for `bgra32`).
    public var fourCC: UInt32 {
        switch self {
        case .bgra32: 0x4247_5241
        }
    }

    public var bytesPerPixel: Int {
        switch self {
        case .bgra32: 4
        }
    }

    /// The format for a CoreVideo FourCC, `nil` when it is not one we handle.
    public init?(fourCC: UInt32) {
        guard let match = Self.allCases.first(where: { $0.fourCC == fourCC }) else { return nil }
        self = match
    }
}
