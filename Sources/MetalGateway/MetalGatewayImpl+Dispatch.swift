/// `GPUGateway` live implementation, dispatch half.
/// OS API: `MTLCommandQueue.makeCommandBuffer(descriptor:)`, `MTLComputeCommandEncoder`,
/// `MTLCommandBuffer.addCompletedHandler` / `commit`.
import Domain
import Metal

extension MetalGatewayImpl {
    /// `errorOptions = .encoderExecutionStatus` so a fault names its encoder (ADR "Untrusted shaders").
    public func encodeAndCommit(
        _ passes: [ComputePass], on context: any GPUContextHandle, completion: @escaping @Sendable (GPUCompletion) -> Void
    ) throws {
        let descriptor = MTLCommandBufferDescriptor()
        descriptor.errorOptions = .encoderExecutionStatus
        let commandBuffer = try context.commandQueue().makeCommandBuffer(descriptor: descriptor).orThrow(GPUError.commandBufferUnavailable)
        // swift-format-ignore: ReplaceForEachWithForLoop
        // A `for` loop is a branch to the thin-live lint (scripts/check-live-thin.sh); iteration without a decision is allowed.
        try passes.forEach { try encode($0, into: commandBuffer) }
        commandBuffer.addCompletedHandler { finished in
            let error = finished.error.map(RawGPUError.init(wrapping:))
            completion(GPUCompletion(gpuStart: finished.gpuStartTime, gpuEnd: finished.gpuEndTime, error: error))
        }
        commandBuffer.commit()
    }

    /// Handles are resolved before the encoder exists, so a foreign handle never leaves an encoder un-ended.
    private func encode(_ pass: ComputePass, into commandBuffer: any MTLCommandBuffer) throws {
        let pipeline = try pass.kernel.pipelineState()
        let textures = try pass.textures.map { try $0.metalTexture() }
        let encoder = try commandBuffer.makeComputeCommandEncoder().orThrow(GPUError.encoderUnavailable)
        encoder.setComputePipelineState(pipeline)
        encoder.setTextures(textures, range: 0..<textures.count)
        withUnsafePointer(to: pass.uniforms) { encoder.setBytes($0, length: MemoryLayout<EffectUniforms>.stride, index: 0) }
        encoder.dispatchThreadgroups(pass.grid.threadgroups.metalSize(), threadsPerThreadgroup: pass.grid.threadsPerThreadgroup.metalSize())
        encoder.endEncoding()
    }
}
