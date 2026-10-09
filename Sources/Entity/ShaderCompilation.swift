/// How a shader source is compiled. Part of the compile cache key
/// (`EffectRuntimeRepository`), so every field is `Hashable`.
public struct ShaderCompileOptions: Sendable, Hashable {
    /// The kernel the compiled handle executes. Every effect exposes one entry
    /// point under this name; the prelude never defines it.
    public let entryPoint: String
    /// `true` turns fast math off so GPU hash-noise matches the Swift reference
    /// under the smoke tolerance.
    public let precise: Bool

    public init(entryPoint: String = "effect", precise: Bool = true) {
        self.entryPoint = entryPoint
        self.precise = precise
    }
}

/// A failed compile, verbatim from the compiler. Mapping the `program_source:`
/// line numbers back to the author's file (after the prelude is prepended) is
/// `ShaderCompilationDataSource`'s job.
public struct ShaderDiagnostics: Error, Sendable, Hashable {
    public let message: String
    /// The OS error code (`MTLLibraryError`); `0` when the source compiled but
    /// the entry point was not found.
    public let code: Int

    public init(message: String, code: Int) {
        self.message = message
        self.code = code
    }
}
