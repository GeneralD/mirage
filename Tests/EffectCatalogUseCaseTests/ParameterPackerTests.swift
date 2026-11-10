import Domain
import TestDoubles
import TestSupport
import Testing

@testable import EffectCatalogUseCase

/// The packing of parameter values into a `Parameters` block (`docs/hackathon/mvp-cd/specs/parameters.md`). Each rule
/// the spec states is one test named as that sentence; the golden bytes are written out from the spec, not computed
/// through the packer. The seeded property reads every field back with a reader of its own.
@Suite("ParameterPacker", .timeLimit(.minutes(1)))
struct ParameterPackerTests {
    /// The six fixtures in their layout order: offsets 0, 4, 8, 16, 32 and 40, stride 48.
    private static let specs = EffectParameterSpec.all
    private static let layout = EffectParameterLayout(specs)

    /// The example values of the spec, one per kind.
    private static let goldenValues: [String: EffectParameterValue] = [
        "strength": .float(0.75),
        "rings": .int(7),
        "inverted": .bool(true),
        "tint": .color(SIMD4<Float>(0.25, 0.5, 0.75, 1)),
        "center": .vector2(SIMD2<Float>(0.5, 1)),
        "mode": .choice(1),
    ]

    /// The 48 bytes of `goldenValues`, written out from the spec's table.
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

    /// The 48 bytes of the defaults (`values: [:]`): strength 0.5, rings 4, inverted false, tint (1, 0.5, 0.25, 1),
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

    // MARK: - The golden table and the defaults

    @Test("the example values pack to the 48 bytes the spec writes out, each field at its offset")
    func packsTheGoldenTable() {
        let block = ParameterPacker.pack(values: Self.goldenValues, specs: Self.specs, layout: Self.layout)
        #expect(block.bytes == Self.goldenBytes)
    }

    @Test("a value that is not given packs as its kind's default")
    func missingValuesPackAsDefaults() {
        let block = ParameterPacker.pack(values: [:], specs: Self.specs, layout: Self.layout)
        #expect(block.bytes == Self.defaultBytes)
    }

    @Test("a value for an id that no spec declares is ignored")
    func undeclaredIdsAreIgnored() {
        let block = ParameterPacker.pack(values: ["ghost": .float(1)], specs: Self.specs, layout: Self.layout)
        #expect(block.bytes == Self.defaultBytes)
    }

    // MARK: - Normalization before packing

    @Test("a float beyond its range packs clamped to the range, so strength 7 packs as 1 and rings 99 as 16")
    func rangeIsEnforcedBeforePacking() {
        let block = ParameterPacker.pack(
            values: ["strength": .float(7), "rings": .int(99)], specs: Self.specs, layout: Self.layout)
        #expect(Array(block.bytes[0..<4]) == [0x00, 0x00, 0x80, 0x3F])
        #expect(Array(block.bytes[4..<8]) == [0x10, 0x00, 0x00, 0x00])
    }

    @Test("a float with a step packs rounded to that step, so strength 0.6 packs as 0.5")
    func stepIsEnforcedBeforePacking() {
        let block = ParameterPacker.pack(values: ["strength": .float(0.6)], specs: Self.specs, layout: Self.layout)
        #expect(Array(block.bytes[0..<4]) == [0x00, 0x00, 0x00, 0x3F])
    }

    @Test("a value of another case packs as the kind's default, so rings given a float packs as 4")
    func wrongCasePacksAsDefault() {
        let block = ParameterPacker.pack(values: ["rings": .float(3)], specs: Self.specs, layout: Self.layout)
        #expect(Array(block.bytes[4..<8]) == [0x04, 0x00, 0x00, 0x00])
    }

    @Test("a NaN component packs as the default of that component, so a NaN red packs as the default 1")
    func nanComponentPacksAsDefault() {
        let block = ParameterPacker.pack(
            values: ["tint": .color(SIMD4<Float>(.nan, 0.25, 0.75, 1))], specs: Self.specs, layout: Self.layout)
        #expect(Array(block.bytes[16..<20]) == [0x00, 0x00, 0x80, 0x3F])
    }

