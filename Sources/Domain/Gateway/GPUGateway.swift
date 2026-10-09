import Dependencies

/// One compute dispatch inside a command buffer. Carries handles, so it lives
/// here rather than in `Entity`; the plain values it packs are Entity types.
public struct ComputePass: Sendable {
    public let kernel: any LibraryHandle
    /// Bound at texture indices `0...`, in order (input first, output last by
    /// convention of the prelude).
    public let textures: [any TextureHandle]
    /// Bound at buffer index 0.
    public let uniforms: EffectUniforms
    public let grid: DispatchGrid

    public init(kernel: any LibraryHandle, textures: [any TextureHandle], uniforms: EffectUniforms, grid: DispatchGrid) {
        self.kernel = kernel
        self.textures = textures
        self.uniforms = uniforms
        self.grid = grid
    }
}

/// Thin pass-through to the GPU device and its command queue. One pass per
/// call, one command buffer per pass (one per effect, so faults are
/// attributable); sequencing several passes, the in-flight cap, drop order and
/// the meaning of a completion are `GPURenderDataSource`'s.
public protocol GPUGateway: Sendable {
    /// The system default device and one command queue. `GPUError.noDevice`
    /// when the machine has no GPU.
    func makeContext() throws -> any GPUContextHandle
    /// Encodes `pass` into a fresh command buffer, commits it and reports the
    /// raw completion exactly once, on the GPU's completion thread. Throws only
    /// for encoding failures (foreign handle, no encoder); a command buffer
    /// that fails while running reports through `completion`.
    func encodeAndCommit(
        _ pass: ComputePass, on context: any GPUContextHandle, completion: @escaping @Sendable (GPUCompletion) -> Void
    ) throws
}

public enum GPUGatewayKey: TestDependencyKey {
    public static let testValue: any GPUGateway = UnimplementedGPUGateway()
}

extension DependencyValues {
    public var gpuGateway: any GPUGateway {
        get { self[GPUGatewayKey.self] }
        set { self[GPUGatewayKey.self] = newValue }
    }
}

private struct UnimplementedGPUGateway: GPUGateway {
    func makeContext() throws -> any GPUContextHandle {
        reportIssue("GPUGateway.makeContext not implemented")
        throw GPUError.noDevice
    }

    func encodeAndCommit(
        _ pass: ComputePass, on context: any GPUContextHandle, completion: @escaping @Sendable (GPUCompletion) -> Void
    ) throws {
        reportIssue("GPUGateway.encodeAndCommit not implemented")
        throw GPUError.commandBufferUnavailable
    }
}
