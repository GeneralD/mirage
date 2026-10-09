/// How long one effect pass ran on the GPU, as its command buffer reported it:
/// the timestamps of a `GPUCompletion` that carried no error. Both are zero when
/// the device does not report them. The budget judgement over these values is
/// `EffectHealthPolicy`'s (MVP-D); `GPURenderDataSource` only hands them up.
public struct GPUTiming: Sendable, Hashable {
    /// GPU-side seconds (`gpuStartTime` / `gpuEndTime`).
    public let gpuStart: Double
    public let gpuEnd: Double

    public init(gpuStart: Double, gpuEnd: Double) {
        self.gpuStart = gpuStart
        self.gpuEnd = gpuEnd
    }
}