    @Test("an int packs as its two's complement, so -2 packs as FE FF FF FF")
    func negativeIntsAreTwosComplement() {
        let offset = EffectParameterSpec(id: "offset", label: "Offset", kind: .int(min: -9, max: 16, defaultValue: 4))
        let block = ParameterPacker.pack(values: ["offset": .int(-2)], specs: [offset], layout: EffectParameterLayout([offset]))
        #expect(Array(block.bytes[0..<4]) == [0xFE, 0xFF, 0xFF, 0xFF])
    }

    @Test("a choice index beyond the options packs as the default index, so index 9 of three options packs as 2")
    func outOfRangeChoicePacksAsDefaultIndex() {
        let pick = EffectParameterSpec(
            id: "pick", label: "Pick", kind: .choice(options: ["a", "b", "c"], defaultIndex: 2))
        let block = ParameterPacker.pack(values: ["pick": .choice(9)], specs: [pick], layout: EffectParameterLayout([pick]))
        #expect(Array(block.bytes[0..<4]) == [0x02, 0x00, 0x00, 0x00])
    }

    // MARK: - Pairing and the block's size

    @Test("a spec with no paired field is skipped, so a layout built from fewer specs packs only the paired ones")
    func unpairedSpecsAreSkipped() {
        let layout = EffectParameterLayout([Self.specs[0]])
        let block = ParameterPacker.pack(values: Self.goldenValues, specs: [Self.specs[0], Self.specs[1]], layout: layout)
        #expect(block.bytes == [0x00, 0x00, 0x40, 0x3F] + [UInt8](repeating: 0, count: 12))
    }

    @Test("a field that does not fit the block is skipped rather than trapping, so the second 16-byte tint is dropped")
    func overflowingFieldsAreSkipped() {
        let layout = EffectParameterLayout([EffectParameterSpec.inverted, EffectParameterSpec.inverted])
        let tint = EffectParameterSpec.tint
        let block = ParameterPacker.pack(values: Self.goldenValues, specs: [tint, tint], layout: layout)
        #expect(block.bytes == Array(Self.goldenBytes[16..<32]))
    }

    @Test("two specs that share an id each pack that id's value in their own field, so [strength, strength] packs twice")
    func duplicateIdsPackByPosition() {
        let strength = EffectParameterSpec.strength
        let layout = EffectParameterLayout([strength, strength])
        let block = ParameterPacker.pack(values: ["strength": .float(0.75)], specs: [strength, strength], layout: layout)
        #expect(block.bytes == [0x00, 0x00, 0x40, 0x3F, 0x00, 0x00, 0x40, 0x3F] + [UInt8](repeating: 0, count: 8))
    }

    @Test("a block is max(stride, 16) bytes long, so the fixtures pack to 48 and a layout of 4 bytes to 16")
    func blockLengthIsAtLeastMinimumLength() {
        #expect(ParameterPacker.pack(values: [:], specs: Self.specs, layout: Self.layout).bytes.count == 48)
        let inverted = [EffectParameterSpec.inverted]
        #expect(ParameterPacker.pack(values: [:], specs: inverted, layout: EffectParameterLayout(inverted)).bytes.count == 16)
    }

    @Test("a single bool packs to a 16-byte block with the flag in its first 4 bytes and zeros after")
    func singleBoolPacksToSixteenBytes() {
        let inverted = [EffectParameterSpec.inverted]
        let block = ParameterPacker.pack(values: ["inverted": .bool(true)], specs: inverted, layout: EffectParameterLayout(inverted))
        #expect(block.bytes == [0x01, 0x00, 0x00, 0x00] + [UInt8](repeating: 0, count: 12))
    }

    @Test("no specs pack to EffectParameterBlock.none, the 16 zero bytes")
    func noSpecsPackToNone() {
        let block = ParameterPacker.pack(values: [:], specs: [], layout: EffectParameterLayout([]))
        #expect(block == EffectParameterBlock.none)
        #expect(block.bytes == [UInt8](repeating: 0, count: 16))
    }

