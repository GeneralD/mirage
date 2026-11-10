import Domain
import TestDoubles
import TestSupport
import Testing

@testable import EffectCatalogUseCase

/// The normalization policy of a parameter kind: its default value, what it accepts, and how a value is brought
/// into its range. Each rule is named as the spec sentence it checks; the seeded properties hold for every kind
/// the spec can declare, with ranges and steps on the float grid so that every snap is exact in `Float`.
@Suite("EffectParameterKind normalization", .timeLimit(.minutes(1)))
struct ParameterNormalizationTests {
    /// One row of the 6 × 6 acceptance table: a kind, a value, and whether the kind accepts that value.
    struct AcceptanceRow: Sendable {
        let kind: EffectParameterKind
        let value: EffectParameterValue
        let accepted: Bool
    }

    /// The six kinds of the shared fixtures, one per case, in the order of `valueOfEachCase`.
    private static let kinds: [EffectParameterKind] = EffectParameterSpec.all.map(\.kind)

    /// One value of each case, in the order of `kinds`.
    private static let valueOfEachCase: [EffectParameterValue] = [
        .float(0.5), .int(4), .bool(true), .color(SIMD4<Float>(1, 1, 1, 1)), .vector2(SIMD2<Float>(0.5, 0.5)), .choice(1),
    ]

    /// Every kind against every value: accepted exactly when the two are the same case.
    private static let acceptanceTable: [AcceptanceRow] = kinds.indices.flatMap { kindIndex -> [AcceptanceRow] in
        valueOfEachCase.indices.map { valueIndex in
            AcceptanceRow(kind: kinds[kindIndex], value: valueOfEachCase[valueIndex], accepted: kindIndex == valueIndex)
        }
    }

    // MARK: - The default value

    @Test("a kind's default value is the default its declaration names")
    func defaultValues() {
        #expect(EffectParameterSpec.strength.kind.defaultValue == .float(0.5))
        #expect(EffectParameterSpec.rings.kind.defaultValue == .int(4))
        #expect(EffectParameterSpec.inverted.kind.defaultValue == .bool(false))
        #expect(EffectParameterSpec.tint.kind.defaultValue == .color(SIMD4<Float>(1, 0.5, 0.25, 1)))
        #expect(EffectParameterSpec.center.kind.defaultValue == .vector2(SIMD2<Float>(0.5, 0.25)))
        #expect(EffectParameterSpec.mode.kind.defaultValue == .choice(0))
    }

    @Test("a choice's default value is its default index, whichever option that index names")
    func choiceDefaultIsItsIndex() {
        #expect(EffectParameterKind.choice(options: ["a", "b", "c"], defaultIndex: 2).defaultValue == .choice(2))
    }

    @Test("a kind accepts its own default value", arguments: kinds)
    func kindAcceptsItsDefault(kind: EffectParameterKind) {
        #expect(kind.accepts(kind.defaultValue))
    }

    // MARK: - Accepting a value

    @Test("accepts is true exactly when the value is of the kind's own case", arguments: acceptanceTable)
    func acceptsOnlyItsOwnCase(row: AcceptanceRow) {
        #expect(row.kind.accepts(row.value) == row.accepted)
    }

    @Test("a value of another case becomes the kind's default", arguments: acceptanceTable.filter { !$0.accepted })
    func otherCaseFallsBackToDefault(row: AcceptanceRow) {
        #expect(row.kind.normalized(row.value) == row.kind.defaultValue)
    }

    // MARK: - Float

    @Test("a float that is NaN falls back to the kind's default")
    func nanFloatIsDefault() {
        #expect(EffectParameterSpec.strength.kind.normalized(.float(.nan)) == .float(0.5))
    }

    @Test("a float outside its range is clamped to the nearer end, and an infinity lands on the end it lies beyond")
    func floatClampsToRange() {
        let plain = EffectParameterKind.float(min: -2, max: 3, step: nil, defaultValue: 0)
        #expect(plain.normalized(.float(7)) == .float(3))
        #expect(plain.normalized(.float(-9)) == .float(-2))
        #expect(plain.normalized(.float(.infinity)) == .float(3))
        #expect(plain.normalized(.float(-.infinity)) == .float(-2))
        #expect(plain.normalized(.float(1.25)) == .float(1.25))
    }

