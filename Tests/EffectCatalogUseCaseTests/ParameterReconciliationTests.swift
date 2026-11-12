import Domain
import TestDoubles
import TestSupport
import Testing

@testable import EffectCatalogUseCase

/// The reconciliation of stored parameter values with the parameters a manifest declares now
/// (`docs/hackathon/mvp-cd/specs/parameters.md`). Each rule is named as the spec sentence it checks.
@Suite("ParameterReconciliation", .timeLimit(.minutes(1)))
struct ParameterReconciliationTests {
    // MARK: - Which ids survive

    @Test("a stored id the manifest no longer declares is dropped")
    func removedIdIsDropped() {
        let result = ParameterReconciliation.reconcile(stored: ["gone": .float(0.5), "rings": .int(2)], specs: [.rings])
        #expect(result == ["rings": .int(2)])
    }

    @Test("the result holds exactly the declared ids, whatever is stored")
    func keysAreTheDeclaredIds() {
        let stored: [String: EffectParameterValue] = ["extra": .bool(true), "strength": .float(0.5)]
        let result = ParameterReconciliation.reconcile(stored: stored, specs: EffectParameterSpec.all)
        #expect(Set(result.keys) == Set(EffectParameterSpec.all.map(\.id)))
    }

    @Test("with nothing stored, every declared id takes the default of its kind")
    func emptyStoredGivesEveryDefault() {
        let result = ParameterReconciliation.reconcile(stored: [:], specs: EffectParameterSpec.all)
        #expect(
            result == [
                "strength": .float(0.5),
                "rings": .int(4),
                "inverted": .bool(false),
                "tint": .color(SIMD4<Float>(1, 0.5, 0.25, 1)),
                "center": .vector2(SIMD2<Float>(0.5, 0.25)),
                "mode": .choice(0),
            ])
    }

    @Test("a declared id with no stored value takes the default of its kind, and the stored ids keep their values")
    func newIdTakesDefault() {
        let result = ParameterReconciliation.reconcile(stored: ["rings": .int(9)], specs: [.rings, .inverted])
        #expect(result == ["rings": .int(9), "inverted": .bool(false)])
    }

    @Test("no specs give an empty dictionary, whatever is stored")
    func noSpecsGiveEmpty() {
        #expect(ParameterReconciliation.reconcile(stored: ["rings": .int(2)], specs: []) == [:])
    }

    // MARK: - Which value survives

    @Test("a stored value of another case than the kind takes the kind's default, because the type changed")
    func changedTypeTakesDefault() {
        let stored: [String: EffectParameterValue] = ["rings": .float(3), "inverted": .int(1), "mode": .bool(true)]
        let result = ParameterReconciliation.reconcile(stored: stored, specs: [.rings, .inverted, .mode])
        #expect(result == ["rings": .int(4), "inverted": .bool(false), "mode": .choice(0)])
    }

    @Test("a stored value of the kind's own case is normalized into the kind's range")
    func ownCaseIsNormalized() {
        let result = ParameterReconciliation.reconcile(stored: ["rings": .int(99), "strength": .float(0.4)], specs: [.rings, .strength])
        #expect(result == ["rings": .int(16), "strength": .float(0.5)])
    }

    @Test("a narrowed range clamps the stored value to the new maximum")
    func narrowedRangeClamps() {
        let narrowed = EffectParameterSpec(
            id: "strength", label: "Strength", kind: .float(min: 0, max: 0.5, step: 0.25, defaultValue: 0.25))
        #expect(ParameterReconciliation.reconcile(stored: ["strength": .float(0.9)], specs: [narrowed]) == ["strength": .float(0.5)])
    }

    @Test("a choice index outside the new options takes the default index, not the nearest option")
    func choiceOutsideOptionsTakesDefault() {
        #expect(ParameterReconciliation.reconcile(stored: ["mode": .choice(5)], specs: [.mode]) == ["mode": .choice(0)])
    }

    @Test("reordered choice options keep the stored index, a decision the spec pins, since no meaning can be matched across lists")
    func reorderedOptionsKeepIndex() {
        let reordered = EffectParameterSpec(id: "mode", label: "Mode", kind: .choice(options: ["Hard", "Soft"], defaultIndex: 0))
        #expect(ParameterReconciliation.reconcile(stored: ["mode": .choice(1)], specs: [reordered]) == ["mode": .choice(1)])
    }

    // MARK: - Duplicate ids

    @Test("a duplicate id does not trap, and the first spec with that id decides the kind")
    func duplicateIdFirstSpecWins() {
        let floatSpec = EffectParameterSpec(id: "x", label: "X", kind: .float(min: 0, max: 1, step: nil, defaultValue: 0.25))
        let intSpec = EffectParameterSpec(id: "x", label: "X", kind: .int(min: 0, max: 9, defaultValue: 3))
        #expect(ParameterReconciliation.reconcile(stored: [:], specs: [floatSpec, intSpec]) == ["x": .float(0.25)])
        #expect(ParameterReconciliation.reconcile(stored: ["x": .float(0.5)], specs: [floatSpec, intSpec]) == ["x": .float(0.5)])
        #expect(ParameterReconciliation.reconcile(stored: ["x": .float(0.5)], specs: [intSpec, floatSpec]) == ["x": .int(3)])
    }

    // MARK: - Properties over seeded specs and stored values

    @Test("reconciling twice is the same as reconciling once, and every value is of its kind's case, for any seed")
    func reconciliationIsIdempotent() {
        forAll { generator in
            let specs = Self.randomSpecs(&generator)
            let stored = Self.randomStored(of: specs, &generator)
            let once = ParameterReconciliation.reconcile(stored: stored, specs: specs)
            #expect(ParameterReconciliation.reconcile(stored: once, specs: specs) == once, "seed \(generator.seed)")
            for spec in specs {
                #expect(once[spec.id].map { spec.kind.accepts($0) } == true, "seed \(generator.seed)")
            }
        }
    }

    /// Up to six specs with distinct ids. Each kind's default lies inside its range and on its step grid, as a manifest
    /// that passed its validation declares it. Every bound and step is a multiple of 0.25, so each snap is exact in `Float`.
    private static func randomSpecs(_ generator: inout SeededGenerator) -> [EffectParameterSpec] {
        (0..<Int.random(in: 0...6, using: &generator)).map { index in
            EffectParameterSpec(id: "p\(index)", label: "P\(index)", kind: randomKind(&generator))
        }
    }

    /// A kind drawn from any case, with an ordered range and a default inside it.
    private static func randomKind(_ generator: inout SeededGenerator) -> EffectParameterKind {
        switch Int.random(in: 0..<6, using: &generator) {
        case 0:
            let steps: [Float] = [0.25, 0.5, 1, 2]
            let step = steps.randomElement(using: &generator) ?? 0.25
            let low = Float(Int.random(in: -8...8, using: &generator)) * 0.25
            let width = Float(Int.random(in: 1...16, using: &generator)) * 0.25
            let offset = Int.random(in: 0...Int(width / step), using: &generator)
            return .float(min: low, max: low + width, step: step, defaultValue: low + Float(offset) * step)
        case 1:
            let low = Int32.random(in: -50...50, using: &generator)
            let high = low + Int32.random(in: 0...50, using: &generator)
            return .int(min: low, max: high, defaultValue: Int32.random(in: low...high, using: &generator))
        case 2:
            return .bool(defaultValue: Bool.random(using: &generator))
        case 3:
            let components = (0..<4).map { _ in Float.random(in: 0...1, using: &generator) }
            return .color(defaultValue: SIMD4<Float>(components[0], components[1], components[2], components[3]))
        case 4:
            let low = SIMD2<Float>(Float.random(in: -4...0, using: &generator), Float.random(in: -4...0, using: &generator))
            let high = SIMD2<Float>(Float.random(in: 0...4, using: &generator), Float.random(in: 0...4, using: &generator))
            let fallback = SIMD2<Float>(
                Float.random(in: low.x...high.x, using: &generator), Float.random(in: low.y...high.y, using: &generator))
            return .vector2(min: low, max: high, defaultValue: fallback)
        default:
            let count = Int.random(in: 1...8, using: &generator)
            return .choice(options: (0..<count).map { "option\($0)" }, defaultIndex: Int.random(in: 0..<count, using: &generator))
        }
    }

    /// Stored values for some of the declared ids, each of the kind's own case or of any case, plus a few ids no spec declares.
    private static func randomStored(of specs: [EffectParameterSpec], _ generator: inout SeededGenerator) -> [String: EffectParameterValue] {
        let declared = specs.compactMap { spec -> (String, EffectParameterValue)? in
            Bool.random(using: &generator)
                ? (spec.id, Bool.random(using: &generator) ? randomValue(of: spec.kind, &generator) : randomValue(&generator))
                : nil
        }
        let undeclared = (0..<Int.random(in: 0...2, using: &generator)).map { ("gone\($0)", randomValue(&generator)) }
        return Dictionary(declared + undeclared, uniquingKeysWith: { _, second in second })
    }

    /// A value of `kind`'s own case, anywhere in or beyond its range.
    private static func randomValue(of kind: EffectParameterKind, _ generator: inout SeededGenerator) -> EffectParameterValue {
        switch kind {
        case .float:
            .float(Float.random(in: -2...2, using: &generator))
        case .int:
            .int(Int32.random(in: -100...100, using: &generator))
        case .bool:
            .bool(Bool.random(using: &generator))
        case .color:
            .color(
                SIMD4<Float>(
                    Float.random(in: -1...2, using: &generator), Float.random(in: -1...2, using: &generator),
                    Float.random(in: -1...2, using: &generator), Float.random(in: -1...2, using: &generator)))
        case .vector2:
            .vector2(SIMD2<Float>(Float.random(in: -6...6, using: &generator), Float.random(in: -6...6, using: &generator)))
        case .choice(let options, _):
            .choice(Int.random(in: -2...(options.count + 2), using: &generator))
        }
    }

    /// A value of any case: the case of a random kind, so the value may or may not match the kind it is stored under.
    private static func randomValue(_ generator: inout SeededGenerator) -> EffectParameterValue {
        randomValue(of: randomKind(&generator), &generator)
    }
}
