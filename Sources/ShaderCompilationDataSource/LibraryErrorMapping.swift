import Domain

/// What a compile error from the shader compiler means for the effect: the pure half
/// of `ShaderCompilationDataSource` that decides whether trying again can help
/// (epic #42, D7). `MetalGateway` reports only the error's raw code, so this is the
/// one place it is interpreted, and a transient fault is a number a test writes down,
/// never a failure it provokes.
///
/// The Gateway reports the code without its domain, so the numbers below are
/// `MTLLibraryError.Code`'s; the diagnostics of a source that compiled but has no
/// entry point carry `0`, which names no `MTLLibraryError` and is the source's.
public enum LibraryErrorMapping {
    /// `MTLLibraryError.Code.internal`, spelled as a number because nothing above the
    /// Gateway imports Metal; `GPUSmokeTests` pins it to the SDK constant.
    public static let internalErrorCode = 2

    /// `MTLLibraryError.Code.internal` is the compiler service failing, which says
    /// nothing about the source: `.environment`, so the next `apply` compiles again.
    /// Every other code — 1 unsupported, 3 compileFailure, 4 compileWarning,
    /// 5 functionNotFound, 6 fileNotFound, the `0` of a missing entry point and a code
    /// a later SDK adds — is `.source`, final: compiling the same text again fails
    /// the same way, and a code nobody has classified is not worth a retry per frame.
    public static func cause(forCode code: Int) -> ShaderDiagnostics.Cause {
        code == internalErrorCode ? .environment : .source
    }

    /// `diagnostics` with the cause its code names; the message and the code are kept.
    public static func classified(_ diagnostics: ShaderDiagnostics) -> ShaderDiagnostics {
        ShaderDiagnostics(message: diagnostics.message, code: diagnostics.code, cause: cause(forCode: diagnostics.code))
    }
}
