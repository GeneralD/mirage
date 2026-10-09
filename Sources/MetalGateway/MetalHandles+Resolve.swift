/// The Metal object behind each handle, or `GPUError.foreignHandle` for a
/// handle another gateway (or a fake) produced.
/// OS API: `MTLCommandQueue`, `MTLComputePipelineState`, `MTLTexture` (casts only).
import Domain
import Metal

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
