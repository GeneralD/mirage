import Domain
import ShaderCompilationDataSource
import Testing

@Suite("LibraryErrorMapping")
struct LibraryErrorMappingTests {
    /// Every `MTLLibraryError.Code` the SDK declares (1–6), the `0` of a missing entry
    /// point, the neighbours outside that range and the extremes, each with the cause
    /// it must become. `GPUSmokeTests` pins the SDK's numbers to these.
    static let libraryCodes: [(code: Int, expected: ShaderDiagnostics.Cause)] = [
        (0, .source),  // the entry point is missing: the source compiled
        (1, .source),  // unsupported
        (2, .environment),  // internal
        (3, .source),  // compileFailure
        (4, .source),  // compileWarning
        (5, .source),  // functionNotFound
        (6, .source),  // fileNotFound
        (7, .source),
        (-1, .source),
        (Int.max, .source),
        (Int.min, .source),
    ]

    @Test("each compiler error code maps to its cause", arguments: libraryCodes)
    func cause(code: Int, expected: ShaderDiagnostics.Cause) {
        #expect(LibraryErrorMapping.cause(forCode: code) == expected)
    }

    @Test("only the internal error is the environment's")
    func onlyInternalIsEnvironment() {
        #expect(LibraryErrorMapping.internalErrorCode == 2)
        #expect(Self.libraryCodes.filter { $0.expected == .environment }.map(\.code) == [LibraryErrorMapping.internalErrorCode])
    }

    @Test("classifying keeps the message and the code, and takes the cause from the code", arguments: libraryCodes)
    func classified(code: Int, expected: ShaderDiagnostics.Cause) {
        // A cause already on the diagnostics is not trusted: the Gateway only ever reports the default.
        let opposite: ShaderDiagnostics.Cause = expected == .source ? .environment : .source
        let raw = ShaderDiagnostics(message: "effect:3:1: error: x", code: code, cause: opposite)

        #expect(LibraryErrorMapping.classified(raw) == ShaderDiagnostics(message: "effect:3:1: error: x", code: code, cause: expected))
    }
}
