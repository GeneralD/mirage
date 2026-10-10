import Domain
import IOSurface
import Testing

/// What the GPU suites share: the one fixed tolerance, a compute pass awaited on
/// its completion handler, and a surface's pixels read back on the CPU.
enum GPUSmokeSupport {
    /// One 8-bit step: the GPU rounds the unorm store, the reference rounds in
    /// Swift. Every GPU-vs-Swift comparison uses this value and no other.
    static let tolerance = 1

    /// The completion handler is the only clock: no sleeps, no polling.
    static func run(_ pass: ComputePass, on context: any GPUContextHandle, through gateway: some GPUGateway) async throws -> GPUCompletion {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try gateway.encodeAndCommit(pass, on: context) { continuation.resume(returning: $0) }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Row-major BGRA bytes of the surface, read under a read lock after the GPU is done.
    static func pixels(of surface: any SurfaceHandle) throws -> SurfacePixels {
        let raw = try #require(surface.backing as? IOSurface)
        IOSurfaceLock(raw, .readOnly, nil)
        defer { IOSurfaceUnlock(raw, .readOnly, nil) }
        let base = IOSurfaceGetBaseAddress(raw).assumingMemoryBound(to: UInt8.self)
        return SurfacePixels(
            bytes: Array(UnsafeBufferPointer(start: base, count: IOSurfaceGetAllocSize(raw))), stride: IOSurfaceGetBytesPerRow(raw))
    }

    /// The largest channel difference between two pixels.
    static func distance(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        zip(lhs, rhs).map { abs(Int($0) - Int($1)) }.max() ?? 0
    }
}

/// A BGRA surface's bytes as read back, with its row stride.
struct SurfacePixels {
    let bytes: [UInt8]
    let stride: Int

    /// `[B, G, R, A]` at `(x, y)`.
    func pixel(x: Int, y: Int) -> [UInt8] {
        (0..<4).map { bytes[y * stride + x * 4 + $0] }
    }
}
