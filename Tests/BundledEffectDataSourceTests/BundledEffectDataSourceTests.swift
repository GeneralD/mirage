import BundledEffectDataSource
import Domain
import Testing

/// The bundled effect as data: what the runtime and the compiler rely on. That it
/// compiles behind the prelude and what its pixels are is the `MetalGateway smoke`
/// GPU suite's job.
@Suite("BundledEffectDataSource")
struct BundledEffectDataSourceTests {
    private let effect = BundledEffectDataSourceImpl().defaultEffect

    @Test("the default effect is the chromatic grain, compiled precise under the entry point `effect`")
    func defaultEffect() {
        #expect(effect == ChromaticGrainEffect.effect)
        #expect(effect.name == "Chromatic Grain")
        #expect(effect.options == ShaderCompileOptions(entryPoint: "effect", precise: true))
    }

    @Test("the source defines the entry point once and binds the layout GPURenderDataSource uses")
    func entryPointAndBindings() {
        let source = effect.source
        #expect(source.components(separatedBy: "kernel void effect(").count == 2, "exactly one entry point")
        #expect(source.contains("[[texture(0)]]"), "input at texture 0")
        #expect(source.contains("[[texture(1)]]"), "output at texture 1")
        #expect(source.contains("constant Uniforms &uniforms [[buffer(0)]]"), "uniforms at buffer 0")
    }

    @Test("the source leaves the prelude's names to the prelude: it uses hash and noise and defines neither, nor Uniforms")
    func preludeNamesAreTheEngines() {
        let source = effect.source
        #expect(source.contains("hash(gid, uniforms.frameIndex, uniforms.seed)"))
        #expect(source.contains("noise("))
        #expect(!source.contains("struct Uniforms"))
        #expect(!source.contains("float hash("))
        #expect(!source.contains("float noise("))
        #expect(!source.contains("namespace prelude"))
        #expect(!source.contains("#include"), "the prelude includes metal_stdlib")
    }
}
