import Dependencies
import Domain
import Foundation

/// The runtime compile of one effect: assemble (`ShaderSourceAssembly`), compile
/// through `ShaderLibraryGateway`, bring the diagnostics back to the author's
/// lines. Stateless, and so free of locks.
///
/// **Off main, guaranteed here.** The compile is a synchronous, slow call into
/// the shader compiler; it always runs inside a `WorkRunner` work item, whatever
/// executor the caller is on. The caller suspends until the item resumes it.
///
/// **A context per compile.** The compile needs only the device behind a
/// `GPUContextHandle`, and compiles are rare (one per effect change), so each one
/// asks `GPUGateway.makeContext()` rather than keeping a context that concurrent
/// compiles would have to share. The handle it returns stays usable on any other
/// context of the same device — the system default device, in the live gateway.
/// A context that cannot be made is reported as diagnostics (its `GPUError`
/// described, its `NSError` code kept), as the live gateway reports any error that
/// is not the compiler's, and the compiler is never asked. Those diagnostics say
/// `cause: .environment`, so the runtime can tell them from a broken source.
///
/// **Telling a transient fault from a broken source.** The compiler's own failures
/// come back from the Gateway as a raw code with the default `.source` cause;
/// `LibraryErrorMapping` classifies them here (epic #42, D7), so a compiler service
/// that failed (`MTLLibraryError.internal`) is `.environment` and retried by the next
/// `apply`, and everything else is final. Only the compiler's answer is classified:
/// a missing context already says `.environment` and its code is no `MTLLibraryError`.
public struct ShaderCompilationDataSourceImpl: Sendable {
    @Dependency(\.gpuGateway) private var gpuGateway
    @Dependency(\.shaderLibraryGateway) private var libraryGateway
    @Dependency(\.workRunner) private var workRunner

    public init() {}
}

extension ShaderCompilationDataSourceImpl: ShaderCompiler {
    public func compile(_ effect: EffectSource) async -> Result<any LibraryHandle, ShaderDiagnostics> {
        await withCheckedContinuation { continuation in
            _ = workRunner.run { continuation.resume(returning: compileNow(effect)) }
        }
    }

    /// The whole compile, on the work item's thread.
    private func compileNow(_ effect: EffectSource) -> Result<any LibraryHandle, ShaderDiagnostics> {
        Result { try gpuGateway.makeContext() }
            .mapError(ShaderDiagnostics.contextUnavailable)
            .flatMap {
                libraryGateway.compile(source: ShaderSourceAssembly.assemble(effect.source), options: effect.options, on: $0)
                    .mapError(LibraryErrorMapping.classified)
            }
            .mapError(ShaderSourceAssembly.authorRelative)
    }
}

extension ShaderDiagnostics {
    /// `GPUGateway.makeContext()` failed: nothing was compiled, and it is the
    /// environment's fault rather than the source's (`cause`), so a later compile may succeed.
    static func contextUnavailable(_ error: any Error) -> ShaderDiagnostics {
        ShaderDiagnostics(message: "no GPU context to compile on: \(error)", code: (error as NSError).code, cause: .environment)
    }
}
