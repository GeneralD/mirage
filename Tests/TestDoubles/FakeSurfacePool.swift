import Domain

/// A `SurfacePool` with the real invariants (stale tokens never resolve, slots
/// reuse with a fresh generation) but no gateway behind it: `allocate` mints
/// `FakeSurfaceHandle`s directly.
public final class FakeSurfacePool: SurfacePool, Sendable {
    private struct Slot {
        var generation: UInt64 = 0
        var handle: (any SurfaceHandle)?
        var descriptor: SurfaceDescriptor?
    }

    private struct State {
        var slots: [Slot]
        var nextID: UInt32 = 1
        var allocateError: (any Error)?

        func slot(for token: SurfaceToken) -> Slot? {
            guard slots.indices.contains(token.index) else { return nil }
            let slot = slots[token.index]
            guard slot.handle != nil, slot.generation == token.generation else { return nil }
            return slot
        }
    }

    public let capacity: Int
    private let state: Locked<State>

    public init(capacity: Int = 4) {
        self.capacity = capacity
        state = Locked(State(slots: Array(repeating: Slot(), count: capacity)))
    }

    public var liveCount: Int { state.current.slots.filter { $0.handle != nil }.count }

    public func failAllocation(with error: (any Error)?) {
        state.withLock { $0.allocateError = error }
    }

    public func adopt(_ handle: any SurfaceHandle, descriptor: SurfaceDescriptor) -> SurfaceToken? {
        state.withLock { state -> SurfaceToken? in
            guard let index = state.slots.firstIndex(where: { $0.handle == nil }) else { return nil }
            state.slots[index].generation += 1
            state.slots[index].handle = handle
            state.slots[index].descriptor = descriptor
            return SurfaceToken(index: index, generation: state.slots[index].generation)
        }
    }

    public func allocate(_ descriptor: SurfaceDescriptor) throws -> SurfaceToken? {
        let handle = try state.withLock { state -> FakeSurfaceHandle in
            if let error = state.allocateError { throw error }
            defer { state.nextID += 1 }
            return FakeSurfaceHandle(id: state.nextID, descriptor: descriptor)
        }
        return adopt(handle, descriptor: descriptor)
    }

    public func handle(for token: SurfaceToken) -> (any SurfaceHandle)? {
        state.withLock { $0.slot(for: token)?.handle }
    }

    public func descriptor(for token: SurfaceToken) -> SurfaceDescriptor? {
        state.withLock { $0.slot(for: token)?.descriptor }
    }

    @discardableResult
    public func release(_ token: SurfaceToken) -> Bool {
        state.withLock { state in
            guard state.slot(for: token) != nil else { return false }
            state.slots[token.index].handle = nil
            state.slots[token.index].descriptor = nil
            return true
        }
    }

    public func releaseAll() {
        state.withLock { state in
            state.slots = state.slots.map { Slot(generation: $0.generation) }
        }
    }
}
