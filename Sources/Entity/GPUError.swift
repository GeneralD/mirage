/// Failures of the GPU Gateways themselves (device, queue, encoder, handle
/// provenance). Errors reported by a *running* command buffer travel as
/// `RawGPUError` inside `GPUCompletion`, never through this type.
public enum GPUError: Error, Sendable, Hashable {
    /// `MTLCreateSystemDefaultDevice` returned nothing.
    case noDevice
    case commandQueueUnavailable
    case commandBufferUnavailable
    case encoderUnavailable
    /// The handle was not produced by this gateway.
    case foreignHandle
    /// The device refused to wrap the surface in a texture.
    case textureBindingFailed
}
