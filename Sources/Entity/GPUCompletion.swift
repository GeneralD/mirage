/// What one committed command buffer reported when it finished. The Gateway
/// hands this out raw; deciding whether the frame is usable, over budget or a
/// failure (`EffectFailure`) is a pure mapping in `GPURenderDataSource`.
public struct GPUCompletion: Sendable, Hashable {
    /// GPU-side timestamps in seconds (`gpuStartTime` / `gpuEndTime`); both
    /// zero when the device does not report them.
    public let gpuStart: Double
    public let gpuEnd: Double
    /// `nil` when the command buffer completed; otherwise the raw error.
    public let error: RawGPUError?

    public init(gpuStart: Double, gpuEnd: Double, error: RawGPUError?) {
        self.gpuStart = gpuStart
        self.gpuEnd = gpuEnd
        self.error = error
    }
}

/// A command-buffer error as the OS reported it: domain and code only, so the
/// Gateway never interprets `timeout` / `pageFault` / `accessRevoked` — tests
/// synthesize these codes and the mapping lives above the Gateway.
public struct RawGPUError: Sendable, Hashable {
    public let domain: String
    public let code: Int

    public init(domain: String, code: Int) {
        self.domain = domain
        self.code = code
    }
}
