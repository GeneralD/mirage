/// `PreviewLayerHandle` minted by `MetalKitPreviewGateway`, and the casts back
/// to the Metal objects behind every handle the gateway is handed.
/// OS API: `CAMetalLayer`, `MTLCommandQueue`, `MTLComputePipelineState`, `MTLTexture` (casts only).
import Domain
import MetalKit

/// `PreviewLayerHandle`: the prepared view's layer, and the view's delegate that
/// keeps the layer at the view's size for as long as the handle is held.
public final class MetalLayerBox: PreviewLayerHandle, @unchecked Sendable {
    public let backing: AnyObject
    private let sizeForwarder: DrawableSizeForwarder

    init(_ layer: CAMetalLayer, sizeForwarder: DrawableSizeForwarder) {
        backing = layer
        self.sizeForwarder = sizeForwarder
    }
}

extension PreviewLayerHandle {
    func metalLayer() throws -> CAMetalLayer {
        try (backing as? CAMetalLayer).orThrow(PreviewError.foreignTarget)
    }
}

extension GPUContextHandle {
    func commandQueue() throws -> any MTLCommandQueue {
        try (backing as? any MTLCommandQueue).orThrow(GPUError.foreignHandle)
    }
}

extension LibraryHandle {
    func pipelineState() throws -> any MTLComputePipelineState {
        try (backing as? any MTLComputePipelineState).orThrow(GPUError.foreignHandle)
    }
}

extension TextureHandle {
    func metalTexture() throws -> any MTLTexture {
        try (backing as? any MTLTexture).orThrow(GPUError.foreignHandle)
    }
}
