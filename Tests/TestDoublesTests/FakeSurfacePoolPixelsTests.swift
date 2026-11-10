import Domain
import TestDoubles
import Testing

@Suite("Fake surface pool pixels")
struct FakeSurfacePoolPixelsTests {
    private let pool = FakeSurfacePool()
    private let descriptor = SurfaceDescriptor.bgra(width: 2, height: 2)
    private static let picture = StillImage(width: 2, height: 2, bgra: (1...16).map { UInt8($0) })
    private static let blank = StillImage(width: 2, height: 2, bgra: [UInt8](repeating: 0, count: 16))

    @Test("an upload of the right size is remembered by its slot and recorded in uploads")
    func uploadIsRemembered() throws {
        let token = try #require(try pool.allocate(descriptor))
        #expect(pool.upload(Self.picture, to: token))
        #expect(pool.download(from: token) == Self.picture)
        #expect(pool.uploads.count == 1)
        #expect(pool.uploads.values.map(\.token) == [token])
        #expect(pool.uploads.values.map(\.image) == [Self.picture])
    }

    @Test("a download of a surface nothing was put into is an image of zeros with the surface's width and height")
    func freshSurfaceDownloadsZeros() throws {
        let token = try #require(try pool.allocate(descriptor))
        #expect(pool.download(from: token) == Self.blank)
    }

    @Test("setPixels makes the next download return that image, and records no upload")
    func setPixelsIsDownloaded() throws {
        let token = try #require(try pool.allocate(descriptor))
        pool.setPixels(Self.picture, of: token)
        #expect(pool.download(from: token) == Self.picture)
        #expect(pool.uploads.count == 0)
    }

    @Test("setPixels on a stale token changes nothing, so the slot's next tenant still downloads zeros")
    func setPixelsOnStaleTokenIsInert() throws {
        let stale = try #require(try pool.allocate(descriptor))
        pool.release(stale)
        pool.setPixels(Self.picture, of: stale)
        let next = try #require(try pool.allocate(descriptor))
        #expect(pool.download(from: next) == Self.blank)
    }

    @Test("failUploads(true) makes upload answer false and record nothing, and failUploads(false) lets it through again")
    func failUploadsRefusesUploads() throws {
        let token = try #require(try pool.allocate(descriptor))
        pool.failUploads(true)
        #expect(!pool.upload(Self.picture, to: token))
        #expect(pool.uploads.count == 0)
        #expect(pool.download(from: token) == Self.blank)
        pool.failUploads(false)
        #expect(pool.upload(Self.picture, to: token))
    }

    @Test("failDownloads(true) makes download answer nil while the uploaded image is still there")
    func failDownloadsRefusesDownloads() throws {
        let token = try #require(try pool.allocate(descriptor))
        #expect(pool.upload(Self.picture, to: token))
        pool.failDownloads(true)
        #expect(pool.download(from: token) == nil)
        pool.failDownloads(false)
        #expect(pool.download(from: token) == Self.picture)
    }

    @Test("an upload to a stale token or of the wrong size answers false and records nothing")
    func badUploadsRecordNothing() throws {
        let stale = try #require(try pool.allocate(descriptor))
        pool.release(stale)
        #expect(!pool.upload(Self.picture, to: stale))
        let live = try #require(try pool.allocate(descriptor))
        #expect(!pool.upload(StillImage(width: 3, height: 2, bgra: [UInt8](repeating: 1, count: 24)), to: live))
        #expect(!pool.upload(StillImage(width: 2, height: 2, bgra: [UInt8](repeating: 1, count: 15)), to: live))
        #expect(pool.uploads.count == 0)
    }

    @Test("a download of a stale token answers nil")
    func staleDownloadIsNil() throws {
        let token = try #require(try pool.allocate(descriptor))
        #expect(pool.upload(Self.picture, to: token))
        pool.release(token)
        #expect(pool.download(from: token) == nil)
    }

    @Test("release forgets the uploaded image, so a slot allocated again downloads as zeros")
    func releaseForgetsTheImage() throws {
        let token = try #require(try pool.allocate(descriptor))
        #expect(pool.upload(Self.picture, to: token))
        pool.release(token)
        let again = try #require(try pool.allocate(descriptor))
        #expect(pool.download(from: again) == Self.blank)
    }

    @Test("releaseAll forgets every uploaded image, so the slots allocated again download as zeros")
    func releaseAllForgetsTheImages() throws {
        let token = try #require(try pool.allocate(descriptor))
        #expect(pool.upload(Self.picture, to: token))
        pool.releaseAll()
        let again = try #require(try pool.allocate(descriptor))
        #expect(pool.download(from: again) == Self.blank)
    }
}
