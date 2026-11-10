import Dependencies
import Domain
import Foundation
import MetalGateway
import ShaderCompilationDataSource
import TestDoubles
import Testing

/// The generated `Parameters` struct on the real compiler. The text is checked in as a string
/// by `ShaderSourceAssemblyTests`; what only a compiler can say is checked here: that every
/// field type is accepted, that each field sits where `EffectParameterLayout` says (the kernel
/// asserts it with `__builtin_offsetof`, so the packer's offsets and the struct's agree), that the
/// `static_assert` really trips on a struct that drifts, and that the author's lines are
/// still the author's. Compile only: binding the block at buffer 1 is the compute pass's.
@Suite("Parameters struct smoke", .serialized, .enabled(if: MetalDeviceProbe.isAvailable), .timeLimit(.minutes(1)))
struct ParametersStructSmokeTests {
    private let gateway = MetalGatewayImpl()

    /// A list of parameter kinds the layout is made of, named for what it pads.
    struct LayoutCase: Sendable, CustomTestStringConvertible {
        let label: String
        let kinds: [EffectParameterKind]
        var testDescription: String { label }

        static let float = EffectParameterKind.float(min: 0, max: 1, step: nil, defaultValue: 0)
        static let int = EffectParameterKind.int(min: 0, max: 9, defaultValue: 0)
        static let bool = EffectParameterKind.bool(defaultValue: false)
        static let color = EffectParameterKind.color(defaultValue: SIMD4<Float>(0, 0, 0, 1))
        static let vector2 = EffectParameterKind.vector2(min: SIMD2<Float>(0, 0), max: SIMD2<Float>(1, 1), defaultValue: SIMD2<Float>(0, 0))
        static let choice = EffectParameterKind.choice(options: ["a", "b"], defaultIndex: 0)

        static let all = [
            LayoutCase(label: "one parameter of every kind", kinds: [float, int, bool, color, vector2, choice]),
            LayoutCase(label: "a float2 after a float: 4 bytes of padding", kinds: [float, vector2]),
            LayoutCase(label: "a float4 after a float: 12 bytes of padding", kinds: [float, color]),
            LayoutCase(label: "a float after a float4: the end is padded to 16", kinds: [color, float]),
            LayoutCase(label: "a float2 between two floats", kinds: [float, vector2, int]),
            LayoutCase(label: "the largest manifest, 32 floats", kinds: Array(repeating: float, count: 32)),
            LayoutCase(label: "the widest manifest, 32 colors", kinds: Array(repeating: color, count: 32)),
        ]

        var specs: [EffectParameterSpec] {
            kinds.enumerated().map { EffectParameterSpec(id: "p\($0.offset)", label: "P\($0.offset)", kind: $0.element) }
        }
    }

    private func compiler() -> ShaderCompilationDataSourceImpl {
        let gateway = gateway
        return withDependencies {
            $0.gpuGateway = gateway
            $0.shaderLibraryGateway = gateway
            $0.workRunner = RecordingWorkRunner()
        } operation: {
            ShaderCompilationDataSourceImpl()
        }
    }

    /// A kernel that reads every field of `layout` through `params` and asserts each one's offset.
    private static func kernel(reading layout: EffectParameterLayout) -> String {
        let offsets = layout.fields.map { "static_assert(__builtin_offsetof(Parameters, \($0.id)) == \($0.offset), \"offset of \($0.id)\");" }
        let reads = layout.fields.map { "    sum += \(read($0));" }
        return
            (offsets + [
                "kernel void effect(texture2d<float, access::write> out [[texture(0)]], constant Uniforms &u [[buffer(0)]],",
                "                   constant Parameters &params [[buffer(1)]], uint2 gid [[thread_position_in_grid]]) {",
                "    float sum = 0.0;",
            ] + reads + [
                "    if (gid.x >= out.get_width() || gid.y >= out.get_height()) { return; }",
                "    out.write(float4(sum), gid);",
                "}",
            ]).joined(separator: "\n")
    }

    /// An expression of type `float` that reads the field.
    private static func read(_ field: EffectParameterLayout.Field) -> String {
        switch field.type {
        case .float: "params.\(field.id)"
        case .int, .uint: "float(params.\(field.id))"
        case .float2: "params.\(field.id).x + params.\(field.id).y"
        case .float4: "dot(params.\(field.id), float4(1.0))"
        }
    }

    @Test("a kernel reading every field type through params compiles, and each field sits at the layout's offset", arguments: LayoutCase.all)
    func everyFieldTypeCompiles(_ layoutCase: LayoutCase) async throws {
        let specs = layoutCase.specs
        let source = Self.kernel(reading: EffectParameterLayout(specs))
        let result = await compiler().compile(EffectSource(name: layoutCase.label, source: source, parameters: specs))
        #expect(result.failure == nil, "\(result.failure?.message ?? "")")
    }

    @Test("an error on the author's third line is reported as effect:3 with every kind of parameter declared")
    func authorLinesAreKept() async throws {
        let broken = """
            kernel void effect(texture2d<float, access::write> out [[texture(0)]],
                               constant Parameters &params [[buffer(1)]], uint2 gid [[thread_position_in_grid]]) {
                float broken = params.p0 +;
                out.write(float4(broken), gid);
            }
            """
        let diagnostics = try #require(
            await compiler().compile(EffectSource(name: "broken", source: broken, parameters: LayoutCase.all[0].specs)).failure)
        #expect(diagnostics.message.hasPrefix("effect:3:"), "\(diagnostics.message)")
        #expect(!diagnostics.message.contains("program_source:"), "\(diagnostics.message)")
    }

    @Test("a kernel that names a parameter the manifest does not declare is the author's error, on the author's line")
    func undeclaredParameterIsTheAuthors() async throws {
        let source = """
            kernel void effect(texture2d<float, access::write> out [[texture(0)]],
                               constant Parameters &params [[buffer(1)]], uint2 gid [[thread_position_in_grid]]) {
                out.write(float4(params.nothing), gid);
            }
            """
        let diagnostics = try #require(
            await compiler().compile(EffectSource(name: "undeclared", source: source, parameters: LayoutCase.all[0].specs)).failure)
        #expect(diagnostics.message.hasPrefix("effect:3:"), "\(diagnostics.message)")
        #expect(diagnostics.cause == .source)
    }

    @Test("an effect that declares no parameters has no Parameters struct: a kernel that asks for one is the author's error")
    func noParametersNoStruct() async throws {
        let source = "kernel void effect(constant Parameters &params [[buffer(1)]]) {}"
        let diagnostics = try #require(await compiler().compile(EffectSource(name: "none", source: source)).failure)
        #expect(diagnostics.message.hasPrefix("effect:1:"), "\(diagnostics.message)")
    }

    @Test("the static_assert trips on a struct whose size drifts from the manifest's, and says so")
    func staticAssertTrips() throws {
        let layout = EffectParameterLayout(LayoutCase.all[0].specs)
        let assembled = ShaderSourceAssembly.assemble("kernel void effect() {}", layout: layout)
        let drifted = assembled.replacingOccurrences(of: "sizeof(Parameters) == \(layout.stride)", with: "sizeof(Parameters) == \(layout.stride - 4)")
        #expect(drifted != assembled)

        let context = try gateway.makeContext()
        let diagnostics = try #require(gateway.compile(source: drifted, options: ShaderCompileOptions(), on: context).failure)
        #expect(diagnostics.message.contains("Parameters must mirror the manifest"), "\(diagnostics.message)")
    }
}
