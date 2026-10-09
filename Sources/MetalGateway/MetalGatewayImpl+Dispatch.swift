/// `GPUGateway` live implementation, dispatch half.
/// OS API: `MTLCommandQueue.makeCommandBuffer(descriptor:)`, `MTLComputeCommandEncoder`,
/// `MTLCommandBuffer.addCompletedHandler` / `commit`.
import Domain
import Metal

extension MetalGatewayImpl {
    /// `errorOptions = .encoderExecutionStatus` so a fault names its encoder (ADR "Untrusted shaders").
    /// Handles are resolved before the encoder exists, so a foreign handle never leaves an encoder un-ended.
    public func encodeAndCommit(
        _ pass: ComputePass, on context: any GPUContextHandle, completion: @escaping @Sendable (GPUCompletion) -> Void
    ) throws {
        let queue = try context.commandQueue()
        let pipeline = try pass.kernel.pipelineState()
        let textures = try pass.textures.map { try $0.metalTexture() }
        let descriptor = MTLCommandBufferDescriptor()
        descriptor.errorOptions = .encoderExecutionStatus
        let commandBuffer = try queue.makeCommandBuffer(descriptor: descriptor).orThrow(GPUError.commandBufferUnavailable)
        let encoder = try commandBuffer.makeComputeCommandEncoder().orThrow(GPUError.encoderUnavailable)
        encoder.setComputePipelineState(pipeline)
        encoder.setTextures(textures, range: 0..<textures.count)
        withUnsafePointer(to: pass.uniforms) { encoder.setBytes($0, length: MemoryLayout<EffectUniforms>.stride, index: 0) }
        encoder.dispatchThreadgroups(pass.grid.threadgroups.metalSize(), threadsPerThreadgroup: pass.grid.threadsPerThreadgroup.metalSize())
        encoder.endEncoding()
        commandBuffer.addCompletedHandler { finished in
            let error = finished.error.map(RawGPUError.init(wrapping:))
            completion(GPUCompletion(gpuStart: finished.gpuStartTime, gpuEnd: finished.gpuEndTime, error: error))
        }
        commandBuffer.commit()
    }
}
