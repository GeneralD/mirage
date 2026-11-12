import Domain
import TestDoubles
import Testing

@testable import EffectCatalogUseCase

/// The values of one effect's parameters as a model (`docs/hackathon/mvp-cd/specs/parameters.md`). Each rule of the
/// model's interface is one test named as the spec sentence it checks. The golden bytes are written out from the spec's
/// table, not computed through the packer.
@Suite("ParameterModel", .timeLimit(.minutes(1)))
struct ParameterModelTests {
    /// The 48 bytes of the six example values, written out from the spec's table.
    private static let goldenBytes: [UInt8] = [
        0x00, 0x00, 0x40, 0x3F,  // strength 0.75 at 0
        0x07, 0x00, 0x00, 0x00,  // rings 7 at 4
        0x01, 0x00, 0x00, 0x00,  // inverted true at 8
        0x00, 0x00, 0x00, 0x00,  // padding 12 to 15
        0x00, 0x00, 0x80, 0x3E,  // tint red 0.25 at 16
        0x00, 0x00, 0x00, 0x3F,  // tint green 0.5
        0x00, 0x00, 0x40, 0x3F,  // tint blue 0.75
        0x00, 0x00, 0x80, 0x3F,  // tint alpha 1
        0x00, 0x00, 0x00, 0x3F,  // center x 0.5 at 32
        0x00, 0x00, 0x80, 0x3F,  // center y 1
        0x01, 0x00, 0x00, 0x00,  // mode 1 at 40
        0x00, 0x00, 0x00, 0x00,  // padding 44 to 47
    ]

    /// The 48 bytes of the defaults of the fixtures: strength 0.5, rings 4, inverted false, tint (1, 0.5, 0.25, 1),
    /// center (0.5, 0.25) and mode 0.
    private static let defaultBytes: [UInt8] = [
        0x00, 0x00, 0x00, 0x3F,  // strength 0.5 at 0
        0x04, 0x00, 0x00, 0x00,  // rings 4 at 4
        0x00, 0x00, 0x00, 0x00,  // inverted false at 8
        0x00, 0x00, 0x00, 0x00,  // padding 12 to 15
        0x00, 0x00, 0x80, 0x3F,  // tint red 1 at 16
        0x00, 0x00, 0x00, 0x3F,  // tint green 0.5
        0x00, 0x00, 0x80, 0x3E,  // tint blue 0.25
        0x00, 0x00, 0x80, 0x3F,  // tint alpha 1
        0x00, 0x00, 0x00, 0x3F,  // center x 0.5 at 32
        0x00, 0x00, 0x80, 0x3E,  // center y 0.25
        0x00, 0x00, 0x00, 0x00,  // mode 0 at 40
        0x00, 0x00, 0x00, 0x00,  // padding 44 to 47
    ]

    /// A model of the fixtures with nothing stored, so every value is its kind's default.
    private static let defaults = ParameterModel(specs: EffectParameterSpec.all, restoring: [:])

    // MARK: - Restoring and the states

