import Dependencies
import Domain
import TestDoubles
import Testing

@testable import SurfacePoolDataSource

@Suite("SurfacePoolDataSource pixels")
struct SurfacePoolPixelsTests {
    private func makePool(_ gateway: any IOSurfaceGateway) -> SurfacePoolDataSourceImpl {
        withDependencies {
            $0.ioSurfaceGateway = gateway
        } operation: {
            SurfacePoolDataSourceImpl(capacity: 3)
        }
    }

    /// A `width` by `height` picture whose bytes are 1, 2, 3 ... so a misplaced byte shows, and none is zero.
    private func picture(width: Int, height: Int) -> StillImage {
        StillImage(width: width, height: height, bgra: (0..<(width * height * 4)).map { UInt8(truncatingIfNeeded: $0 + 1) })
    }

    /// The bytes the gateway holds for the surface behind `token`, padding included.
    private func surfaceBytes(_ gateway: FakeIOSurfaceGateway, _ pool: SurfacePoolDataSourceImpl, _ token: SurfaceToken) throws -> [UInt8] {
        try gateway.readBytes(try #require(pool.handle(for: token)))
    }

    @Test("an upload of a 5 by 2 image into a 32 byte stride surface writes each row followed by 12 zeros")
    func uploadWritesPaddedRows() throws {
        let gateway = FakeIOSurfaceGateway()
        let pool = makePool(gateway)
        let token = try #require(try pool.allocate(SurfaceDescriptor(width: 5, height: 2, pixelFormat: .bgra32, bytesPerRow: 32)))
        let picture = picture(width: 5, height: 2)
        #expect(pool.upload(picture, to: token))
        let padding = [UInt8](repeating: 0, count: 12)
        let expected = Array(picture.bgra[0..<20]) + padding + Array(picture.bgra[20..<40]) + padding
        #expect(try surfaceBytes(gateway, pool, token) == expected)
    }

    @Test("an upload then a download returns the same 5 by 2 image from a 32 byte stride surface")
    func roundTripWithPadding() throws {
        let pool = makePool(FakeIOSurfaceGateway())
        let token = try #require(try pool.allocate(SurfaceDescriptor(width: 5, height: 2, pixelFormat: .bgra32, bytesPerRow: 32)))
        let picture = picture(width: 5, height: 2)
        #expect(pool.upload(picture, to: token))
        #expect(pool.download(from: token) == picture)
    }

    @Test("an upload then a download returns the same 4 by 2 image from a 16 byte stride surface with no padding")
    func roundTripWithoutPadding() throws {
        let pool = makePool(FakeIOSurfaceGateway())
        let token = try #require(try pool.allocate(.bgra(width: 4, height: 2)))
        let picture = picture(width: 4, height: 2)
        #expect(pool.upload(picture, to: token))
        #expect(pool.download(from: token) == picture)
    }

    @Test("a download drops the padding even when the surface's padding holds 0xFF")
    func downloadDropsPaddingContents() throws {
        let gateway = FakeIOSurfaceGateway()
        let pool = makePool(gateway)
        let token = try #require(try pool.allocate(SurfaceDescriptor(width: 5, height: 2, pixelFormat: .bgra32, bytesPerRow: 32)))
        let picture = picture(width: 5, height: 2)
        let filler = [UInt8](repeating: 0xFF, count: 12)
        let raw = Array(picture.bgra[0..<20]) + filler + Array(picture.bgra[20..<40]) + filler
        try gateway.writeBytes(raw, to: try #require(pool.handle(for: token)))
        #expect(pool.download(from: token) == picture)
    }

    @Test("an upload of an image of another width or height is refused and leaves the surface all zeros")
    func mismatchedSizeIsRefused() throws {
        let gateway = FakeIOSurfaceGateway()
        let pool = makePool(gateway)
        let token = try #require(try pool.allocate(SurfaceDescriptor(width: 5, height: 2, pixelFormat: .bgra32, bytesPerRow: 32)))
        #expect(!pool.upload(picture(width: 4, height: 2), to: token))
        #expect(!pool.upload(picture(width: 5, height: 3), to: token))
        #expect(try surfaceBytes(gateway, pool, token) == [UInt8](repeating: 0, count: 64))
    }

    @Test("an upload whose byte count is not width * height * 4 is refused and leaves the surface all zeros")
    func wrongByteCountIsRefused() throws {
        let gateway = FakeIOSurfaceGateway()
        let pool = makePool(gateway)
        let token = try #require(try pool.allocate(SurfaceDescriptor(width: 5, height: 2, pixelFormat: .bgra32, bytesPerRow: 32)))
        let short = StillImage(width: 5, height: 2, bgra: [UInt8](repeating: 7, count: 39))
        #expect(!pool.upload(short, to: token))
        #expect(try surfaceBytes(gateway, pool, token) == [UInt8](repeating: 0, count: 64))
    }

    @Test("an upload to a released token is refused, and a download of it answers nil")
    func staleTokenIsRefused() throws {
        let pool = makePool(FakeIOSurfaceGateway())
        let token = try #require(try pool.allocate(.bgra(width: 5, height: 2)))
        pool.release(token)
        #expect(!pool.upload(picture(width: 5, height: 2), to: token))
        #expect(pool.download(from: token) == nil)
    }

    @Test("a download of a surface nothing was uploaded to is an image of zeros with the surface's width and height")
    func freshSurfaceDownloadsZeros() throws {
        let pool = makePool(FakeIOSurfaceGateway())
        let token = try #require(try pool.allocate(SurfaceDescriptor(width: 5, height: 2, pixelFormat: .bgra32, bytesPerRow: 32)))
        #expect(pool.download(from: token) == StillImage(width: 5, height: 2, bgra: [UInt8](repeating: 0, count: 40)))
    }

    @Test("an upload the gateway refuses answers false, and a download the gateway refuses answers nil")
    func gatewayFailuresAreValues() throws {
        let pool = makePool(FailingPixelsGateway())
        let token = try #require(try pool.allocate(.bgra(width: 5, height: 2)))
        #expect(!pool.upload(picture(width: 5, height: 2), to: token))
        #expect(pool.download(from: token) == nil)
    }
}

/// Forwards everything to a `FakeIOSurfaceGateway` except the pixel reads and writes, which fail like a lock that cannot be taken.
private struct FailingPixelsGateway: IOSurfaceGateway {
    let base = FakeIOSurfaceGateway()

    func create(_ descriptor: SurfaceDescriptor) throws -> any SurfaceHandle { try base.create(descriptor) }
    func makeSendRight(_ surface: any SurfaceHandle) throws -> MachSendRight { try base.makeSendRight(surface) }
    func resolve(_ right: MachSendRight) throws -> any SurfaceHandle { try base.resolve(right) }
    func identifier(_ surface: any SurfaceHandle) -> UInt32 { base.identifier(surface) }
    func fill(_ surface: any SurfaceHandle, with byte: UInt8) throws { try base.fill(surface, with: byte) }
    func readBytes(_ surface: any SurfaceHandle) throws -> [UInt8] { throw SurfaceError.lockFailed(code: 1) }
    func writeBytes(_ bytes: [UInt8], to surface: any SurfaceHandle) throws { throw SurfaceError.lockFailed(code: 1) }

    func descriptor(_ surface: any SurfaceHandle) -> SurfaceDescriptor { base.descriptor(surface) }
}
