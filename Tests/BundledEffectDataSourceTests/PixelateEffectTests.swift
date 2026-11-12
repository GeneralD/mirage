import BundledEffectDataSource
import Domain
import Testing

/// The bundled pixelate effect as data: what the runtime and the compiler rely on. That it compiles
/// behind the prelude and what its pixels are is the `Pixelate smoke` GPU suite's job.
@Suite("PixelateEffect")
struct PixelateEffectTests {
    @Test("the effect is named Pixelate, compiled precise under the entry point `effect`, with its source and parameter")
    func effectIsPixelate() {
        let effect = PixelateEffect.effect
        #expect(
            effect
                == EffectSource(
                    name: "Pixelate", source: PixelateEffect.source, options: ShaderCompileOptions(), parameters: PixelateEffect.parameters))
        #expect(effect.name == "Pixelate")
        #expect(effect.options == ShaderCompileOptions(entryPoint: "effect", precise: true))
        #expect(effect.parameters == PixelateEffect.parameters)
    }

    @Test("the one parameter is blockSize, an int from 1 to 64")
    func blockSizeIsTheOneParameter() {
        let expected = EffectParameterSpec(id: "blockSize", label: "Block Size", kind: .int(min: 1, max: 64, defaultValue: 8))
        #expect(PixelateEffect.parameters == [expected])
    }

    @Test("the default block size of 8 lies within the range of 1 to 64")
    func defaultBlockSizeIsInRange() {
        guard let spec = PixelateEffect.parameters.first, case .int(let minimum, let maximum, let defaultValue) = spec.kind else {
            Issue.record("blockSize is not an int parameter")
            return
        }
        #expect(minimum == 1)
        #expect(maximum == 64)
        #expect((minimum...maximum).contains(defaultValue))
    }

    @Test("the layout places blockSize at offset 0 in a struct of stride 4")
    func layoutPlacesBlockSizeFirst() {
        let layout = EffectParameterLayout(PixelateEffect.parameters)
        #expect(layout.fields == [EffectParameterLayout.Field(id: "blockSize", type: .int, offset: 0)])
        #expect(layout.stride == 4)
    }

    @Test("the source defines the entry point once and binds the layout GPURenderDataSource uses")
    func entryPointAndBindings() {
        let source = PixelateEffect.source
        #expect(source.components(separatedBy: "kernel void effect(").count == 2, "exactly one entry point")
        #expect(source.contains("[[texture(0)]]"), "input at texture 0")
        #expect(source.contains("[[texture(1)]]"), "output at texture 1")
        #expect(source.contains("constant Uniforms &uniforms [[buffer(0)]]"), "uniforms at buffer 0")
        #expect(source.contains("constant Parameters &params [[buffer(1)]]"), "parameters at buffer 1")
    }

    @Test("the source reads the block size as params.blockSize")
    func readsBlockSize() {
        #expect(PixelateEffect.source.contains("params.blockSize"))
    }

    @Test("the source leaves the prelude's names to the prelude: it defines neither Parameters, Uniforms, hash nor noise, and includes nothing")
    func preludeNamesAreTheEngines() {
        let source = PixelateEffect.source
        #expect(!source.contains("struct Parameters"))
        #expect(!source.contains("struct Uniforms"))
        #expect(!source.contains("float hash("))
        #expect(!source.contains("float noise("))
        #expect(!source.contains("#include"), "the prelude includes metal_stdlib")
    }
}
