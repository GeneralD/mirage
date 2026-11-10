/// `IOSurfaceGateway` live implementation, pixel-bytes half.
/// OS API: `IOSurfaceLock`, `IOSurfaceGetBaseAddress`, `IOSurfaceGetBytesPerRow`,
/// `IOSurfaceGetHeight`, `IOSurfaceUnlock`.
import Darwin
import Domain
import IOSurface

extension IOSurfaceGatewayImpl {
    public func readBytes(_ surface: any SurfaceHandle) throws -> [UInt8] {
        let raw = try surface.ioSurface()
        let status = IOSurfaceLock(raw, .readOnly, nil)
        try (status == KERN_SUCCESS).orThrow(SurfaceError.lockFailed(code: Int(status)))
        defer { _ = IOSurfaceUnlock(raw, .readOnly, nil) }
        let count = IOSurfaceGetBytesPerRow(raw) * IOSurfaceGetHeight(raw)
        return Array(UnsafeRawBufferPointer(start: IOSurfaceGetBaseAddress(raw), count: count))
    }

    public func writeBytes(_ bytes: [UInt8], to surface: any SurfaceHandle) throws {
        let raw = try surface.ioSurface()
        let count = IOSurfaceGetBytesPerRow(raw) * IOSurfaceGetHeight(raw)
        try (bytes.count == count).orThrow(SurfaceError.sizeMismatch(expected: count, actual: bytes.count))
        let status = IOSurfaceLock(raw, [], nil)
        try (status == KERN_SUCCESS).orThrow(SurfaceError.lockFailed(code: Int(status)))
        defer { _ = IOSurfaceUnlock(raw, [], nil) }
        _ = bytes.withUnsafeBytes { memcpy(IOSurfaceGetBaseAddress(raw), $0.baseAddress, count) }
    }
}