    @Test("a float without a step is not rounded at all")
    func floatWithoutStepKeepsItsValue() {
        let plain = EffectParameterKind.float(min: 0, max: 1, step: nil, defaultValue: 0.5)
        #expect(plain.normalized(.float(0.3)) == .float(0.3))
    }

    @Test("a float is rounded to the nearest step, the strength examples of the spec, and 1.3 becomes 1.5 in 1...3 step 0.5")
    func floatSnapsToStep() {
        let strength = EffectParameterSpec.strength.kind
        #expect(strength.normalized(.float(0.3)) == .float(0.25))
        #expect(strength.normalized(.float(0.4)) == .float(0.5))
        #expect(strength.normalized(.float(0.9)) == .float(1.0))
        #expect(strength.normalized(.float(0.1)) == .float(0.0))
        #expect(strength.normalized(.float(7)) == .float(1.0))
        #expect(strength.normalized(.float(-1)) == .float(0.0))
        #expect(EffectParameterKind.float(min: 1, max: 3, step: 0.5, defaultValue: 2).normalized(.float(1.3)) == .float(1.5))
    }

    @Test("a float's steps are counted from its minimum, not from zero")
    func floatStepsStartAtMinimum() {
        let odd = EffectParameterKind.float(min: 1, max: 9, step: 2, defaultValue: 5)
        #expect(odd.normalized(.float(2.2)) == .float(3))
        #expect(odd.normalized(.float(4.1)) == .float(5))
    }

    @Test("a float that rounds past its maximum is clamped to the maximum, the rounding being done first")
    func floatRoundedPastMaximumIsClamped() {
        let kind = EffectParameterKind.float(min: 0, max: 1.5, step: 1, defaultValue: 0)
        #expect(kind.normalized(.float(1.5)) == .float(1.5))
        #expect(kind.normalized(.float(.infinity)) == .float(1.5))
    }

    @Test("a step that is infinite leaves the clamped value as it is, never NaN")
    func infiniteStepDoesNotSnap() {
        let kind = EffectParameterKind.float(min: 0, max: 1, step: .infinity, defaultValue: 0.5)
        #expect(kind.normalized(.float(0.3)) == .float(0.3))
    }

    // MARK: - Int, bool, color, vector2, choice

    @Test("an int is clamped to its range, and the extremes of Int32 do not trap")
    func intClampsToRange() {
        let rings = EffectParameterSpec.rings.kind
        #expect(rings.normalized(.int(0)) == .int(1))
        #expect(rings.normalized(.int(17)) == .int(16))
        #expect(rings.normalized(.int(Int32.min)) == .int(1))
        #expect(rings.normalized(.int(Int32.max)) == .int(16))
        #expect(rings.normalized(.int(4)) == .int(4))
    }

    @Test("a bool is kept as it is")
    func boolIsKept() {
        let inverted = EffectParameterSpec.inverted.kind
        #expect(inverted.normalized(.bool(true)) == .bool(true))
        #expect(inverted.normalized(.bool(false)) == .bool(false))
    }

    @Test("each color component is clamped to 0 through 1, and a NaN component takes the default's component")
    func colorComponentsAreClampedOrDefaulted() {
        let tint = EffectParameterSpec.tint.kind
        #expect(tint.normalized(.color(SIMD4<Float>(2, -1, .nan, 0.5))) == .color(SIMD4<Float>(1, 0, 0.25, 0.5)))
    }

    @Test("each vector component is clamped to its own range, and a NaN component takes the default's component")
    func vectorComponentsAreClampedOrDefaulted() {
        let center = EffectParameterSpec.center.kind
        #expect(center.normalized(.vector2(SIMD2<Float>(1.5, .nan))) == .vector2(SIMD2<Float>(1, 0.25)))
        let skewed = EffectParameterKind.vector2(min: SIMD2<Float>(-1, 0), max: SIMD2<Float>(2, 4), defaultValue: SIMD2<Float>(0, 1))
        #expect(skewed.normalized(.vector2(SIMD2<Float>(-5, 9))) == .vector2(SIMD2<Float>(-1, 4)))
    }

    @Test("a choice index outside the options becomes the default index, not the nearest option")
    func choiceOutsideOptionsIsDefault() {
        let kind = EffectParameterKind.choice(options: ["a", "b", "c", "d"], defaultIndex: 2)
        #expect(kind.normalized(.choice(9)) == .choice(2))
        #expect(kind.normalized(.choice(-1)) == .choice(2))
        #expect(kind.normalized(.choice(3)) == .choice(3))
    }

