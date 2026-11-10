import Domain
import TestDoubles
import Testing

@testable import IOSurfaceGateway

/// Real IOSurface, no GPU: the pixel bytes go through the OS lock and come back
/// unchanged, row padding included.
@Suite("IOSurface pixels")
struct IOSurfacePixelsTests {
    private let gateway = IOSurfaceGatewayImpl()

    @Test("a 64 × 48 surface returns the sequential bytes written to it")
    func sequentialBytesRoundTrip() throws {
        let surface = try gateway.create(.bgra(width: 64, height: 48))
        let count = gateway.descriptor(surface).byteCount
        let bytes = (0..<count).map { UInt8(truncatingIfNeeded: $0) }
        try gateway.writeBytes(bytes, to: surface)
        #expect(try gateway.readBytes(surface) == bytes)
    }

    @Test("a surface of width 6 with a padded stride reads back the padding bytes that were written")
    func paddedStrideRoundTrip() throws {
        let surface = try gateway.create(.bgra(width: 6, height: 4))
        let descriptor = gateway.descriptor(surface)
        #expect(descriptor.bytesPerRow > 24)
        #expect(descriptor.bytesPerRow.isMultiple(of: 16))
        let bytes = (0..<(descriptor.bytesPerRow * 4)).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 1) }
        try gateway.writeBytes(bytes, to: surface)
        let read = try gateway.readBytes(surface)
        #expect(read.count == descriptor.bytesPerRow * 4)
        #expect(read == bytes)
    }

    @Test("fill with 7 makes readBytes return only 7s, with the length bytesPerRow times height")
    func readAfterFillIsAllFilledByte() throws {
        let surface = try gateway.create(.bgra(width: 6, height: 4))
        try gateway.fill(surface, with: 7)
        let descriptor = gateway.descriptor(surface)
        let read = try gateway.readBytes(surface)
        #expect(read.count == descriptor.bytesPerRow * descriptor.height)
        #expect(read.allSatisfy { $0 == 7 })
    }

    @Test("a write one byte shorter than bytesPerRow times height throws sizeMismatch and keeps the pixels")
    func shortWriteKeepsPixels() throws {
        let surface = try gateway.create(.bgra(width: 6, height: 4))
        try gateway.fill(surface, with: 0x5A)
        let expected = gateway.descriptor(surface).byteCount
        #expect(throws: SurfaceError.sizeMismatch(expected: expected, actual: expected - 1)) {
            try gateway.writeBytes([UInt8](repeating: 0x11, count: expected - 1), to: surface)
        }
        #expect(try gateway.readBytes(surface).allSatisfy { $0 == 0x5A })
    }

    @Test("an empty write throws sizeMismatch and keeps the pixels")
    func emptyWriteKeepsPixels() throws {
        let surface = try gateway.create(.bgra(width: 6, height: 4))
        try gateway.fill(surface, with: 0x5A)
        let expected = gateway.descriptor(surface).byteCount
        #expect(throws: SurfaceError.sizeMismatch(expected: expected, actual: 0)) {
            try gateway.writeBytes([], to: surface)
        }
        #expect(try gateway.readBytes(surface).allSatisfy { $0 == 0x5A })
    }

    @Test("a handle from another gateway is a foreign handle for both read and write")
    func foreignHandle() {
        let foreign = FakeSurfaceHandle(id: 7)
        #expect(throws: SurfaceError.foreignHandle) { try gateway.readBytes(foreign) }
        #expect(throws: SurfaceError.foreignHandle) { try gateway.writeBytes([0], to: foreign) }
    }
}
