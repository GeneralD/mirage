import Dependencies
import Domain
import TestDoubles
import Testing

@testable import SurfaceRepository

@Suite("SurfaceRepository pixels")
struct SurfaceRepositoryPixelsTests {
    private static let descriptor = SurfaceDescriptor.bgra(width: 2, height: 2)
    private static let picture = StillImage(width: 2, height: 2, bgra: (1...16).map { UInt8($0) })

    private func makeRepository(pool: FakeSurfacePool) -> SurfaceRepositoryImpl {
        withDependencies {
            $0.surfacePool = pool
        } operation: {
            SurfaceRepositoryImpl()
        }
    }

    @Test("upload leaves the image and its token once in the pool's uploads and returns the pool's answer")
    func uploadForwards() throws {
        let pool = FakeSurfacePool()
        let repository = makeRepository(pool: pool)
        let token = try #require(try repository.allocate(Self.descriptor))
        #expect(repository.upload(Self.picture, to: token))
        #expect(pool.uploads.count == 1)
        #expect(pool.uploads.values.map(\.token) == [token])
        #expect(pool.uploads.values.map(\.image) == [Self.picture])
    }

    @Test("upload answers false when the pool refuses the image, and records nothing")
    func uploadRefusedByPool() throws {
        let pool = FakeSurfacePool()
        pool.failUploads(true)
        let repository = makeRepository(pool: pool)
        let token = try #require(try repository.allocate(Self.descriptor))
        #expect(!repository.upload(Self.picture, to: token))
        #expect(pool.uploads.count == 0)
    }

    @Test("download returns the image the pool remembers for the token")
    func downloadForwards() throws {
        let pool = FakeSurfacePool()
        let repository = makeRepository(pool: pool)
        let token = try #require(try repository.allocate(Self.descriptor))
        #expect(repository.upload(Self.picture, to: token))
        #expect(repository.download(from: token) == Self.picture)
    }

    @Test("download answers nil when the pool answers nil")
    func downloadRefusedByPool() throws {
        let pool = FakeSurfacePool()
        let repository = makeRepository(pool: pool)
        let token = try #require(try repository.allocate(Self.descriptor))
        #expect(repository.upload(Self.picture, to: token))
        pool.failDownloads(true)
        #expect(repository.download(from: token) == nil)
    }

    @Test("upload to a stale token answers false and download from it answers nil")
    func staleTokenIsRefused() throws {
        let pool = FakeSurfacePool()
        let repository = makeRepository(pool: pool)
        let token = try #require(try repository.allocate(Self.descriptor))
        #expect(repository.release(token))
        #expect(!repository.upload(Self.picture, to: token))
        #expect(repository.download(from: token) == nil)
        #expect(pool.uploads.count == 0)
    }
}
