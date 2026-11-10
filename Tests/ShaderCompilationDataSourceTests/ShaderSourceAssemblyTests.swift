import Domain
import ShaderCompilationDataSource
import TestSupport
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

    @Test("the assembled source is the prelude, one generated line, the #line directive, then the author's source verbatim")
    func assemblyOrder() {
        let author = "kernel void effect() {}\n// tail without newline"
        let assembled = ShaderSourceAssembly.assemble(author, layout: EffectParameterLayout(everyKindSpecs))
        #expect(assembled == ShaderPrelude.source + everyKindParametersLine + "\n" + "#line 1 \"effect\"\n" + author)
        #expect(ShaderPrelude.source.hasSuffix("\n"), "the generated line must start a line of its own")
    }

    @Test("a layout with every kind generates the checked-in Parameters line, struct and static_assert together on one line")
    func goldenParametersLine() {
        let lines = Self.lines(ShaderSourceAssembly.assemble("first", layout: EffectParameterLayout(everyKindSpecs)))
        #expect(String(lines[Self.offset - 2]) == everyKindParametersLine)
    }

    @Test("without parameters the generated line is the comment // no parameters, given an empty layout or left to the default")
    func noParameters() {
        let given = ShaderSourceAssembly.assemble("first", layout: EffectParameterLayout([]))
        #expect(String(Self.lines(given)[Self.offset - 2]) == noParametersLine)
        #expect(ShaderSourceAssembly.assemble("first") == given)
        #expect(!given.contains("Parameters"), "no name is taken from an existing package")
    }

    @Test("authorLineOffset counts the prelude's lines, the generated line and the directive")
    func offsetCountsPreludeParametersAndDirective() {
        #expect(Self.offset == Self.lines(ShaderPrelude.source).count + 1, "the prelude's lines, plus the generated line and the directive")
    }

    @Test(
        "author line 1 is assembled line authorLineOffset + 1, right after the directive, whatever the parameters",
        arguments: Seeds.range(0..<50))
    func offsetDoesNotDependOnTheLayout(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let layout = EffectParameterLayout(randomSpecs(&generator))
        let lines = Self.lines(ShaderSourceAssembly.assemble("first\nsecond", layout: layout))
        #expect(lines.count == Self.offset + 2, "the prelude, one generated line, the directive and the two author lines, nothing else")
        #expect(lines[Self.offset - 2].hasPrefix(layout.fields.isEmpty ? noParametersLine : "struct Parameters { "))
        #expect(lines[Self.offset - 1] == "#line 1 \"effect\"")
        #expect(lines[Self.offset] == "first")
        #expect(lines[Self.offset + 1] == "second")
    }

    @Test(
        "a diagnostic on the author's third line reads effect:3 whatever the parameters, found by where the line really is",
        arguments: Seeds.range(0..<50))
    func authorLinesSurviveParameters(seed: UInt64) throws {
        var generator = SeededGenerator(seed: seed)
        let layout = EffectParameterLayout(randomSpecs(&generator))
        let lines = Self.lines(ShaderSourceAssembly.assemble("one\ntwo\nTHIRD\nfour", layout: layout))
        let compilerLine = try #require(lines.firstIndex(of: "THIRD")) + 1
        #expect(ShaderSourceAssembly.authorRelative("program_source:\(compilerLine):9: error: x") == "effect:3:9: error: x")
    }

    @Test("the prelude declares Uniforms, hash and noise, never Parameters, and never an entry point")
    func preludeSurface() {
        let prelude = ShaderPrelude.source
        #expect(prelude.contains("struct Uniforms {\n    float time;\n    uint frameIndex;\n    float2 resolution;\n    uint seed;\n};"))
        #expect(prelude.contains("static_assert(sizeof(Uniforms) == 24"))
        #expect(prelude.contains("inline float hash(uint2 cell, uint timeStep, uint seed)"))
        #expect(prelude.contains("inline float noise(float2 p, float time, uint seed)"))
        #expect(!prelude.contains("Parameters"), "it differs per effect, so it is generated, not shared")
        #expect(!prelude.contains("kernel "), "the effect's entry point is the author's")
    }

    @Test("a location in the author's part becomes effect:<author line>, the column untouched")
    func authorLocation() {
        let message = "program_source:\(Self.offset + 3):15: error: expected expression"
        #expect(ShaderSourceAssembly.authorRelative(message) == "effect:3:15: error: expected expression")
    }

    @Test("a location in the prelude, the generated Parameters line and the directive's line included, becomes prelude:<line>")
    func preludeLocation() {
        #expect(
            ShaderSourceAssembly.authorRelative("program_source:12:14: note: previous definition is here")
                == "prelude:12:14: note: previous definition is here")
        #expect(ShaderSourceAssembly.authorRelative("program_source:\(Self.offset):1: warning: x") == "prelude:\(Self.offset):1: warning: x")
        #expect(ShaderSourceAssembly.authorRelative("program_source:\(Self.offset - 1):7: error: x") == "prelude:\(Self.offset - 1):7: error: x")
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
