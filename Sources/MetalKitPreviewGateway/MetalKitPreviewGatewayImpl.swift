/// `PreviewGateway` live implementation, view half.
/// OS API: `MTKView.device` / `colorPixelFormat` / `framebufferOnly` / `isPaused` /
/// `enableSetNeedsDisplay`, the view's `CAMetalLayer`. What is drawn and when is `PreviewDataSource`'s.
import Domain
import MetalKit

public struct MetalKitPreviewGatewayImpl {
    public init() {}
}

extension MetalKitPreviewGatewayImpl: PreviewGateway {
    /// BGRA8 like every frame-path texture; `framebufferOnly = false` because the
    /// preview kernel writes the drawable from compute. Paused, with no
    /// `setNeedsDisplay` loop: the view never draws on its own, frames are pushed.
    /// Every handle is resolved before the view is touched, so a refusal leaves it as it was.
    @MainActor
    public func prepare(_ target: any PreviewTargetHandle, on context: any GPUContextHandle) throws -> any PreviewLayerHandle {
        let view = try (target.backing as? MTKView).orThrow(PreviewError.foreignTarget)
        let queue = try context.commandQueue()
        let layer = try (view.layer as? CAMetalLayer).orThrow(PreviewError.foreignTarget)
        view.device = queue.device
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return MetalLayerBox(layer)
    }
}
