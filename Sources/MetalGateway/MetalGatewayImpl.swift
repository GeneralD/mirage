/// `GPUGateway` live implementation, context half.
/// OS API: `MTLCreateSystemDefaultDevice`, `MTLDevice.makeCommandQueue`.
/// Every decision lives in `GPURenderDataSource`; this only forwards.
import Domain
import Metal

public struct MetalGatewayImpl {
    public init() {}
}

extension MetalGatewayImpl: GPUGateway {
    public func makeContext() throws -> any GPUContextHandle {
        let device = try MTLCreateSystemDefaultDevice().orThrow(GPUError.noDevice)
        return CommandQueueBox(try device.makeCommandQueue().orThrow(GPUError.commandQueueUnavailable))
    }
}
