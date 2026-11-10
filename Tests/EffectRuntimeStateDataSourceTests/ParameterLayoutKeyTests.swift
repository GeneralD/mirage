import Domain
import EffectRuntimeStateDataSource
import TestDoubles
import TestSupport
import Testing

/// The compile cache's key takes the layout of an effect's parameters: the generated `Parameters`
/// struct is part of what is compiled, and nothing else about a parameter is. The key's other
/// parts are in `EffectRuntimeStateDataSourceTests`.
@Suite("EffectRuntimeState cache key", .timeLimit(.minutes(1)))
@MainActor
struct ParameterLayoutKeyTests {
    /// A change to the parameters of one source, and whether it changes the struct the shader reads.
    struct LayoutChange: Sendable, CustomTestStringConvertible {
        let label: String
        let parameters: [EffectParameterSpec]
        let compilesAgain: Bool
        var testDescription: String { label }

        static let strength = EffectParameterSpec(id: "strength", label: "Strength", kind: .float(min: 0, max: 1, step: 0.01, defaultValue: 0.5))
        static let rings = EffectParameterSpec(id: "rings", label: "Rings", kind: .int(min: 1, max: 16, defaultValue: 4))
        static let mode = EffectParameterSpec(id: "mode", label: "Mode", kind: .choice(options: ["Soft", "Hard"], defaultIndex: 0))
        static let original = [strength, rings, mode]

        static let all = [
            LayoutChange(
                label: "another label on every parameter",
                parameters: original.map { EffectParameterSpec(id: $0.id, label: $0.label + "!", kind: $0.kind) }, compilesAgain: false),
            LayoutChange(
                label: "another default",
                parameters: [
                    EffectParameterSpec(id: "strength", label: "Strength", kind: .float(min: 0, max: 1, step: 0.01, defaultValue: 0.9)), rings,
                    mode,
                ], compilesAgain: false),
            LayoutChange(
                label: "another range and step",
                parameters: [
                    EffectParameterSpec(id: "strength", label: "Strength", kind: .float(min: -4, max: 4, step: nil, defaultValue: 0.5)),
                    EffectParameterSpec(id: "rings", label: "Rings", kind: .int(min: 0, max: 99, defaultValue: 4)), mode,
                ], compilesAgain: false),
            LayoutChange(
                label: "more options in the choice",
                parameters: [
                    strength, rings,
                    EffectParameterSpec(id: "mode", label: "Mode", kind: .choice(options: ["Soft", "Hard", "Wet"], defaultIndex: 2)),
                ], compilesAgain: false),
            LayoutChange(
                label: "a bool in place of the choice: both are a uint",
                parameters: [strength, rings, EffectParameterSpec(id: "mode", label: "Mode", kind: .bool(defaultValue: true))],
                compilesAgain: false),
            LayoutChange(
                label: "another id",
                parameters: [EffectParameterSpec(id: "amount", label: "Strength", kind: strength.kind), rings, mode], compilesAgain: true),
            LayoutChange(
                label: "another field type",
                parameters: [
                    strength, EffectParameterSpec(id: "rings", label: "Rings", kind: .float(min: 1, max: 16, step: nil, defaultValue: 4)), mode,
                ],
                compilesAgain: true),
            LayoutChange(
                label: "a parameter added",
                parameters: original + [EffectParameterSpec(id: "tint", label: "Tint", kind: .color(defaultValue: SIMD4<Float>(1, 1, 1, 1)))],
                compilesAgain: true),
            LayoutChange(label: "a parameter removed", parameters: [strength, rings], compilesAgain: true),
            LayoutChange(label: "the parameters in another order", parameters: [rings, strength, mode], compilesAgain: true),
            LayoutChange(label: "no parameters at all", parameters: [], compilesAgain: true),
        ]
    }

    private static func ripple(_ parameters: [EffectParameterSpec]) -> EffectSource {
        EffectSource(name: "ripple", source: EffectSource.first.source, parameters: parameters)
    }

    @Test(
        "the cache key includes the parameter layout: a change of the Parameters struct compiles again, a label, default or range does not",
        arguments: LayoutChange.all)
    func layoutIsPartOfTheKey(_ change: LayoutChange) async throws {
        let fixture = StateFixture()
        let original = try await fixture.prepared(Self.ripple(LayoutChange.original))

        let begun = try await fixture.answer(fixture.begin(Self.ripple(change.parameters)))
        if change.compilesAgain {
            #expect(begun.ticket != nil, "another struct is another library")
        } else {
            #expect(begun == .cached)
            let admission = try await fixture.answer(fixture.admit())
            #expect(identity(admission.library) == identity(original))
        }
    }

    @Test("one source with two layouts is two libraries: each is a hit for its own layout after both compiled")
    func twoLayoutsOfOneSource() async throws {
        let fixture = StateFixture()
        let withParameters = Self.ripple(LayoutChange.original)
        let without = Self.ripple([])
        let first = try await fixture.prepared(withParameters)
        let second = try await fixture.prepared(without)
        #expect(identity(first) != identity(second))

        #expect(try await fixture.answer(fixture.begin(withParameters)) == .cached)
        #expect(identity(try await fixture.answer(fixture.admit()).library) == identity(first))
        #expect(try await fixture.answer(fixture.begin(without)) == .cached)
        #expect(identity(try await fixture.answer(fixture.admit()).library) == identity(second))
    }
}
