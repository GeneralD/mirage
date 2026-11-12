import Entity
import TestSupport

/// One kind of every case, with values that mean nothing: the tests read the kind, not the range.
enum Kinds {
    static let float = EffectParameterKind.float(min: 0, max: 1, step: nil, defaultValue: 0.5)
    static let int = EffectParameterKind.int(min: 1, max: 16, defaultValue: 4)
    static let bool = EffectParameterKind.bool(defaultValue: false)
    static let color = EffectParameterKind.color(defaultValue: SIMD4<Float>(1, 0.5, 0.25, 1))
    static let vector2 = EffectParameterKind.vector2(min: SIMD2<Float>(0, 0), max: SIMD2<Float>(1, 1), defaultValue: SIMD2<Float>(0.5, 0.5))
    static let choice = EffectParameterKind.choice(options: ["Soft", "Hard"], defaultIndex: 0)

    static let all: [EffectParameterKind] = [float, int, bool, color, vector2, choice]
}

/// The six parameters of the spec's example manifest, in its order.
let rippleSpecs: [EffectParameterSpec] = [
    EffectParameterSpec(id: "strength", label: "Strength", kind: .float(min: 0, max: 1, step: 0.01, defaultValue: 0.5)),
    EffectParameterSpec(id: "rings", label: "Rings", kind: .int(min: 1, max: 16, defaultValue: 4)),
    EffectParameterSpec(id: "inverted", label: "Inverted", kind: .bool(defaultValue: false)),
    EffectParameterSpec(id: "tint", label: "Tint", kind: .color(defaultValue: SIMD4<Float>(1, 0.8, 0.6, 1))),
    EffectParameterSpec(
        id: "center", label: "Center", kind: .vector2(min: SIMD2<Float>(0, 0), max: SIMD2<Float>(1, 1), defaultValue: SIMD2<Float>(0.5, 0.5))),
    EffectParameterSpec(id: "mode", label: "Mode", kind: .choice(options: ["Soft", "Hard"], defaultIndex: 0)),
]

func specs(_ kinds: [EffectParameterKind]) -> [EffectParameterSpec] {
    kinds.enumerated().map { EffectParameterSpec(id: "p\($0.offset)", label: "P\($0.offset)", kind: $0.element) }
}

func randomKind(_ generator: inout SeededGenerator) -> EffectParameterKind {
    Kinds.all.randomElement(using: &generator) ?? Kinds.float
}

/// Between none and the 32 the manifest allows.
func randomSpecs(_ generator: inout SeededGenerator) -> [EffectParameterSpec] {
    let count = Int.random(in: 0...32, using: &generator)
    return specs((0..<count).map { _ in randomKind(&generator) })
}

/// A kind with the same field type and other numbers: a bool for a choice and the reverse, a new
/// range and default for the rest. Everything the panel owns changes, nothing the shader sees.
func otherKind(sharingFieldTypeWith kind: EffectParameterKind) -> EffectParameterKind {
    switch kind {
    case .float: .float(min: -5, max: 5, step: 0.5, defaultValue: 1)
    case .int: .int(min: -9, max: 9, defaultValue: 0)
    case .bool: .choice(options: ["a", "b", "c"], defaultIndex: 2)
    case .choice: .bool(defaultValue: true)
    case .color: .color(defaultValue: SIMD4<Float>(0, 0, 0, 0))
    case .vector2: .vector2(min: SIMD2<Float>(-1, -1), max: SIMD2<Float>(2, 2), defaultValue: SIMD2<Float>(0, 0))
    }
}
