/// The prepared view's `MTKViewDelegate`: hands every new drawable size to the layer.
/// OS API: `MTKViewDelegate.mtkView(_:drawableSizeWillChange:)`, `CAMetalLayer.drawableSize`.
/// A paused view resizes only its own `drawableSize`; without this the layer keeps its first drawable's size.
import MetalKit

@MainActor
final class DrawableSizeForwarder: NSObject, MTKViewDelegate {
    private let layer: CAMetalLayer

    init(_ layer: CAMetalLayer) {
        self.layer = layer
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        layer.drawableSize = size
    }

    /// Never called: the view is paused and frames are pushed through `PreviewGateway.draw`.
    func draw(in view: MTKView) {}
}
