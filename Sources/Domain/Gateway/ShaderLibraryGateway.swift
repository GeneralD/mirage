import Dependencies

/// Thin pass-through to the runtime shader compiler. Source assembly (prelude,
/// `#line`), the compile cache and the "never on main" guarantee belong to
/// `ShaderCompilationDataSource` / `EffectRuntimeStateDataSource`; this port only
/// turns one source into one executable handle or the compiler's diagnostics.
public protocol ShaderLibraryGateway: Sendable {
    /// `makeLibrary(source:options:)`, then `options.entryPoint` resolved to its
    /// compute pipeline state. Runs synchronously on the caller's thread.
    func compile(
        source: String, options: ShaderCompileOptions, on context: any GPUContextHandle
    ) -> Result<any LibraryHandle, ShaderDiagnostics>
}

public enum ShaderLibraryGatewayKey: TestDependencyKey {
    public static let testValue: any ShaderLibraryGateway = UnimplementedShaderLibraryGateway()
}

extension DependencyValues {
    public var shaderLibraryGateway: any ShaderLibraryGateway {
        get { self[ShaderLibraryGatewayKey.self] }
        set { self[ShaderLibraryGatewayKey.self] = newValue }
    }
}

private struct UnimplementedShaderLibraryGateway: ShaderLibraryGateway {
    func compile(
        source: String, options: ShaderCompileOptions, on context: any GPUContextHandle
    ) -> Result<any LibraryHandle, ShaderDiagnostics> {
        reportIssue("ShaderLibraryGateway.compile not implemented")
        return .failure(ShaderDiagnostics(message: "ShaderLibraryGateway.compile not implemented", code: 0))
    }
}
