import BundledEffectDataSource
import Domain
import Testing

/// The vignette as data: what the runtime and the compiler rely on. That it compiles behind the
/// prelude and what its pixels are is the `Vignette smoke` GPU suite's job.
@Suite("VignetteEffect")
struct VignetteEffectTests {
    private let effect = VignetteEffect.effect

    @Test("the vignette is named Vignette and compiled precise under the entry point `effect`")
    func nameAndOptions() {
        #expect(effect.name == "Vignette")
        #expect(effect.options == ShaderCompileOptions(entryPoint: "effect", precise: true))
    }

    @Test("the parameters are strength then radius, with the ranges and defaults the panel shows")
    func parametersAreStrengthThenRadius() {
        #expect(
            VignetteEffect.parameters == [
                EffectParameterSpec(id: "strength", label: "Strength", kind: .float(min: 0, max: 1, step: 0.05, defaultValue: 0.5)),
                EffectParameterSpec(id: "radius", label: "Radius", kind: .float(min: 0.2, max: 1.5, step: 0.05, defaultValue: 0.8)),
            ])
        #expect(effect.parameters == VignetteEffect.parameters, "the effect declares exactly its parameters")
    }

    @Test("the layout puts strength at 0 and radius at 4 in a struct of stride 8")
    func layoutOfTheParameters() {
        let layout = EffectParameterLayout(effect.parameters)
        #expect(layout.stride == 8)
        #expect(layout.fields.map(\.id) == ["strength", "radius"])
        #expect(layout.fields.map(\.offset) == [0, 4])
    }

    @Test("each default lies inside its range, and each step is positive and at most the range's width")
    func defaultsAndStepsAreInRange() {
        for spec in VignetteEffect.parameters {
            guard case .float(let low, let high, let step, let defaultValue) = spec.kind else {
                Issue.record("\(spec.id) is not a float parameter")
                continue
            }
            #expect((low...high).contains(defaultValue), "\(spec.id): default \(defaultValue) is outside \(low)...\(high)")
            #expect(step.map { 0 < $0 && $0 <= high - low } == true, "\(spec.id): step \(String(describing: step))")
        }
    }

    @Test("the source defines the entry point once and binds the layout the runtime uses")
    func entryPointAndBindings() {
        let source = effect.source
        #expect(source.components(separatedBy: "kernel void effect(").count == 2, "exactly one entry point")
        #expect(source.contains("[[texture(0)]]"), "input at texture 0")
        #expect(source.contains("[[texture(1)]]"), "output at texture 1")
        #expect(source.contains("constant Uniforms &uniforms [[buffer(0)]]"), "uniforms at buffer 0")
        #expect(source.contains("constant Parameters &params [[buffer(1)]]"), "parameters at buffer 1")
    }

    @Test("the source reads strength and radius from params and leaves the struct and the prelude's names to the prelude")
    func readsParametersAndDefinesNoPreludeNames() {
        let source = effect.source
        #expect(source.contains("params.strength"))
        #expect(source.contains("params.radius"))
        #expect(!source.contains("struct Parameters"), "the generated struct is not the author's")
        #expect(!source.contains("struct Uniforms"))
        #expect(!source.contains("float hash("))
        #expect(!source.contains("float noise("))
        #expect(!source.contains("#include"), "the prelude includes metal_stdlib")
    }
}
