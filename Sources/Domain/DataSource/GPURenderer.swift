import Dependencies

/// `GPURenderDataSource`: one effect pass from a pooled input surface into a
/// pooled output surface. It resolves both tokens through the pool, binds them
/// as textures, commits exactly one command buffer through `GPUGateway` and
/// maps the raw completion onto `EffectFailure` — the one place a GPU outcome
/// is interpreted.
///
/// Contract: never throws; a stale token is `.invalidResource` and reaches no
/// gateway; every texture bound for the pass is unbound exactly once, on every
/// path. It keeps no failure history — counting, budget and auto-disable are
/// `EffectHealthPolicy`'s (MVP-D).
public protocol GPURenderer: Sendable {
    /// Runs `library` with `input` at texture index 0 and `output` at index 1,
    /// `uniforms` at buffer index 0, over a grid covering the output surface.
    /// Both leases stay the caller's; the renderer only borrows the surfaces
    /// until the command buffer completes.
    func render(
        library: any LibraryHandle, input: SurfaceToken, output: SurfaceToken, uniforms: EffectUniforms
    ) async -> Result<GPUTiming, EffectFailure>
}

public enum GPURendererKey: TestDependencyKey {
    public static let testValue: any GPURenderer = UnimplementedGPURenderer()
}

extension DependencyValues {
    public var gpuRenderer: any GPURenderer {
        get { self[GPURendererKey.self] }
        set { self[GPURendererKey.self] = newValue }
    }
}

private struct UnimplementedGPURenderer: GPURenderer {
    func render(
        library: any LibraryHandle, input: SurfaceToken, output: SurfaceToken, uniforms: EffectUniforms
    ) async -> Result<GPUTiming, EffectFailure> {
        reportIssue("GPURenderer.render not implemented")
        return .failure(.internalError)
    }
}
