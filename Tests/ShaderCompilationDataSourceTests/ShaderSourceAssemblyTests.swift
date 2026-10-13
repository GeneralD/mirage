import Domain
import ShaderCompilationDataSource
import Testing

/// The pure half of the DataSource: what the compiler is handed, and how its
/// locations come back. The real compiler's behaviour under `#line` is proven by
/// the `MetalGateway smoke` GPU suite; here every location form is synthesized.
@Suite("ShaderSourceAssembly")
struct ShaderSourceAssemblyTests {
    private static let offset = ShaderSourceAssembly.authorLineOffset

    private static func lines(_ text: String) -> [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    @Test("the assembled source is the prelude, the #line directive, then the author's source verbatim")
    func assemblyOrder() {
        let author = "kernel void effect() {}\n// tail without newline"
        let assembled = ShaderSourceAssembly.assemble(author)
        #expect(assembled == ShaderPrelude.source + "#line 1 \"effect\"\n" + author)
        #expect(ShaderPrelude.source.hasSuffix("\n"), "the directive must start a line of its own")
    }

    @Test("author line 1 is assembled line authorLineOffset + 1, right after the directive")
    func offsetCountsPreludeAndDirective() {
        let lines = Self.lines(ShaderSourceAssembly.assemble("first\nsecond"))
        #expect(lines[Self.offset - 1] == "#line 1 \"effect\"")
        #expect(lines[Self.offset] == "first")
        #expect(lines[Self.offset + 1] == "second")
        #expect(Self.offset == Self.lines(ShaderPrelude.source).count, "prelude lines + the directive line")
    }

    @Test("the prelude declares Uniforms, hash and noise, and never an entry point")
    func preludeSurface() {
        let prelude = ShaderPrelude.source
        #expect(prelude.contains("struct Uniforms {\n    float time;\n    uint frameIndex;\n    float2 resolution;\n    uint seed;\n};"))
        #expect(prelude.contains("static_assert(sizeof(Uniforms) == 24"))
        #expect(prelude.contains("inline float hash(uint2 cell, uint timeStep, uint seed)"))
        #expect(prelude.contains("inline float noise(float2 p, float time, uint seed)"))
        #expect(!prelude.contains("kernel "), "the effect's entry point is the author's")
    }

    @Test("a location in the author's part becomes effect:<author line>, the column untouched")
    func authorLocation() {
        let message = "program_source:\(Self.offset + 3):15: error: expected expression"
        #expect(ShaderSourceAssembly.authorRelative(message) == "effect:3:15: error: expected expression")
    }

    @Test("a location in the prelude, the directive's line included, becomes prelude:<line>")
    func preludeLocation() {
        #expect(
            ShaderSourceAssembly.authorRelative("program_source:12:14: note: previous definition is here")
                == "prelude:12:14: note: previous definition is here")
        #expect(ShaderSourceAssembly.authorRelative("program_source:\(Self.offset):1: warning: x") == "prelude:\(Self.offset):1: warning: x")
    }

    @Test("every location of a multi-diagnostic message is rewritten on its own")
    func severalLocations() {
        let message = """
            effect:1:14: error: redefinition of 'hash'
            inline float hash(uint2 cell, uint timeStep, uint seed) { return 0; }
                         ^
            program_source:44:14: note: previous definition is here
            program_source:\(Self.offset + 7):2: error: unknown type name 'flaot'
            """
        let expected = """
            effect:1:14: error: redefinition of 'hash'
            inline float hash(uint2 cell, uint timeStep, uint seed) { return 0; }
                         ^
            prelude:44:14: note: previous definition is here
            effect:7:2: error: unknown type name 'flaot'
            """
        #expect(ShaderSourceAssembly.authorRelative(message) == expected)
    }

    @Test("program_source:<n>: inside the echoed source line or the message text is the author's text, not a location, and is kept")
    func textThatOnlyLooksLikeALocation() {
        // Verbatim from the real compiler (Apple M1 Max): the excerpt echoes the failing line as the author wrote it.
        let withDirective = """
            effect:2:20: error: expected expression
                float x = 1.0 +; // was program_source:70: before
                               ^

            """
        #expect(ShaderSourceAssembly.authorRelative(withDirective) == withDirective)

        let withoutDirective = """
            program_source:\(Self.offset + 2):20: error: expected expression
                float x = 1.0 +; // was program_source:70: before
                               ^
            program_source:\(Self.offset + 4):1: error: unknown type name 'program_source:3:'
            """
        let expected = """
            effect:2:20: error: expected expression
                float x = 1.0 +; // was program_source:70: before
                               ^
            effect:4:1: error: unknown type name 'program_source:3:'
            """
        #expect(ShaderSourceAssembly.authorRelative(withoutDirective) == expected)
    }

    @Test("text without a program_source location is left as it is")
    func untouchedText() {
        for message in ["no kernel named 'effect' in the compiled source", "effect:3:1: error: x", "program_source: no line", ""] {
            #expect(ShaderSourceAssembly.authorRelative(message) == message)
        }
    }

    @Test("a line number too large for Int is left as the compiler wrote it")
    func overflowingLine() {
        let message = "program_source:99999999999999999999999:1: error: x"
        #expect(ShaderSourceAssembly.authorRelative(message) == message)
    }

    @Test("rewriting diagnostics keeps the compiler's code")
    func codeIsKept() {
        let raw = ShaderDiagnostics(message: "program_source:\(Self.offset + 1):1: error: x", code: 3)
        #expect(ShaderSourceAssembly.authorRelative(raw) == ShaderDiagnostics(message: "effect:1:1: error: x", code: 3))
    }

    @Test("rewriting diagnostics keeps their cause", arguments: [ShaderDiagnostics.Cause.source, .environment])
    func causeIsKept(_ cause: ShaderDiagnostics.Cause) {
        let raw = ShaderDiagnostics(message: "program_source:\(Self.offset + 1):1: error: x", code: 3, cause: cause)
        #expect(ShaderSourceAssembly.authorRelative(raw).cause == cause)
    }
}
