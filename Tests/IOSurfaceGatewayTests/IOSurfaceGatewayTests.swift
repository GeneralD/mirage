import Domain
import IOSurface
import TestDoubles
import Testing

@testable import IOSurfaceGateway

/// Real IOSurface, no GPU: the only suite that proves the OS calls do what the
/// thin Gateway claims (zero-copy identity across a Mach port is question Q1).
@Suite("IOSurfaceGateway")
struct IOSurfaceGatewayTests {
    private let gateway = IOSurfaceGatewayImpl()
    private let size = SurfaceDescriptor.bgra(width: 64, height: 48)

    private func firstByte(of surface: any SurfaceHandle) throws -> UInt8 {
        let raw = try #require(surface.backing as? IOSurface)
        IOSurfaceLock(raw, .readOnly, nil)
        defer { IOSurfaceUnlock(raw, .readOnly, nil) }
        return IOSurfaceGetBaseAddress(raw).assumingMemoryBound(to: UInt8.self).pointee
    }

    @Test("create reports the requested geometry with an aligned stride")
    func createDescriptor() throws {
        let surface = try gateway.create(size)
        let resolved = gateway.descriptor(surface)
        #expect(resolved.width == 64)
        #expect(resolved.height == 48)
        #expect(resolved.pixelFormat == .bgra32)
        #expect(resolved.bytesPerRow >= 64 * 4)
        #expect(surface.backing is IOSurface)
    }

    @Test("create rejects a descriptor IOSurface cannot allocate")
    func createFailure() {
        #expect(throws: SurfaceError.allocationFailed) {
            try gateway.create(.bgra(width: 0, height: 0))
        }
    }

    @Test("fill writes the byte into every byte of the allocation")
    func fillWritesEveryByte() throws {
        let surface = try gateway.create(size)
        try gateway.fill(surface, with: 0xAB)
        let raw = try #require(surface.backing as? IOSurface)
        IOSurfaceLock(raw, .readOnly, nil)
        defer { IOSurfaceUnlock(raw, .readOnly, nil) }
        let bytes = UnsafeBufferPointer(start: IOSurfaceGetBaseAddress(raw).assumingMemoryBound(to: UInt8.self), count: IOSurfaceGetAllocSize(raw))
        #expect(bytes.allSatisfy { $0 == 0xAB })
    }

    @Test("a send right resolves to the same surface: identical ID and shared pixels (zero-copy identity)")
    func zeroCopyIdentity() throws {
        let original = try gateway.create(size)
        let right = try gateway.makeSendRight(original)
        let resolved = try gateway.resolve(right)
        #expect(gateway.identifier(resolved) == gateway.identifier(original))
        #expect(gateway.identifier(original) != 0)
        // The lookup returns a new IOSurface wrapper object, so object identity (`===`) cannot hold; the
        // proof of "same pixels, no copy" is that a write through one handle is visible through the other.
        try gateway.fill(original, with: 0x5A)
        #expect(try firstByte(of: resolved) == 0x5A)
        try gateway.fill(resolved, with: 0xC3)
        #expect(try firstByte(of: original) == 0xC3)
    }

    @Test("a right that was already resolved fails to resolve again")
    func resolveTwice() throws {
        let right = try gateway.makeSendRight(try gateway.create(size))
        _ = try gateway.resolve(right)
        #expect(throws: SurfaceError.lookupFailed(portName: right.name)) {
            try gateway.resolve(right)
        }
    }

    @Test("a handle from another gateway is a foreign handle for every operation")
    func foreignHandle() {
        let foreign = FakeSurfaceHandle(id: 7)
        #expect(throws: SurfaceError.foreignHandle) { try gateway.makeSendRight(foreign) }
        #expect(throws: SurfaceError.foreignHandle) { try gateway.fill(foreign, with: 1) }
        #expect(gateway.identifier(foreign) == 0)
        #expect(gateway.descriptor(foreign) == .hd720)
    }
}
