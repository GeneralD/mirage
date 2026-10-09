import Dependencies
import Domain
import TestDoubles
import Testing

@testable import SurfacePoolDataSource

@Suite("SurfacePoolDataSource")
struct SurfacePoolDataSourceTests {
    private func makePool(capacity: Int = 3, gateway: FakeIOSurfaceGateway = FakeIOSurfaceGateway()) -> SurfacePoolDataSourceImpl {
        withDependencies {
            $0.ioSurfaceGateway = gateway
        } operation: {
            SurfacePoolDataSourceImpl(capacity: capacity)
        }
    }

    @Test("a fresh pool is empty and reports its capacity")
    func freshPool() {
        let pool = makePool(capacity: 5)
        #expect(pool.capacity == 5)
        #expect(pool.liveCount == 0)
    }

    @Test("a negative capacity is a pool that holds nothing")
    func negativeCapacity() throws {
        let pool = makePool(capacity: -2)
        #expect(pool.capacity == 0)
        #expect(try pool.allocate(.hd720) == nil)
        #expect(pool.adopt(FakeSurfaceHandle(id: 1), descriptor: .hd720) == nil)
    }

    @Test("adopt hands out the lowest free slot with generation 1 and resolves to the same handle")
    func adoptResolves() throws {
        let pool = makePool()
        let handle = FakeSurfaceHandle(id: 1)
        let token = try #require(pool.adopt(handle, descriptor: .hd720))
        #expect(token == SurfaceToken(index: 0, generation: 1))
        #expect(pool.handle(for: token) === handle)
        #expect(pool.descriptor(for: token) == .hd720)
        #expect(pool.liveCount == 1)
    }

    @Test("adopt on a full pool returns nil and leaves the pool untouched")
    func adoptFull() throws {
        let pool = makePool(capacity: 1)
        let first = try #require(pool.adopt(FakeSurfaceHandle(id: 1), descriptor: .hd720))
        #expect(pool.adopt(FakeSurfaceHandle(id: 2), descriptor: .hd720) == nil)
        #expect(pool.liveCount == 1)
        #expect(pool.handle(for: first) != nil)
    }

    @Test("allocate goes through the gateway and stores the resolved descriptor")
    func allocateUsesGateway() throws {
        let gateway = FakeIOSurfaceGateway()
        let pool = makePool(gateway: gateway)
        let token = try #require(try pool.allocate(.bgra(width: 8, height: 4)))
        #expect(gateway.createdCount == 1)
        #expect(pool.descriptor(for: token) == .bgra(width: 8, height: 4))
        #expect(pool.handle(for: token) is FakeSurfaceHandle)
    }

    @Test("allocate stores the descriptor the gateway resolved, not the one requested (the live gateway aligns the stride up)")
    func allocateStoresResolvedDescriptor() throws {
        let gateway = StrideRoundingGateway(rounding: 64)
        let pool = withDependencies {
            $0.ioSurfaceGateway = gateway
        } operation: {
            SurfacePoolDataSourceImpl(capacity: 1)
        }
        let requested = SurfaceDescriptor.bgra(width: 8, height: 4)
        let token = try #require(try pool.allocate(requested))
        let stored = try #require(pool.descriptor(for: token))
        #expect(stored != requested)
        #expect(stored.bytesPerRow == requested.bytesPerRow + 64)
        #expect(stored.width == requested.width)
        #expect(stored.height == requested.height)
    }

    @Test("allocate on a full pool returns nil without asking the gateway for a surface")
    func allocateFullSkipsGateway() throws {
        let gateway = FakeIOSurfaceGateway()
        let pool = makePool(capacity: 1, gateway: gateway)
        _ = try pool.allocate(.hd720)
        #expect(try pool.allocate(.hd720) == nil)
        #expect(gateway.createdCount == 1)
    }

    @Test("allocate rethrows the gateway's error and keeps the slot free")
    func allocateRethrows() throws {
        let gateway = FakeIOSurfaceGateway()
        gateway.failCreation(with: .allocationFailed)
        let pool = makePool(capacity: 1, gateway: gateway)
        #expect(throws: SurfaceError.allocationFailed) { try pool.allocate(.hd720) }
        #expect(pool.liveCount == 0)
        gateway.failCreation(with: nil)
        #expect(try pool.allocate(.hd720) != nil)
    }

    @Test("allocate(filledWith:) fills the surface through the gateway with the given byte")
    func allocateFilled() throws {
        let pool = makePool()
        let token = try #require(try pool.allocate(.hd720, filledWith: 0x7F))
        let handle = try #require(pool.handle(for: token) as? FakeSurfaceHandle)
        #expect(handle.lastFill == 0x7F)
        #expect(pool.liveCount == 1)
    }

