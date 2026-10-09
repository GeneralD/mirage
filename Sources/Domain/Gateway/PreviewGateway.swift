import Dependencies

/// What a prepared preview target is drawn into (live: the view's `CAMetalLayer`,
/// whose `nextDrawable()` may be called off the main thread), in the shape of
/// the other handles: `backing` is the OS object as `AnyObject`, the gateway
/// that minted it casts it back and throws `PreviewError.foreignTarget` for
/// anything else. Holding it keeps the layer's drawable size in step with the
/// view (live: it holds the view's delegate, which the view holds weakly); it
/// owns nothing the OS must be told about, so it is given back by dropping it.
public protocol PreviewLayerHandle: AnyObject, Sendable {
    var backing: AnyObject { get }
}

/// Thin pass-through to the preview view and its drawables. Which frame is
/// drawn and when, the one-draw-in-flight cap, latest-wins, the preview
/// kernel's source and the surface's texture binding are `PreviewDataSource`'s.
public protocol PreviewGateway: Sendable {
    /// Points the target view at the context's device with BGRA8 drawables a
    /// compute kernel can write, stops it from drawing on its own and returns
    /// the layer `draw` writes to, sized to the view whenever the view resizes
    /// (a paused view no longer sizes its layer). On the main thread, because the target is a
    /// view. `PreviewError.foreignTarget` for a target this gateway cannot draw
    /// on, `GPUError.foreignHandle` for a context another gateway produced.
    @MainActor
    func prepare(_ target: any PreviewTargetHandle, on context: any GPUContextHandle) throws -> any PreviewLayerHandle

    /// Encodes one pass of `kernel` — `texture` at index 0, the layer's next
    /// drawable at index 1, whole 16 × 16 threadgroups covering the drawable
    /// (the kernel bounds-checks its `gid`) — presents the drawable and commits.
    /// `completion` runs exactly once with the raw outcome when the command
    /// buffer finishes, on the GPU's completion thread, also when the layer had
    /// no drawable to give (nothing is drawn then). Throws only before the
    /// commit (foreign handle, no command buffer or encoder); `completion` then
    /// never runs. May wait inside `nextDrawable()` while the compositor holds
    /// every drawable (at most one second, the layer's timeout).
    func draw(
        _ texture: any TextureHandle, with kernel: any LibraryHandle, into layer: any PreviewLayerHandle,
        on context: any GPUContextHandle, completion: @escaping @Sendable (GPUCompletion) -> Void
    ) throws
}

public enum PreviewGatewayKey: TestDependencyKey {
    public static let testValue: any PreviewGateway = UnimplementedPreviewGateway()
}

extension DependencyValues {
    public var previewGateway: any PreviewGateway {
        get { self[PreviewGatewayKey.self] }
        set { self[PreviewGatewayKey.self] = newValue }
    }
}

private struct UnimplementedPreviewGateway: PreviewGateway {
    func prepare(_ target: any PreviewTargetHandle, on context: any GPUContextHandle) throws -> any PreviewLayerHandle {
        reportIssue("PreviewGateway.prepare not implemented")
        throw PreviewError.foreignTarget
    }

    func draw(
        _ texture: any TextureHandle, with kernel: any LibraryHandle, into layer: any PreviewLayerHandle,
        on context: any GPUContextHandle, completion: @escaping @Sendable (GPUCompletion) -> Void
    ) throws {
        reportIssue("PreviewGateway.draw not implemented")
        throw GPUError.commandBufferUnavailable
    }
}
