/// `PreviewGateway` live implementation, draw half.
/// OS API: `CAMetalLayer.nextDrawable()`, `MTLComputeCommandEncoder`,
/// `MTLCommandBuffer.present(_:)` / `addCompletedHandler` / `commit`. One pass per call; the order is `PreviewDataSource`'s.
import Domain
import MetalKit

extension MetalKitPreviewGatewayImpl {
    /// The layer, not `MTKView.currentDrawable`: the view caches that drawable
    /// until its own `draw()` ends, which a paused view never runs, and the view
    /// belongs to the main thread while this runs on the frame executor. Handles
    /// are resolved before anything is encoded; no drawable leaves the command
    /// buffer empty, and it still commits so `completion` still runs once.
    public func draw(
        _ texture: any TextureHandle, with kernel: any LibraryHandle, into layer: any PreviewLayerHandle,
        on context: any GPUContextHandle, completion: @escaping @Sendable (GPUCompletion) -> Void
    ) throws {
        let queue = try context.commandQueue()
        let pipeline = try kernel.pipelineState()
        let frame = try texture.metalTexture()
        let metalLayer = try layer.metalLayer()
        let commandBuffer = try queue.makeCommandBuffer().orThrow(GPUError.commandBufferUnavailable)
        try metalLayer.nextDrawable().map { drawable in
            let grid = DispatchGrid.covering(width: drawable.texture.width, height: drawable.texture.height)
            let encoder = try commandBuffer.makeComputeCommandEncoder().orThrow(GPUError.encoderUnavailable)
            encoder.setComputePipelineState(pipeline)
            encoder.setTextures([frame, drawable.texture], range: 0..<2)
            encoder.dispatchThreadgroups(grid.threadgroups.metalSize(), threadsPerThreadgroup: grid.threadsPerThreadgroup.metalSize())
            encoder.endEncoding()
            commandBuffer.present(drawable)
        }
        commandBuffer.addCompletedHandler { finished in
            let error = finished.error.map(RawGPUError.init(wrapping:))
            completion(GPUCompletion(gpuStart: finished.gpuStartTime, gpuEnd: finished.gpuEndTime, error: error))
        }
        commandBuffer.commit()
    }
}
