import Domain
import TestSupport

/// One parameter of every kind, in the order of the parameters spec's example manifest. The
/// numbers mean nothing here: what the shader sees is each kind's field type and its place.
let everyKindSpecs: [EffectParameterSpec] = [
    EffectParameterSpec(id: "strength", label: "Strength", kind: .float(min: 0, max: 1, step: 0.01, defaultValue: 0.5)),
    EffectParameterSpec(id: "rings", label: "Rings", kind: .int(min: 1, max: 16, defaultValue: 4)),
    EffectParameterSpec(id: "inverted", label: "Inverted", kind: .bool(defaultValue: false)),
    EffectParameterSpec(id: "tint", label: "Tint", kind: .color(defaultValue: SIMD4<Float>(1, 0.8, 0.6, 1))),
    EffectParameterSpec(
        id: "center", label: "Center", kind: .vector2(min: SIMD2<Float>(0, 0), max: SIMD2<Float>(1, 1), defaultValue: SIMD2<Float>(0.5, 0.5))),
    EffectParameterSpec(id: "mode", label: "Mode", kind: .choice(options: ["Soft", "Hard"], defaultIndex: 0)),
]

/// The `Parameters` line of `everyKindSpecs`, checked in as text: the offsets are float 0, int 4,
/// uint 8, float4 16, float2 32, uint 40, and the stride 48.
let everyKindParametersLine =
    "struct Parameters { float strength; int rings; uint inverted; float4 tint; float2 center; uint mode; }; "
    + "static_assert(sizeof(Parameters) == 48, \"Parameters must mirror the manifest\");"

/// The line a layout without parameters leaves in the same place.
let noParametersLine = "// no parameters"

/// Between none and the 32 a manifest allows, each of a random kind and named `p<index>`.
func randomSpecs(_ generator: inout SeededGenerator) -> [EffectParameterSpec] {
    let count = Int.random(in: 0...32, using: &generator)
    return (0..<count).map { index in
        let spec = everyKindSpecs.randomElement(using: &generator) ?? everyKindSpecs[0]
        return EffectParameterSpec(id: "p\(index)", label: "P\(index)", kind: spec.kind)
    }
}