    @Test("a range whose minimum is above its maximum does not trap, and clamps as min(max(value, lo), hi)")
    func invertedRangeDoesNotTrap() {
        #expect(EffectParameterKind.int(min: 9, max: 1, defaultValue: 5).normalized(.int(5)) == .int(1))
        #expect(EffectParameterKind.int(min: Int32.max, max: Int32.min, defaultValue: 0).normalized(.int(0)) == .int(Int32.min))
        #expect(EffectParameterKind.float(min: 1, max: 0, step: nil, defaultValue: 0.5).normalized(.float(0.5)) == .float(0))
    }

    // MARK: - Properties over seeded kinds and values

    @Test("normalizing a value twice is the same as normalizing it once, for any kind and any value", arguments: Seeds.range(0..<128))
    func normalizationIsIdempotent(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let kind = Self.randomKind(&generator)
        let once = kind.normalized(Self.randomValue(of: kind, &generator))
        #expect(kind.accepts(once))
        #expect(kind.normalized(once) == once)
    }

    @Test("a normalized float or int lies within the range its kind declares", arguments: Seeds.range(0..<128))
    func normalizedNumbersLieWithinTheirRange(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let kind = Self.randomKind(&generator)
        switch (kind, kind.normalized(Self.randomValue(of: kind, &generator))) {
        case (.float(let lo, let hi, _, _), .float(let result)):
            #expect((lo...hi).contains(result))
        case (.int(let lo, let hi, _), .int(let result)):
            #expect((lo...hi).contains(result))
        default:
            break
        }
    }

    /// A kind drawn from any case, with a range ordered from its minimum to its maximum and a step on the float grid.
    private static func randomKind(_ generator: inout SeededGenerator) -> EffectParameterKind {
        switch Int.random(in: 0..<6, using: &generator) {
        case 0:
            let first = Int.random(in: -256...256, using: &generator)
            let second = Int.random(in: -256...256, using: &generator)
            let steps: [Float] = [0.25, 0.5, 1, 2]
            let step = steps.randomElement(using: &generator) ?? 0.25
            return .float(min: Float(min(first, second)) * 0.25, max: Float(max(first, second)) * 0.25, step: step, defaultValue: 0)
        case 1:
            let first = Int32.random(in: -1000...1000, using: &generator)
            let second = Int32.random(in: -1000...1000, using: &generator)
            return .int(min: min(first, second), max: max(first, second), defaultValue: 0)
        case 2:
            return .bool(defaultValue: Bool.random(using: &generator))
        case 3:
            let components = (0..<4).map { _ in Float.random(in: -1...2, using: &generator) }
            return .color(defaultValue: SIMD4<Float>(components[0], components[1], components[2], components[3]))
        case 4:
            let low = SIMD2<Float>(Float.random(in: -4...0, using: &generator), Float.random(in: -4...0, using: &generator))
            let high = SIMD2<Float>(Float.random(in: 0...4, using: &generator), Float.random(in: 0...4, using: &generator))
            return .vector2(min: low, max: high, defaultValue: low)
        default:
            let count = Int.random(in: 1...8, using: &generator)
            let options = (0..<count).map { "option\($0)" }
            return .choice(options: options, defaultIndex: Int.random(in: 0..<count, using: &generator))
        }
    }

    /// A value of `kind`'s own case, anywhere in or beyond its range.
    private static func randomValue(of kind: EffectParameterKind, _ generator: inout SeededGenerator) -> EffectParameterValue {
        switch kind {
        case .float:
            return .float(Float.random(in: -100...100, using: &generator))
        case .int:
            return .int(Int32.random(in: -2000...2000, using: &generator))
        case .bool:
            return .bool(Bool.random(using: &generator))
        case .color:
            let components = (0..<4).map { _ in Float.random(in: -1...2, using: &generator) }
            return .color(SIMD4<Float>(components[0], components[1], components[2], components[3]))
        case .vector2:
            let x = Float.random(in: -6...6, using: &generator)
            let y = Float.random(in: -6...6, using: &generator)
            return .vector2(SIMD2<Float>(x, y))
        case .choice(let options, _):
            return .choice(Int.random(in: -2...(options.count + 2), using: &generator))
        }
    }
}
