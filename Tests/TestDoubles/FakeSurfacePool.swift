import Domain
import TestSupport

/// A `SurfacePool` with the real invariants (stale tokens never resolve, slots
/// reuse with a fresh generation) but no gateway behind it: `allocate` mints
/// `FakeSurfaceHandle`s directly.
///
/// Pixels never pass through the gateway here: an uploaded image is kept in its slot and read back by
/// `download`, and `setPixels` stands in for what the GPU wrote.
public final class FakeSurfacePool: SurfacePool, Sendable {
    /// One successful `upload`, in the order the uploads succeeded.
    public struct Upload: Sendable, Equatable {
        public let token: SurfaceToken
        public let image: StillImage
    }

    private struct Slot {
        var generation: UInt64 = 0
        var handle: (any SurfaceHandle)?
        var descriptor: SurfaceDescriptor?
        var image: StillImage?
    }

    private struct State {
        var slots: [Slot]
        var nextID: UInt32 = 1
        var allocateError: (any Error)?
        var fillError: (any Error)?
        var uploadsFail = false
        var downloadsFail = false

        func slot(for token: SurfaceToken) -> Slot? {
            guard slots.indices.contains(token.index) else { return nil }
            let slot = slots[token.index]
            guard slot.handle != nil, slot.generation == token.generation else { return nil }
            return slot
        }
    }

    public let capacity: Int
    /// Every successful `upload`, so a test can see what reached the pool.
    public let uploads = Collector<Upload>()
    private let state: Locked<State>

    public init(capacity: Int = 4) {
        self.capacity = capacity
        state = Locked(State(slots: Array(repeating: Slot(), count: capacity)))
    }

    public var liveCount: Int { state.current.slots.filter { $0.handle != nil }.count }

    public func failAllocation(with error: (any Error)?) {
        state.withLock { $0.allocateError = error }
    }

    /// Makes `allocate(_:filledWith:)` fail after the slot was taken, like a gateway fill error.
    public func failFill(with error: (any Error)?) {
        state.withLock { $0.fillError = error }
    }

    /// Makes every `upload` answer `false` and record nothing, while `fail` is `true`.
    public func failUploads(_ fail: Bool) {
        state.withLock { $0.uploadsFail = fail }
    }

    /// Makes every `download` answer `nil`, while `fail` is `true`.
    public func failDownloads(_ fail: Bool) {
        state.withLock { $0.downloadsFail = fail }
    }

    /// Stands in for what the GPU wrote: the next `download` of `token` returns `image`. A stale token changes nothing.
    public func setPixels(_ image: StillImage, of token: SurfaceToken) {
        state.withLock { state in
            guard state.slot(for: token) != nil else { return }
            state.slots[token.index].image = image
        }
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

    public func allocate(_ descriptor: SurfaceDescriptor, filledWith byte: UInt8) throws -> SurfaceToken? {
        guard let token = try allocate(descriptor) else { return nil }
        if let error = state.current.fillError {
            release(token)
            throw error
        }
        (handle(for: token) as? FakeSurfaceHandle)?.fill(with: byte)
        return token
    }

    public func handle(for token: SurfaceToken) -> (any SurfaceHandle)? {
        state.withLock { $0.slot(for: token)?.handle }
    }

    public func descriptor(for token: SurfaceToken) -> SurfaceDescriptor? {
        state.withLock { $0.slot(for: token)?.descriptor }
    }

    public func upload(_ image: StillImage, to token: SurfaceToken) -> Bool {
        let accepted = state.withLock { state -> Bool in
            guard !state.uploadsFail,
                let slot = state.slot(for: token),
                let descriptor = slot.descriptor,
                descriptor.width == image.width,
                descriptor.height == image.height,
                descriptor.pixelFormat == .bgra32,
                image.bgra.count == image.width * image.height * 4
            else { return false }
            state.slots[token.index].image = image
            return true
        }
        if accepted {
            uploads.append(Upload(token: token, image: image))
        }
        return accepted
    }

    /// The image last uploaded or set for the token; a surface nothing was put into reads as zeros of its size.
    public func download(from token: SurfaceToken) -> StillImage? {
        state.withLock { state -> StillImage? in
            guard !state.downloadsFail, let slot = state.slot(for: token), let descriptor = slot.descriptor else { return nil }
            return slot.image
                ?? StillImage(
                    width: descriptor.width, height: descriptor.height,
                    bgra: [UInt8](repeating: 0, count: descriptor.width * descriptor.height * 4))
        }
    }

    @discardableResult
    public func release(_ token: SurfaceToken) -> Bool {
        state.withLock { state in
            guard state.slot(for: token) != nil else { return false }
            state.slots[token.index].handle = nil
            state.slots[token.index].descriptor = nil
            state.slots[token.index].image = nil
            return true
        }
    }

    public func releaseAll() {
        state.withLock { state in
            state.slots = state.slots.map { Slot(generation: $0.generation) }
        }
    }
}
