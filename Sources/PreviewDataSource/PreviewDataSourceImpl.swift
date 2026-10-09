import Dependencies
import Domain

/// Draws presented frames into the attached preview view.
///
/// One draw is in flight at a time. Frames that arrive meanwhile wait in a
/// one-element slot where the newest wins; the frame it replaces completes at
/// once, undrawn. A frame is drawn by resolving its token through the pool,
/// binding the surface to a texture on the attach's GPU context and running
/// `PreviewKernel` into the view's next drawable; when the GPU is done the
/// texture is unbound and the frame completed, then the waiting frame (if any)
/// is drawn. Every `present` completes exactly once — undrawn when nothing is
/// attached, its token is stale, or binding or encoding fails.
///
/// Executor-confined: every state change runs on `FrameExecutor`, so there is
/// no lock and no actor on the frame path. Only `attach` starts on the main
/// thread (the view's), and it hands what it readied to the executor.
public final class PreviewDataSourceImpl: @unchecked Sendable {
    /// What one attach produced: the GPU context, the layer the view is drawn
    /// through and the preview kernel compiled for that context.
    private struct Attachment: Sendable {
        let context: any GPUContextHandle
        let layer: any PreviewLayerHandle
        let kernel: any LibraryHandle
    }

    /// A presented frame and the completion that ends its borrow of the surface.
    private struct Request: Sendable {
        let frame: FrameRef
        let completion: @Sendable () -> Void
    }

    @Dependency(\.gpuGateway) private var gpuGateway
    @Dependency(\.shaderLibraryGateway) private var shaderLibrary
    @Dependency(\.textureCacheGateway) private var textureCache
    @Dependency(\.previewGateway) private var previewGateway
    @Dependency(\.surfacePool) private var pool
    @Dependency(\.frameExecutor) private var frameExecutor
    @Dependency(\.errorLog) private var errorLog

    // Executor-confined: the attach in effect, whether a draw is in flight, and
    // the newest frame waiting for it.
    private var attachment: Attachment?
    private var drawing = false
    private var waiting: Request?

    public init() {}
}

extension PreviewDataSourceImpl: PreviewRenderer {
    /// The context and the view are readied here, on the main thread, so a
    /// missing device or a foreign target is thrown to the caller and the
    /// previous attach stays in effect; the kernel is compiled on the executor,
    /// never on main.
    @MainActor
    public func attach(_ target: any PreviewTargetHandle) throws {
        let context = try gpuGateway.makeContext()
        let layer = try previewGateway.prepare(target, on: context)
        frameExecutor.run { [self] in adopt(layer, on: context) }
    }

    public func present(_ frame: FrameRef, completion: @escaping @Sendable () -> Void) {
        let request = Request(frame: frame, completion: completion)
        frameExecutor.run { [self] in submit(request) }
    }
}

extension PreviewDataSourceImpl {
    /// A kernel that does not compile leaves nothing attached: the new view is
    /// already readied, so drawing on the previous one would draw on a view
    /// that has been replaced.
    private func adopt(_ layer: any PreviewLayerHandle, on context: any GPUContextHandle) {
        switch shaderLibrary.compile(source: PreviewKernel.source, options: PreviewKernel.options, on: context) {
        case .success(let kernel):
            attachment = Attachment(context: context, layer: layer, kernel: kernel)
        case .failure(let diagnostics):
            attachment = nil
            errorLog.record(.preview, "preview detached, its kernel did not compile (\(diagnostics.code)): \(diagnostics.message)")
        }
    }

    private func submit(_ request: Request) {
        guard let attachment else { return request.completion() }
        guard !drawing else { return hold(request) }
        draw(request, with: attachment)
    }

    /// Latest wins: the frame already waiting is replaced and completes now, undrawn.
    private func hold(_ request: Request) {
        let replaced = waiting
        waiting = request
        replaced?.completion()
    }

    private func draw(_ request: Request, with attachment: Attachment) {
        let token = request.frame.token
        guard let surface = pool.handle(for: token) else {
            errorLog.record(.preview, "frame not shown, token \(token.index)/\(token.generation) is stale")
            return request.completion()
        }
        let texture: any TextureHandle
        do {
            texture = try textureCache.bind(surface, on: attachment.context)
        } catch {
            errorLog.record(.preview, "frame not shown, binding its surface failed: \(error)")
            return request.completion()
        }
        drawing = true
        do {
            try previewGateway.draw(texture, with: attachment.kernel, into: attachment.layer, on: attachment.context) { [self] outcome in
                frameExecutor.run { [self] in finish(request, texture: texture, outcome: outcome) }
            }
        } catch {
            drawing = false
            errorLog.record(.preview, "frame not shown, encoding the draw failed: \(error)")
            unbind(texture)
            request.completion()
        }
    }

    /// The texture goes back before the frame completes: the completion ends the
    /// caller's lease on the surface the texture wraps.
    private func finish(_ request: Request, texture: any TextureHandle, outcome: GPUCompletion) {
        drawing = false
        outcome.error.map { errorLog.record(.preview, "preview draw failed: \($0.domain) \($0.code)") }
        unbind(texture)
        request.completion()
        let next = waiting
        waiting = nil
        next.map(submit)
    }

    private func unbind(_ texture: any TextureHandle) {
        do {
            try textureCache.unbind(texture)
        } catch {
            errorLog.record(.preview, "unbinding a preview texture failed: \(error)")
        }
    }
}
