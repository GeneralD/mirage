import Dependencies
import Domain
import TestDoubles
import Testing

@testable import SurfaceRepository

@Suite("SurfaceRepository")
struct SurfaceRepositoryTests {
    private func makeRepository(pool: FakeSurfacePool) -> SurfaceRepositoryImpl {
        withDependencies {
            $0.surfacePool = pool
        } operation: {
            SurfaceRepositoryImpl()
        }
    }

    @Test("allocate forwards to the pool and returns its token")
    func allocateForwards() throws {
        let pool = FakeSurfacePool(capacity: 2)
        let repository = makeRepository(pool: pool)
        let token = try #require(try repository.allocate(.hd720))
        #expect(pool.handle(for: token) != nil)
        #expect(pool.descriptor(for: token) == .hd720)
        #expect(repository.liveCount == 1)
    }

    @Test("allocate forwards the exact descriptor it was given")
    func allocateForwardsDescriptor() throws {
        let pool = FakeSurfacePool(capacity: 2)
        let repository = makeRepository(pool: pool)
        let requested = SurfaceDescriptor.bgra(width: 3, height: 2)
        let token = try #require(try repository.allocate(requested))
        #expect(pool.descriptor(for: token) == requested)
        #expect(pool.descriptor(for: token) != .hd720)
    }

    @Test("allocate returns nil when the pool is full")
    func allocateFull() throws {
        let pool = FakeSurfacePool(capacity: 1)
        let repository = makeRepository(pool: pool)
        _ = try repository.allocate(.hd720)
        #expect(try repository.allocate(.hd720) == nil)
        #expect(repository.liveCount == 1)
    }

    @Test("allocate rethrows the pool's error")
    func allocateThrows() {
        let pool = FakeSurfacePool()
        pool.failAllocation(with: SurfaceError.allocationFailed)
        let repository = makeRepository(pool: pool)
        #expect(throws: SurfaceError.allocationFailed) {
            try repository.allocate(.hd720)
        }
        #expect(repository.liveCount == 0)
    }

    @Test("release forwards, reporting false for a stale token")
    func releaseForwards() throws {
        let pool = FakeSurfacePool()
        let repository = makeRepository(pool: pool)
        let token = try #require(try repository.allocate(.hd720))
        #expect(repository.release(token))
        #expect(repository.liveCount == 0)
        #expect(!repository.release(token))
        #expect(!repository.release(SurfaceToken(index: 99, generation: 1)))
    }

    @Test("releaseAll forwards and empties the pool")
    func releaseAllForwards() throws {
        let pool = FakeSurfacePool(capacity: 3)
        let repository = makeRepository(pool: pool)
        let tokens = try (0..<3).map { _ in try #require(try repository.allocate(.hd720)) }
        repository.releaseAll()
        #expect(repository.liveCount == 0)
        #expect(tokens.allSatisfy { pool.handle(for: $0) == nil })
    }
}