    @Test("allocate(filledWith:) on a full pool returns nil and creates nothing")
    func allocateFilledFull() throws {
        let gateway = FakeIOSurfaceGateway()
        let pool = makePool(capacity: 1, gateway: gateway)
        _ = try pool.allocate(.hd720)
        #expect(try pool.allocate(.hd720, filledWith: 0) == nil)
        #expect(gateway.createdCount == 1)
    }

    @Test("a failing fill releases the slot, rethrows, and leaves liveCount unchanged")
    func allocateFilledRollsBack() throws {
        let gateway = FakeIOSurfaceGateway()
        let pool = makePool(capacity: 1, gateway: gateway)
        gateway.failFill(with: .allocationFailed)
        #expect(throws: SurfaceError.allocationFailed) { try pool.allocate(.hd720, filledWith: 0) }
        #expect(pool.liveCount == 0)
        gateway.failFill(with: nil)
        #expect(try pool.allocate(.hd720, filledWith: 0) != nil)
    }

    @Test("release frees the slot, and a second release of the same token is false")
    func releaseOnce() throws {
        let pool = makePool()
        let token = try #require(pool.adopt(FakeSurfaceHandle(id: 1), descriptor: .hd720))
        #expect(pool.release(token))
        #expect(pool.liveCount == 0)
        #expect(pool.handle(for: token) == nil)
        #expect(pool.descriptor(for: token) == nil)
        #expect(!pool.release(token))
    }

    @Test("a reused slot gets a new generation, so the old token stays dead")
    func reuseBumpsGeneration() throws {
        let pool = makePool(capacity: 1)
        let old = try #require(pool.adopt(FakeSurfaceHandle(id: 1), descriptor: .hd720))
        pool.release(old)
        let replacementHandle = FakeSurfaceHandle(id: 2)
        let replacement = try #require(pool.adopt(replacementHandle, descriptor: .hd720))
        #expect(replacement.index == old.index)
        #expect(replacement.generation == old.generation + 1)
        #expect(pool.handle(for: old) == nil)
        #expect(!pool.release(old))
        #expect(pool.handle(for: replacement) === replacementHandle)
    }

    @Test("a stale release changes nothing, including for a token that was never issued")
    func staleReleaseIsInert() throws {
        let pool = makePool()
        let live = try #require(pool.adopt(FakeSurfaceHandle(id: 1), descriptor: .hd720))
        for token in [
            SurfaceToken(index: -1, generation: 1),
            SurfaceToken(index: 3, generation: 1),
            SurfaceToken(index: 0, generation: 0),
            SurfaceToken(index: 0, generation: 2),
            SurfaceToken(index: 1, generation: 1),
        ] {
            #expect(!pool.release(token))
        }
        #expect(pool.liveCount == 1)
        #expect(pool.handle(for: live) != nil)
    }

    @Test("releaseAll clears every slot and generations keep counting up")
    func releaseAllKeepsCounting() throws {
        let pool = makePool(capacity: 2)
        let tokens = try (1...2).map { try #require(pool.adopt(FakeSurfaceHandle(id: UInt32($0)), descriptor: .hd720)) }
        pool.releaseAll()
        #expect(pool.liveCount == 0)
        #expect(tokens.allSatisfy { pool.handle(for: $0) == nil && !pool.release($0) })
        let next = try #require(pool.adopt(FakeSurfaceHandle(id: 3), descriptor: .hd720))
        #expect(next == SurfaceToken(index: 0, generation: 2))
    }

    @Test("releaseAll on an empty pool is a no-op")
    func releaseAllEmpty() {
        let pool = makePool()
        pool.releaseAll()
        #expect(pool.liveCount == 0)
    }
}

/// Delegates to `FakeIOSurfaceGateway` but reports a stride rounded up the way the
/// live gateway's alignment does, so the pool can be told apart from one that stores the request.
private struct StrideRoundingGateway: IOSurfaceGateway {
    let rounding: Int
    let base = FakeIOSurfaceGateway()

    func create(_ descriptor: SurfaceDescriptor) throws -> any SurfaceHandle { try base.create(descriptor) }
    func makeSendRight(_ surface: any SurfaceHandle) throws -> MachSendRight { try base.makeSendRight(surface) }
    func resolve(_ right: MachSendRight) throws -> any SurfaceHandle { try base.resolve(right) }
    func identifier(_ surface: any SurfaceHandle) -> UInt32 { base.identifier(surface) }
    func fill(_ surface: any SurfaceHandle, with byte: UInt8) throws { try base.fill(surface, with: byte) }

    func descriptor(_ surface: any SurfaceHandle) -> SurfaceDescriptor {
        let resolved = base.descriptor(surface)
        return SurfaceDescriptor(
            width: resolved.width, height: resolved.height, pixelFormat: resolved.pixelFormat, bytesPerRow: resolved.bytesPerRow + rounding)
    }
}
