import Domain
import TestDoubles
import Testing

@Suite("Fake surface pixels")
struct FakeSurfacePixelsTests {
    private let gateway = FakeIOSurfaceGateway()
    private let descriptor = SurfaceDescriptor.bgra(width: 6, height: 4)

    @Test("a surface just created reads as descriptor.byteCount zeros")
    func freshSurfaceIsZeros() throws {
        let surface = try gateway.create(descriptor)
        let read = try gateway.readBytes(surface)
        #expect(read.count == descriptor.byteCount)
        #expect(read.allSatisfy { $0 == 0 })
    }

    @Test("fill with 9 makes every byte read back as 9")
    func fillReplacesEveryByte() throws {
        let surface = try gateway.create(descriptor)
        try gateway.fill(surface, with: 9)
        #expect(try gateway.readBytes(surface) == [UInt8](repeating: 9, count: descriptor.byteCount))
    }

    @Test("a write reads back as the same bytes")
    func writeReadsBackUnchanged() throws {
        let surface = try gateway.create(descriptor)
        let bytes = (0..<descriptor.byteCount).map { UInt8(truncatingIfNeeded: $0) }
        try gateway.writeBytes(bytes, to: surface)
        #expect(try gateway.readBytes(surface) == bytes)
    }

    @Test("a write one byte shorter than descriptor.byteCount throws sizeMismatch and keeps the contents")
    func shortWriteKeepsContents() throws {
        let surface = try gateway.create(descriptor)
        try gateway.fill(surface, with: 3)
        #expect(throws: SurfaceError.sizeMismatch(expected: descriptor.byteCount, actual: descriptor.byteCount - 1)) {
            try gateway.writeBytes([UInt8](repeating: 0x11, count: descriptor.byteCount - 1), to: surface)
        }
        #expect(try gateway.readBytes(surface) == [UInt8](repeating: 3, count: descriptor.byteCount))
    }

    @Test("a fill after a write wins, and a write after a fill wins")
    func fillAndWriteOrderDecidesTheContents() throws {
        let surface = try gateway.create(descriptor)
        try gateway.writeBytes([UInt8](repeating: 1, count: descriptor.byteCount), to: surface)
        try gateway.fill(surface, with: 9)
        #expect(try gateway.readBytes(surface) == [UInt8](repeating: 9, count: descriptor.byteCount))
        try gateway.writeBytes([UInt8](repeating: 4, count: descriptor.byteCount), to: surface)
        #expect(try gateway.readBytes(surface) == [UInt8](repeating: 4, count: descriptor.byteCount))
    }

    @Test("a handle that is not a FakeSurfaceHandle is a foreign handle for both read and write")
    func nonFakeHandleIsForeign() {
        let stranger = StrangerSurfaceHandle()
        #expect(throws: SurfaceError.foreignHandle) { try gateway.readBytes(stranger) }
        #expect(throws: SurfaceError.foreignHandle) { try gateway.writeBytes([0], to: stranger) }
    }
}

private final class StrangerSurfaceHandle: SurfaceHandle {
    var backing: AnyObject { self }
}
