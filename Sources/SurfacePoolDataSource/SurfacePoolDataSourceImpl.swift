import Dependencies
import Domain

/// Slot and generation bookkeeping for the process's surfaces.
///
/// A token is valid only while its slot is occupied by the same generation it
/// was issued with, so a double release or a use after release resolves to
/// nothing instead of touching the slot's next tenant. Generations only ever
/// count up, `releaseAll` included.
///
/// Executor-confined: every mutation runs on FrameExecutor, so there is no lock
/// and no actor on the frame path.
public final class SurfacePoolDataSourceImpl: @unchecked Sendable {
    private struct Slot {
        /// Number of times this slot has been handed out; the current tenant's generation while occupied.
        var generation: UInt64 = 0
        var tenant: Tenant?
    }

    private struct Tenant {
        let handle: any SurfaceHandle
        let descriptor: SurfaceDescriptor
    }

    public let capacity: Int
    // Mutable by design: the slot table is the pool's state.
    private var slots: [Slot]
    @Dependency(\.ioSurfaceGateway) private var gateway

    public init(capacity: Int = 8) {
        let resolved = max(capacity, 0)
        self.capacity = resolved
        slots = Array(repeating: Slot(), count: resolved)
    }
}

extension SurfacePoolDataSourceImpl: SurfacePool {
    public var liveCount: Int { slots.filter { $0.tenant != nil }.count }

    public func adopt(_ handle: any SurfaceHandle, descriptor: SurfaceDescriptor) -> SurfaceToken? {
        guard let index = slots.firstIndex(where: { $0.tenant == nil }) else { return nil }
        slots[index].generation += 1
        slots[index].tenant = Tenant(handle: handle, descriptor: descriptor)
        return SurfaceToken(index: index, generation: slots[index].generation)
    }

    /// A full pool answers `nil` before the gateway is asked for anything, so a
    /// refused allocation never leaves an orphaned surface behind.
    public func allocate(_ descriptor: SurfaceDescriptor) throws -> SurfaceToken? {
        guard liveCount < capacity else { return nil }
        let handle = try gateway.create(descriptor)
        return adopt(handle, descriptor: gateway.descriptor(handle))
    }

    public func handle(for token: SurfaceToken) -> (any SurfaceHandle)? {
        tenant(for: token)?.handle
    }

    public func descriptor(for token: SurfaceToken) -> SurfaceDescriptor? {
        tenant(for: token)?.descriptor
    }

    @discardableResult
    public func release(_ token: SurfaceToken) -> Bool {
        guard tenant(for: token) != nil else { return false }
        slots[token.index].tenant = nil
        return true
    }

    public func releaseAll() {
        slots = slots.map { Slot(generation: $0.generation) }
    }
}

extension SurfacePoolDataSourceImpl {
    private func tenant(for token: SurfaceToken) -> Tenant? {
        guard slots.indices.contains(token.index), slots[token.index].generation == token.generation else { return nil }
        return slots[token.index].tenant
    }
}
