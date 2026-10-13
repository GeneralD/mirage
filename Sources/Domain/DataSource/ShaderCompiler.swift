import Dependencies

/// `ShaderCompilationDataSource`: turns an effect's MSL into a kernel the GPU
/// can dispatch. The engine prelude (`Uniforms`, `hash`, `noise`) is prepended
/// behind a `#line 1 "effect"` directive, so the compiler reports the author's
/// own line numbers; any location still given against the assembled source is
/// rewritten to the author's file (`effect:<line>:`) or to the prelude
/// (`prelude:<line>:`). The compile runs off the main thread through the
/// `WorkRunner` port. Nothing is cached here: the compile cache and "newest
/// wins" belong to `EffectRuntimeStateDataSource`.
public protocol ShaderCompiler: Sendable {
    /// One compile of `effect.source` with `effect.options`.
    ///
    /// Cancellation does not shorten it: a compile, once started, runs to
    /// completion even if the caller is cancelled — the compiler cannot be
    /// interrupted — and the cancelled caller stays suspended until then and
    /// receives the real result, handle or diagnostics, never an early or
    /// synthesized failure. Discarding a stale result is the caller's call.
    func compile(_ effect: EffectSource) async -> Result<any LibraryHandle, ShaderDiagnostics>
}

public enum ShaderCompilerKey: TestDependencyKey {
    public static let testValue: any ShaderCompiler = UnimplementedShaderCompiler()
}

extension DependencyValues {
    public var shaderCompiler: any ShaderCompiler {
        get { self[ShaderCompilerKey.self] }
        set { self[ShaderCompilerKey.self] = newValue }
    }
}

private struct UnimplementedShaderCompiler: ShaderCompiler {
    func compile(_ effect: EffectSource) async -> Result<any LibraryHandle, ShaderDiagnostics> {
        reportIssue("ShaderCompiler.compile not implemented")
        return .failure(ShaderDiagnostics(message: "ShaderCompiler.compile not implemented", code: 0))
    }
}
