import BundledEffectDataSource
import Domain
import Testing

/// The duotone effect as data: its name, compile options, parameters and layout, and the source text the
/// runtime assembles with the prelude. That it compiles and what its pixels are is `DuotoneSmokeTests`' job.
@Suite("Duotone effect")
struct DuotoneEffectTests {
    private let effect = DuotoneEffect.effect

    @Test("the duotone is named Duotone and compiled precise under the entry point `effect`")
    func nameAndOptions() {
        #expect(effect.name == "Duotone")
        #expect(effect.options == ShaderCompileOptions(entryPoint: "effect", precise: true))
    }

    @Test("the effect is its source and parameters under its name, with the default compile options")
    func effectIsItsParts() {
        #expect(
            effect
                == EffectSource(
                    name: DuotoneEffect.name, source: DuotoneEffect.source, options: ShaderCompileOptions(),
                    parameters: DuotoneEffect.parameters))
    }

    @Test("the parameters are shadows, highlights and amount, in that order, with the defaults the spec gives")
    func parametersInOrder() {
        #expect(
            effect.parameters == [
                EffectParameterSpec(id: "shadows", label: "Shadows", kind: .color(defaultValue: SIMD4<Float>(0.05, 0.05, 0.25, 1))),
                EffectParameterSpec(id: "highlights", label: "Highlights", kind: .color(defaultValue: SIMD4<Float>(1, 0.85, 0.5, 1))),
                EffectParameterSpec(id: "amount", label: "Amount", kind: .float(min: 0, max: 1, step: 0.05, defaultValue: 1)),
            ])
    }

    @Test("the Parameters layout is 48 bytes with shadows at 0, highlights at 16 and amount at 32")
    func layoutOffsetsAndStride() {
        let layout = EffectParameterLayout(effect.parameters)
        #expect(layout.stride == 48)
        #expect(layout.fields.map(\.id) == ["shadows", "highlights", "amount"])
        #expect(layout.fields.map(\.offset) == [0, 16, 32])
    }

    @Test("every colour default has all four components within [0, 1]")
    func colourDefaultsAreInUnitRange() {
        let colours = effect.parameters.compactMap { spec -> SIMD4<Float>? in
            guard case .color(let defaultValue) = spec.kind else { return nil }
            return defaultValue
        }
        #expect(colours.count == 2, "two colour parameters")
        #expect(colours.allSatisfy { colour in (0..<4).allSatisfy { (0...1).contains(colour[$0]) } })
    }

    @Test("amount's default 1 lies within its range, and its step is more than 0 and at most 1")
    func amountDefaultAndStep() {
        guard let amount = effect.parameters.first(where: { $0.id == "amount" }),
            case .float(let low, let high, let step, let defaultValue) = amount.kind
        else {
            Issue.record("no float parameter named amount")
            return
        }
        #expect(defaultValue == 1)
        #expect((low...high).contains(defaultValue))
        #expect(step.map { $0 > 0 && $0 <= 1 } == true, "the step is in (0, 1]")
    }

    @Test("the source defines the entry point once and binds input, output, uniforms and parameters at 0, 1, buffer 0 and buffer 1")
    func entryPointAndBindings() {
        let source = effect.source
        #expect(source.components(separatedBy: "kernel void effect(").count == 2, "exactly one entry point")
        #expect(source.contains("[[texture(0)]]"), "input at texture 0")
        #expect(source.contains("[[texture(1)]]"), "output at texture 1")
        #expect(source.contains("constant Uniforms &uniforms [[buffer(0)]]"), "uniforms at buffer 0")
        #expect(source.contains("constant Parameters &params [[buffer(1)]]"), "parameters at buffer 1")
    }

    @Test("the source reads the three parameters by name and defines none of the prelude's or the layout's names")
    func readsParametersAndDefinesNoPreludeNames() {
        let source = effect.source
        #expect(source.contains("params.shadows"))
        #expect(source.contains("params.highlights"))
        #expect(source.contains("params.amount"))
        #expect(!source.contains("struct Parameters"))
        #expect(!source.contains("struct Uniforms"))
        #expect(!source.contains("float hash("))
        #expect(!source.contains("float noise("))
        #expect(!source.contains("#include"), "the prelude includes metal_stdlib")
    }
}
