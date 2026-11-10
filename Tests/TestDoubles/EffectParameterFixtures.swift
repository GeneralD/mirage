import Domain

/// The six parameters of the spec's example manifest (`docs/hackathon/mvp-cd/specs/parameters.md`), one per kind,
/// in the order their layout places them: offsets 0, 4, 8, 16, 32 and 40, stride 48. A label is the id with its
/// first letter capitalized.
extension EffectParameterSpec {
    public static let strength = EffectParameterSpec(
        id: "strength", label: "Strength", kind: .float(min: 0, max: 1, step: 0.25, defaultValue: 0.5))
    public static let rings = EffectParameterSpec(id: "rings", label: "Rings", kind: .int(min: 1, max: 16, defaultValue: 4))
    public static let inverted = EffectParameterSpec(id: "inverted", label: "Inverted", kind: .bool(defaultValue: false))
    public static let tint = EffectParameterSpec(
        id: "tint", label: "Tint", kind: .color(defaultValue: SIMD4<Float>(1, 0.5, 0.25, 1)))
    public static let center = EffectParameterSpec(
        id: "center", label: "Center",
        kind: .vector2(min: SIMD2<Float>(0, 0), max: SIMD2<Float>(1, 1), defaultValue: SIMD2<Float>(0.5, 0.25)))
    public static let mode = EffectParameterSpec(
        id: "mode", label: "Mode", kind: .choice(options: ["Soft", "Hard"], defaultIndex: 0))

    /// The six in their layout order.
    public static let all: [EffectParameterSpec] = [strength, rings, inverted, tint, center, mode]
}
