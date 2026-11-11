import BundledEffectDataSource
import Domain
import Testing

/// The bundled effect as data: what the runtime and the compiler rely on. That it
/// compiles behind the prelude and what its pixels are is the `MetalGateway smoke`
/// GPU suite's job.
@Suite("BundledEffectDataSource")
struct BundledEffectDataSourceTests {
    private let effect = BundledEffectDataSourceImpl().defaultEffect
    private let effects = BundledEffectDataSourceImpl().effects

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

    @Test("the bundled effects are the four enums' effects, in menu order: chromatic grain, vignette, pixelate, duotone")
    func bundledEffectsInMenuOrder() {
        #expect(effects == [ChromaticGrainEffect.effect, VignetteEffect.effect, PixelateEffect.effect, DuotoneEffect.effect])
    }

    @Test("the effects are named Chromatic Grain, Vignette, Pixelate and Duotone, and no two share a name")
    func namesInMenuOrderAndUnique() {
        #expect(effects.map(\.name) == ["Chromatic Grain", "Vignette", "Pixelate", "Duotone"])
        #expect(Set(effects.map(\.name)).count == effects.count, "an effect's id is bundled:<name>, so a name cannot repeat")
    }

    @Test("the first effect is the default effect, so the menu's first row is the one the runtime runs first")
    func firstEffectIsTheDefault() {
        #expect(effects.first == effect)
    }

    @Test("the four effects declare 0, 2, 1 and 3 parameters, in menu order")
    func parameterCountsInMenuOrder() {
        #expect(effects.map(\.parameters.count) == [0, 2, 1, 3])
    }

    @Test("every bundled effect is compiled with the default options: the entry point effect, precise")
    func everyEffectCompilesWithTheDefaultOptions() {
        for bundled in effects {
            #expect(bundled.options == ShaderCompileOptions(), "\(bundled.name)")
        }
    }

    @Test("every bundled source defines the entry point once, and none defines the prelude's names or includes the prelude")
    func everySourceLeavesThePreludeToThePrelude() {
        for bundled in effects {
            let source = bundled.source
            #expect(source.components(separatedBy: "kernel void effect(").count == 2, "\(bundled.name): exactly one entry point")
            for name in ["struct Uniforms", "float hash(", "float noise(", "#include", "struct Parameters"] {
                #expect(!source.contains(name), "\(bundled.name) defines or includes \(name)")
            }
        }
    }

    @Test("a bundled effect with parameters reads them from a Parameters block at buffer 1, as params.<id>")
    func parametersAreReadFromBufferOne() {
        for bundled in effects where !bundled.parameters.isEmpty {
            #expect(bundled.source.contains("constant Parameters &params [[buffer(1)]]"), "\(bundled.name): parameters at buffer 1")
            for spec in bundled.parameters {
                #expect(bundled.source.contains("params.\(spec.id)"), "\(bundled.name) does not read params.\(spec.id)")
            }
        }
    }

    @Test("a bundled effect without parameters declares no Parameters block, so its source names none")
    func effectWithoutParametersNamesNoBlock() {
        for bundled in effects where bundled.parameters.isEmpty {
            #expect(!bundled.source.contains("Parameters"), "\(bundled.name)")
        }
    }

    @Test("every bundled effect declares at most 32 parameters")
    func atMostThirtyTwoParameters() {
        for bundled in effects {
            #expect(bundled.parameters.count <= 32, "\(bundled.name)")
        }
    }

    @Test("every bundled parameter id is 1 to 64 ASCII letters, digits and underscores, not starting with a digit, unique in its effect")
    func idsAreIdentifiersAndUniqueWithinAnEffect() {
        for bundled in effects {
            let ids = bundled.parameters.map(\.id)
            for id in ids {
                #expect(id.wholeMatch(of: #/[A-Za-z_][A-Za-z0-9_]{0,63}/#) != nil, "\(bundled.name): \(id)")
            }
            #expect(Set(ids).count == ids.count, "\(bundled.name): a parameter id repeats")
        }
    }

    @Test("every bundled parameter label has something other than spaces in it")
    func labelsAreNotBlank() {
        for spec in effects.flatMap(\.parameters) {
            #expect(!spec.label.allSatisfy(\.isWhitespace), "\(spec.id): the label is blank")
        }
    }

    @Test("every bundled float, int and vector2 range has min below max and a default between them, per component for a vector2")
    func rangesHoldTheirDefaults() {
        for spec in effects.flatMap(\.parameters) {
            switch spec.kind {
            case .float(let low, let high, _, let defaultValue):
                #expect(low < high, "\(spec.id): min is not below max")
                #expect(low <= defaultValue && defaultValue <= high, "\(spec.id): default is outside min to max")
            case .int(let low, let high, let defaultValue):
                #expect(low < high, "\(spec.id): min is not below max")
                #expect(low <= defaultValue && defaultValue <= high, "\(spec.id): default is outside min to max")
            case .vector2(let low, let high, let defaultValue):
                for component in 0..<2 {
                    #expect(low[component] < high[component], "\(spec.id)[\(component)]: min is not below max")
                    #expect(
                        low[component] <= defaultValue[component] && defaultValue[component] <= high[component],
                        "\(spec.id)[\(component)]: default is outside min to max")
                }
            case .bool, .color, .choice:
                break
            }
        }
    }

    @Test("every bundled float step is above 0 and at most max minus min")
    func stepsFitTheRange() {
        for spec in effects.flatMap(\.parameters) {
            guard case .float(let low, let high, let step?, _) = spec.kind else { continue }
            #expect(step > 0 && step <= high - low, "\(spec.id)")
        }
    }

    @Test("every bundled colour default has its four components in 0 to 1")
    func colourDefaultsAreInUnitRange() {
        for spec in effects.flatMap(\.parameters) {
            guard case .color(let defaultValue) = spec.kind else { continue }
            #expect((0..<4).allSatisfy { (0...1).contains(defaultValue[$0]) }, "\(spec.id)")
        }
    }

    @Test("every bundled choice has 1 to 32 distinct non-empty options and a default index among them")
    func choicesHoldTheirOptions() {
        for spec in effects.flatMap(\.parameters) {
            guard case .choice(let options, let defaultIndex) = spec.kind else { continue }
            #expect((1...32).contains(options.count), "\(spec.id): option count")
            #expect(Set(options).count == options.count, "\(spec.id): an option repeats")
            #expect(options.allSatisfy { !$0.isEmpty }, "\(spec.id): an option is empty")
            #expect(options.indices.contains(defaultIndex), "\(spec.id): default index is out of range")
        }
    }
}
