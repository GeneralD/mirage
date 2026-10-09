import Domain
import MetalKit

/// The `PreviewTargetHandle` `PreviewView` hands out: the `MTKView` itself as
/// `backing`. Only `PreviewGateway.prepare` opens it, on the main thread.
public final class PreviewViewTarget: PreviewTargetHandle, @unchecked Sendable {
    public let backing: AnyObject

    public init(_ view: MTKView) {
        backing = view
    }
}