    // MARK: - Seeded properties

    @Test(
        "for any seed, every field reads back as its kind's normalized value, or the default when its id is not given",
        arguments: Seeds.range(0..<200))
    func fieldsReadBackAsNormalized(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let values = Self.randomValues(&generator)
        let block = ParameterPacker.pack(values: values, specs: Self.specs, layout: Self.layout)
        for (spec, field) in zip(Self.specs, Self.layout.fields) {
            let expected = values[spec.id].map { spec.kind.normalized($0) } ?? spec.kind.defaultValue
            #expect(Self.read(spec.kind, field, in: block) == expected, "\(spec.id) at offset \(field.offset)")
        }
    }

    /// The values of one run: a third of the ids are left out, and each given one is drawn for its spec.
    private static func randomValues(_ generator: inout SeededGenerator) -> [String: EffectParameterValue] {
        Self.specs.reduce(into: [String: EffectParameterValue]()) { values, spec in
            guard Int.random(in: 0..<3, using: &generator) != 0 else { return }
            values[spec.id] = randomValue(for: spec.kind, &generator)
        }
    }

    /// A value for `kind`: of its own case half the time, otherwise of the case of a random spec, so some are mismatched.
    private static func randomValue(for kind: EffectParameterKind, _ generator: inout SeededGenerator) -> EffectParameterValue {
        let drawn = Bool.random(using: &generator) ? kind : (Self.specs.map(\.kind).randomElement(using: &generator) ?? kind)
        return ownCase(of: drawn, &generator)
    }

    /// A value of `kind`'s own case, anywhere in or beyond its range, with NaN and the infinities among them.
    private static func ownCase(of kind: EffectParameterKind, _ generator: inout SeededGenerator) -> EffectParameterValue {
        switch kind {
        case .float:
            return .float(edgeFloat(&generator))
        case .int:
            return .int(Int32.random(in: -64...64, using: &generator))
        case .bool:
            return .bool(Bool.random(using: &generator))
        case .color:
            let components = (0..<4).map { _ in edgeFloat(&generator) }
            return .color(SIMD4<Float>(components[0], components[1], components[2], components[3]))
        case .vector2:
            let components = (0..<2).map { _ in edgeFloat(&generator) }
            return .vector2(SIMD2<Float>(components[0], components[1]))
        case .choice:
            return .choice(Int.random(in: -2...8, using: &generator))
        }
    }

    /// A `Float` within, beyond, or never in the fixtures' ranges, with NaN and the infinities among them.
    private static func edgeFloat(_ generator: inout SeededGenerator) -> Float {
        switch Int.random(in: 0..<10, using: &generator) {
        case 0: return .nan
        case 1: return .infinity
        case 2: return -.infinity
        default: return Float.random(in: -8...8, using: &generator)
        }
    }

    /// The field's value as a shader reads it: its words, 4 bytes each and little endian, from its offset, cast to `kind`.
    private static func read(
        _ kind: EffectParameterKind, _ field: EffectParameterLayout.Field, in block: EffectParameterBlock
    ) -> EffectParameterValue {
        let words = (0..<field.type.size / 4).map { wordAt(field.offset + 4 * $0, in: block) }
        let floats = words.map { Float(bitPattern: $0) }
        switch kind {
        case .float:
            return .float(floats[0])
        case .int:
            return .int(Int32(bitPattern: words[0]))
        case .bool:
            return .bool(words[0] != 0)
        case .choice:
            return .choice(Int(words[0]))
        case .vector2:
            return .vector2(SIMD2<Float>(floats[0], floats[1]))
        case .color:
            return .color(SIMD4<Float>(floats[0], floats[1], floats[2], floats[3]))
        }
    }

    /// The 4 bytes at `offset` as one little-endian word.
    private static func wordAt(_ offset: Int, in block: EffectParameterBlock) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { word, byte in word | UInt32(block.bytes[offset + byte]) << (8 * byte) }
    }
}
