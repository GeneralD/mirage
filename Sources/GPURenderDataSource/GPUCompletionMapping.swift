import Domain

/// What a command buffer's raw completion means for the effect: the pure half of
/// `GPURenderDataSource`. `MetalGateway` reports only the error's domain and
/// code; this is the one place they are interpreted, so a timeout or a page
/// fault is a raw code a test writes down, never a hang it provokes.
public enum GPUCompletionMapping {
    /// `MTLCommandBufferErrorDomain`, spelled out because nothing above the
    /// Gateway imports Metal; `GPUSmokeTests` pins it to the SDK constant.
    public static let commandBufferErrorDomain = "MTLCommandBufferErrorDomain"

    /// No error is success with the GPU's timestamps; any error is a failure.
    public static func result(of completion: GPUCompletion) -> Result<GPUTiming, EffectFailure> {
        guard let error = completion.error else {
            return .success(GPUTiming(gpuStart: completion.gpuStart, gpuEnd: completion.gpuEnd))
        }
        return .failure(failure(for: error))
    }

    /// `MTLCommandBufferError.Code` → `EffectFailure`: 2 timeout, 3 pageFault,
    /// 4 accessRevoked, 8 outOfMemory, 9 invalidResource. Every other code (0 none,
    /// 1 internal, 7 notPermitted, 10 memoryless, 11 deviceRemoved,
    /// 12 stackOverflow, a code a later SDK adds) stays `unknown(code:)` so it is
    /// visible rather than misread, and so does any code from another domain:
    /// the numbers mean these causes only in the command-buffer domain.
    public static func failure(for error: RawGPUError) -> EffectFailure {
        guard error.domain == commandBufferErrorDomain else { return .unknown(code: error.code) }
        return switch error.code {
        case 2: .timeout
        case 3: .pageFault
        case 4: .accessRevoked
        case 8: .outOfMemory
        case 9: .invalidResource
        default: .unknown(code: error.code)
        }
    }
}
