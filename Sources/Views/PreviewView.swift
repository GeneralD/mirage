import Domain
import MetalKit
import SwiftUI

/// The preview window's drawing surface: an `MTKView` the preview sink draws
/// frames into. The view only exists; readying it (device, pixel format, a
/// paused draw loop) is `PreviewGateway.prepare`'s, reached through the sink's
/// `attach`, so the view hands its target out once, when it is created, and
/// whoever owns the sink attaches it.
public struct PreviewView: NSViewRepresentable {
    private let onTarget: @MainActor (any PreviewTargetHandle) -> Void

    public init(onTarget: @escaping @MainActor (any PreviewTargetHandle) -> Void) {
        self.onTarget = onTarget
    }

    public func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero)
        onTarget(PreviewViewTarget(view))
        return view
    }

    public func updateNSView(_ view: MTKView, context: Context) {}
}
