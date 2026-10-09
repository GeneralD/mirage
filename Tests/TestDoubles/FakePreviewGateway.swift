import Dependencies
import Domain
import TestSupport

/// The layer `FakePreviewGateway` mints for a prepared target: remembers the
/// target and the context so a test can tell which attach a draw went to.
public final class FakePreviewLayerHandle: PreviewLayerHandle, Sendable {
    public let target: FakePreviewTargetHandle
    public let context: FakeGPUContextHandle

    init(target: FakePreviewTargetHandle, context: FakeGPUContextHandle) {
        self.target = target
        self.context = context
    }

    public var backing: AnyObject { self }
}

/// `PreviewGateway` as the test drives it: `prepare` mints a layer per call and
/// records it, every `draw` is recorded as a `Draw` and stays pending until the
/// test completes it with any `GPUCompletion`, in any order — exactly once, as
/// the live command buffer's completion handler runs. Handles must be the
/// fakes' (`FakePreviewTargetHandle`, `FakeGPUContextHandle`,
/// `FakeTextureHandle`, `FakeLibraryHandle`, `FakePreviewLayerHandle`); anything
/// else is refused before anything is recorded, with the live gateway's errors
/// in the live gateway's order.
public final class FakePreviewGateway: PreviewGateway, Sendable {
    public struct Draw: Sendable {
        public let id: Int
        public let texture: FakeTextureHandle
        public let kernel: FakeLibraryHandle
        public let layer: FakePreviewLayerHandle
        public let context: FakeGPUContextHandle
        /// The gateway that issued it: ids restart at 1 per instance, so the id alone cannot tell a stranger's draw.
        fileprivate let origin: ObjectIdentifier
    }

    private struct State {
        var nextID = 1
        var pending: [Int: @Sendable (GPUCompletion) -> Void] = [:]
        var prepareError: (any Error)?
        var drawError: (any Error)?
    }

    private let state = Locked(State())
    /// Every layer `prepare` minted, in order.
    public let prepared = Collector<FakePreviewLayerHandle>()
    /// Every draw handed in, in order, completed or not.
    public let draws = Collector<Draw>()

    public init() {}

    /// The draws not yet completed, in draw order.
    public var pending: [Draw] {
        let ids = state.current.pending
        return draws.values.filter { ids[$0.id] != nil }
    }

    public func failPrepare(with error: (any Error)?) {
        state.withLock { $0.prepareError = error }
    }

    public func failDraw(with error: (any Error)?) {
        state.withLock { $0.drawError = error }
    }

    public nonisolated func prepare(_ target: any PreviewTargetHandle, on context: any GPUContextHandle) throws -> any PreviewLayerHandle {
        // Same order as the live gateway: the target first, then the context.
        let fakeTarget = try (target as? FakePreviewTargetHandle).orThrow(PreviewError.foreignTarget)
        let fakeContext = try (context as? FakeGPUContextHandle).orThrow(GPUError.foreignHandle)
        if let error = state.current.prepareError { throw error }
        let layer = FakePreviewLayerHandle(target: fakeTarget, context: fakeContext)
        prepared.append(layer)
        return layer
    }

    public func draw(
        _ texture: any TextureHandle, with kernel: any LibraryHandle, into layer: any PreviewLayerHandle,
        on context: any GPUContextHandle, completion: @escaping @Sendable (GPUCompletion) -> Void
    ) throws {
        // Same order as the live gateway: context, kernel, texture, layer.
        let fakeContext = try (context as? FakeGPUContextHandle).orThrow(GPUError.foreignHandle)
        let fakeKernel = try (kernel as? FakeLibraryHandle).orThrow(GPUError.foreignHandle)
        let fakeTexture = try (texture as? FakeTextureHandle).orThrow(GPUError.foreignHandle)
        let fakeLayer = try (layer as? FakePreviewLayerHandle).orThrow(PreviewError.foreignTarget)
        let draw = try state.withLock { state in
            if let error = state.drawError { throw error }
            let id = state.nextID
            state.nextID += 1
            state.pending[id] = completion
            return Draw(id: id, texture: fakeTexture, kernel: fakeKernel, layer: fakeLayer, context: fakeContext, origin: ObjectIdentifier(self))
        }
        draws.append(draw)
    }

    /// Delivers `completion` to the draw's handler, once. `false` when the draw
    /// is unknown, came from another gateway, or was already completed — each
    /// is a bug in the test, and it is reported as one.
    @discardableResult
    public func complete(_ draw: Draw, with completion: GPUCompletion = GPUCompletion(gpuStart: 0, gpuEnd: 0, error: nil)) -> Bool {
        guard draw.origin == ObjectIdentifier(self) else {
            reportIssue("FakePreviewGateway: draw \(draw.id) was issued by another gateway")
            return false
        }
        guard let handler = state.withLock({ $0.pending.removeValue(forKey: draw.id) }) else {
            reportIssue("FakePreviewGateway: draw \(draw.id) completed twice or never drawn")
            return false
        }
        handler(completion)
        return true
    }
}
