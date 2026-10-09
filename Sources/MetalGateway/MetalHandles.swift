/// Handles minted by `MetalGateway`; each owns one Metal object as `backing`.
/// OS API: `MTLCommandQueue`, `MTLComputePipelineState`, `MTLTexture`
/// (object ownership only).
import Domain
import Metal

/// `GPUContextHandle`: the queue, whose `device` is the context's device.
public final class CommandQueueBox: GPUContextHandle, @unchecked Sendable {
    public let backing: AnyObject

    public init(_ queue: any MTLCommandQueue) {
        backing = queue
    }
}

/// `LibraryHandle`: the entry kernel's compute pipeline state.
public final class PipelineBox: LibraryHandle, @unchecked Sendable {
    public let backing: AnyObject

    public init(_ pipeline: any MTLComputePipelineState) {
        backing = pipeline
    }
}

/// `TextureHandle`: the IOSurface-backed texture.
public final class TextureBox: TextureHandle, @unchecked Sendable {
    public let backing: AnyObject

    public init(_ texture: any MTLTexture) {
        backing = texture
    }
}