    @Test("a model restored from nothing has the fixtures' default of each parameter, in declaration order")
    func restoredFromNothingHasDefaults() {
        #expect(
            Self.defaults.states == [
                EffectParameterState(spec: .strength, value: .float(0.5)),
                EffectParameterState(spec: .rings, value: .int(4)),
                EffectParameterState(spec: .inverted, value: .bool(false)),
                EffectParameterState(spec: .tint, value: .color(SIMD4<Float>(1, 0.5, 0.25, 1))),
                EffectParameterState(spec: .center, value: .vector2(SIMD2<Float>(0.5, 0.25))),
                EffectParameterState(spec: .mode, value: .choice(0)),
            ])
    }

    @Test("restoring clamps a stored value of the declared kind into its range, so a stored rings 99 reads back as 16")
    func restoringClampsOutOfRangeValues() {
        let model = ParameterModel(specs: [.rings], restoring: ["rings": .int(99)])
        #expect(model.values == ["rings": .int(16)])
    }

    @Test("restoring drops a stored id that no spec declares, so an id the manifest removed is gone")
    func restoringDropsUndeclaredIds() {
        let model = ParameterModel(specs: [.rings], restoring: ["rings": .int(2), "gone": .bool(true)])
        #expect(model.values == ["rings": .int(2)])
    }

    @Test("states pair each spec with its current value, in declaration order, so a stored choice shows its index")
    func statesFollowDeclarationOrder() {
        let model = ParameterModel(specs: [.rings, .mode], restoring: ["mode": .choice(1)])
        #expect(
            model.states == [
                EffectParameterState(spec: .rings, value: .int(4)),
                EffectParameterState(spec: .mode, value: .choice(1)),
            ])
    }

    @Test("a model with no specs has no states, and its block is EffectParameterBlock.none")
    func emptySpecsGiveNoStatesAndNoneBlock() {
        let model = ParameterModel(specs: [], restoring: ["rings": .int(2)])
        #expect(model.states == [])
        #expect(model.block == EffectParameterBlock.none)
    }

    // MARK: - The block

    @Test("the block of the defaults packs each default at its offset, so the fixtures pack to the 48 default bytes")
    func defaultsPackToDefaultBytes() {
        #expect(Self.defaults.block.bytes == Self.defaultBytes)
    }

    @Test("a value change repacks the block to the golden table, so the six example values pack to the 48 bytes of the spec")
    func valueChangesRepackToGoldenTable() throws {
        let model = try #require(
            Self.defaults.setting("strength", to: .float(0.75))?
                .setting("rings", to: .int(7))?
                .setting("inverted", to: .bool(true))?
                .setting("tint", to: .color(SIMD4<Float>(0.25, 0.5, 0.75, 1)))?
                .setting("center", to: .vector2(SIMD2<Float>(0.5, 1)))?
                .setting("mode", to: .choice(1)))
        #expect(model.block.bytes == Self.goldenBytes)
    }

    // MARK: - Setting a value

    @Test("setting a float beyond its range stores it clamped to the range, so strength 7 becomes 1.0")
    func settingClampsToRange() throws {
        let model = try #require(Self.defaults.setting("strength", to: .float(7)))
        #expect(model.values["strength"] == EffectParameterValue.float(1))
    }

    @Test("setting a value equal to the current one still returns a model, and that model equals the receiver")
    func settingUnchangedValueReturnsEqualModel() {
        #expect(Self.defaults.setting("rings", to: .int(4)) == Self.defaults)
    }

    @Test("setting an id no spec declares returns nil")
    func settingUndeclaredIdIsNil() {
        #expect(Self.defaults.setting("ghost", to: .float(0.5)) == nil)
    }

    @Test("setting a value of another case than the declared kind returns nil, so rings given a float is refused")
    func settingWrongCaseIsNil() {
        #expect(Self.defaults.setting("rings", to: .float(3)) == nil)
    }

    @Test("setting on a model with no specs returns nil for any id, because no spec declares it")
    func settingOnEmptyModelIsNil() {
        let empty = ParameterModel(specs: [], restoring: [:])
        #expect(empty.setting("strength", to: .float(0.5)) == nil)
    }

    @Test("setting leaves the receiver as it was, since a model is a value")
    func settingLeavesReceiverUnchanged() throws {
        let changed = try #require(Self.defaults.setting("rings", to: .int(9)))
        #expect(changed.values["rings"] == EffectParameterValue.int(9))
        #expect(Self.defaults.values["rings"] == EffectParameterValue.int(4))
    }

    @Test("setting then resetting returns every value to its kind's default, so the model equals the defaults again")
    func resettingAfterSettingRestoresDefaults() throws {
        let changed = try #require(Self.defaults.setting("rings", to: .int(9)))
        #expect(changed.resetting() == Self.defaults)
    }

    // MARK: - Respecifying

    @Test("respecified keeps the value of an id whose type is unchanged, so rings 9 stays 9 under a new label")
    func respecifiedKeepsValueOfSameIdAndType() {
        let relabeled = EffectParameterSpec(id: "rings", label: "Count", kind: .int(min: 1, max: 16, defaultValue: 4))
        let model = ParameterModel(specs: [.rings], restoring: ["rings": .int(9)]).respecified([relabeled])
        #expect(model.values == ["rings": .int(9)])
    }

    @Test("respecified clamps a value to a narrowed range, so rings 9 under a maximum of 8 becomes 8")
    func respecifiedClampsToNarrowedRange() {
        let narrowed = EffectParameterSpec(id: "rings", label: "Rings", kind: .int(min: 1, max: 8, defaultValue: 4))
        let model = ParameterModel(specs: [.rings], restoring: ["rings": .int(9)]).respecified([narrowed])
        #expect(model.values == ["rings": .int(8)])
    }

    @Test("respecified gives a new parameter its default, so inverted added to rings 9 starts at false")
    func respecifiedGivesNewParameterDefault() {
        let model = ParameterModel(specs: [.rings], restoring: ["rings": .int(9)]).respecified([.rings, .inverted])
        #expect(model.values == ["rings": .int(9), "inverted": .bool(false)])
    }

    @Test("respecified drops a parameter that is no longer declared, so rings is gone once the specs omit it")
    func respecifiedDropsRemovedParameter() {
        let model = ParameterModel(specs: [.rings, .inverted], restoring: ["rings": .int(9)]).respecified([.inverted])
        #expect(model.values == ["inverted": .bool(false)])
        #expect(model.states == [EffectParameterState(spec: .inverted, value: .bool(false))])
    }

    @Test("respecified gives a parameter whose type changed its default, so a choice stored under a bool id becomes the bool default")
    func respecifiedGivesChangedTypeDefault() {
        let asBool = EffectParameterSpec(id: "mode", label: "Mode", kind: .bool(defaultValue: true))
        let model = ParameterModel(specs: [.mode], restoring: ["mode": .choice(1)]).respecified([asBool])
        #expect(model.values == ["mode": .bool(true)])
    }

    @Test("respecified lays the block out for the new specs, so a field that moves to a later offset moves its bytes")
    func respecifiedRepacksUnderNewLayout() {
        let model = ParameterModel(specs: [.rings], restoring: ["rings": .int(9)]).respecified([.inverted, .rings])
        #expect(model.block.bytes == [0x00, 0x00, 0x00, 0x00, 0x09, 0x00, 0x00, 0x00] + [UInt8](repeating: 0, count: 8))
    }
}
