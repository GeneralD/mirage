/// `ShaderLibraryGateway` live implementation.
/// OS API: `MTLDevice.makeLibrary(source:options:)`, `MTLLibrary.makeFunction(name:)`,
/// `MTLDevice.makeComputePipelineState(function:)`.
import Domain
import Foundation
import Metal

extension MetalGatewayImpl: ShaderLibraryGateway {
    public func compile(
        source: String, options: ShaderCompileOptions, on context: any GPUContextHandle
    ) -> Result<any LibraryHandle, ShaderDiagnostics> {
        Result<any LibraryHandle, any Error> {
            let device = try context.commandQueue().device
            let library = try device.makeLibrary(source: source, options: options.metalOptions())
            let function = try library.makeFunction(name: options.entryPoint).orThrow(ShaderDiagnostics.missingEntryPoint(options.entryPoint))
            return PipelineBox(try device.makeComputePipelineState(function: function))
        }.mapError(ShaderDiagnostics.init(wrapping:))
    }
}

extension ShaderCompileOptions {
    /// `fastMathEnabled` only (epic #14, D7): `mathMode` needs macOS 15, and
    /// `languageVersion` / `#available` would be a branch in a thin live.
    fileprivate func metalOptions() -> MTLCompileOptions {
        let compileOptions = MTLCompileOptions()
        compileOptions.fastMathEnabled = !precise
        return compileOptions
    }
}

extension ShaderDiagnostics {
    fileprivate static func missingEntryPoint(_ name: String) -> ShaderDiagnostics {
        ShaderDiagnostics(message: "no kernel named '\(name)' in the compiled source", code: 0)
    }

    /// The compiler's own diagnostics pass through unchanged; any other error is reported by its `NSError` fields.
    fileprivate init(wrapping error: any Error) {
        self = (error as? ShaderDiagnostics) ?? ShaderDiagnostics(message: error.localizedDescription, code: (error as NSError).code)
    }
}
