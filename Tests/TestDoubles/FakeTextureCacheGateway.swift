import Domain

/// A bound texture as `FakeTextureCacheGateway` mints it: remembers the surface
/// it wraps so a test can check which surface a pass read or wrote.
public final class FakeTextureHandle: TextureHandle, Sendable {
    public let surface: FakeSurfaceHandle

    init(surface: FakeSurfaceHandle) {
        self.surface = surface
    }

    public var backing: AnyObject { self }
}

/// `TextureCacheGateway` that counts. `bindCount == unbindCount` with
/// `doubleUnbindCount == 0` is the invariant `GPURenderDataSource` must keep;
/// a handle given back twice throws `GPUError.foreignHandle` (to the port it is
/// no longer one it issued) *and* is counted, so a test can tell a leak from a
/// double release. Foreign surfaces, contexts and textures are refused as the
/// live gateway refuses them.
public final class FakeTextureCacheGateway: TextureCacheGateway, Sendable {
    private struct State {
        var bound: Set<ObjectIdentifier> = []
        var bindCount = 0
        var unbindCount = 0
        var doubleUnbindCount = 0
        var bindError: GPUError?
    }

    private let state = Locked(State())

    public init() {}

    public var bindCount: Int { state.current.bindCount }
    public var unbindCount: Int { state.current.unbindCount }
    public var doubleUnbindCount: Int { state.current.doubleUnbindCount }
    /// Textures bound and not yet given back.
    public var liveCount: Int { state.current.bound.count }
    /// Every bind was unbound exactly once.
    public var isBalanced: Bool {
        let state = state.current
        return state.bindCount == state.unbindCount && state.doubleUnbindCount == 0
    }

    public func failBind(with error: GPUError?) {
        state.withLock { $0.bindError = error }
    }

    public func bind(_ surface: any SurfaceHandle, on context: any GPUContextHandle) throws -> any TextureHandle {
        _ = try (context as? FakeGPUContextHandle).orThrow(GPUError.foreignHandle)
        let fake = try (surface as? FakeSurfaceHandle).orThrow(SurfaceError.foreignHandle)
        return try state.withLock { state in
            if let error = state.bindError { throw error }
            let texture = FakeTextureHandle(surface: fake)
            state.bound.insert(ObjectIdentifier(texture))
            state.bindCount += 1
            return texture
        }
    }

    public func unbind(_ texture: any TextureHandle) throws {
        let fake = try (texture as? FakeTextureHandle).orThrow(GPUError.foreignHandle)
        try state.withLock { state in
            guard state.bound.remove(ObjectIdentifier(fake)) != nil else {
                state.doubleUnbindCount += 1
                throw GPUError.foreignHandle
            }
            state.unbindCount += 1
        }
    }
}
