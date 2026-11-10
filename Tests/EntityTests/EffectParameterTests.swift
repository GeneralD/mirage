import Entity
import Foundation
import TestSupport
import Testing

@Suite("EffectParameterSpec")
struct EffectParameterSpecTests {
    @Test("two specs are the same value only when id, label and kind all agree")
    func specIdentity() {
        let base = EffectParameterSpec(id: "strength", label: "Strength", kind: Kinds.float)
        #expect(base == EffectParameterSpec(id: "strength", label: "Strength", kind: Kinds.float))
        #expect(base != EffectParameterSpec(id: "amount", label: "Strength", kind: Kinds.float))
        #expect(base != EffectParameterSpec(id: "strength", label: "Amount", kind: Kinds.float))
        #expect(base != EffectParameterSpec(id: "strength", label: "Strength", kind: Kinds.int))
        #expect(Set([base, base]).count == 1)
    }

    @Test("a kind with the same case but another range, step or default is another kind")
    func kindsCompareByTheirParts() {
        let base = EffectParameterKind.float(min: 0, max: 1, step: nil, defaultValue: 0.5)
        #expect(base != .float(min: 0, max: 2, step: nil, defaultValue: 0.5))
        #expect(base != .float(min: 0, max: 1, step: 0.1, defaultValue: 0.5))
        #expect(base != .float(min: 0, max: 1, step: nil, defaultValue: 0.25))
        #expect(EffectParameterKind.choice(options: ["a", "b"], defaultIndex: 0) != .choice(options: ["b", "a"], defaultIndex: 0))
        #expect(EffectParameterKind.choice(options: ["a", "b"], defaultIndex: 0) != .choice(options: ["a", "b"], defaultIndex: 1))
    }

    @Test("a state pairs a spec with its current value")
    func stateIsAPair() {
        let spec = EffectParameterSpec(id: "rings", label: "Rings", kind: Kinds.int)
        let state = EffectParameterState(spec: spec, value: .int(6))
        #expect(state.spec == spec)
        #expect(state.value == .int(6))
        #expect(state != EffectParameterState(spec: spec, value: .int(7)))
        #expect(state != EffectParameterState(spec: spec, value: .choice(6)))
    }
}

@Suite("EffectParameterValue")
struct EffectParameterValueTests {
    private static let samples: [EffectParameterValue] = [
        .float(0.25), .int(-3), .bool(true), .color(SIMD4<Float>(1, 0.5, 0.25, 1)), .vector2(SIMD2<Float>(0.5, 0.75)), .choice(2),
    ]

    @Test("a value survives encode and decode, whichever case it is", arguments: samples)
    func codableRoundTrip(value: EffectParameterValue) throws {
        let decoded = try JSONDecoder().decode(EffectParameterValue.self, from: JSONEncoder().encode(value))
        #expect(decoded == value)
    }

    @Test("a float, an int and a choice with the same number are three different values")
    func casesAreNotInterchangeable() {
        #expect(EffectParameterValue.float(1) != .int(1))
        #expect(EffectParameterValue.int(1) != .choice(1))
        #expect(EffectParameterValue.bool(true) != .int(1))
    }

    @Test("the JSON form is pinned: what the parameter store of a later issue will persist")
    func jsonForm() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        func json(_ value: EffectParameterValue) throws -> String { String(decoding: try encoder.encode(value), as: UTF8.self) }

        #expect(try json(.float(0.25)) == #"{"float":{"_0":0.25}}"#)
        #expect(try json(.int(-3)) == #"{"int":{"_0":-3}}"#)
        #expect(try json(.bool(true)) == #"{"bool":{"_0":true}}"#)
        #expect(try json(.color(SIMD4<Float>(1, 0.5, 0.25, 1))) == #"{"color":{"_0":[1,0.5,0.25,1]}}"#)
        #expect(try json(.vector2(SIMD2<Float>(0.5, 0.75))) == #"{"vector2":{"_0":[0.5,0.75]}}"#)
        #expect(try json(.choice(2)) == #"{"choice":{"_0":2}}"#)
    }

    @Test("a dictionary of values, the shape one effect is stored in, survives encode and decode")
    func storedShape() throws {
        let stored: [String: EffectParameterValue] = ["strength": .float(0.75), "inverted": .bool(false), "mode": .choice(1)]
        let decoded = try JSONDecoder().decode([String: EffectParameterValue].self, from: JSONEncoder().encode(stored))
        #expect(decoded == stored)
    }
}

/// One row of the golden table: what a list of kinds lays out to.
struct LayoutCase: Sendable, CustomTestStringConvertible {
    let name: String
    let kinds: [EffectParameterKind]
    let types: [EffectParameterFieldType]
    let offsets: [Int]
    let stride: Int

    var testDescription: String { name }
}

let layoutCases: [LayoutCase] = [
    LayoutCase(name: "no parameters", kinds: [], types: [], offsets: [], stride: 0),
    LayoutCase(name: "one float", kinds: [Kinds.float], types: [.float], offsets: [0], stride: 4),
    LayoutCase(name: "one color", kinds: [Kinds.color], types: [.float4], offsets: [0], stride: 16),
    LayoutCase(name: "one vec2", kinds: [Kinds.vector2], types: [.float2], offsets: [0], stride: 8),
    LayoutCase(
        name: "int, bool, choice pack as 4-byte fields", kinds: [Kinds.int, Kinds.bool, Kinds.choice], types: [.int, .uint, .uint],
        offsets: [0, 4, 8], stride: 12),
    LayoutCase(
        name: "a float2 after a float skips 4 bytes", kinds: [Kinds.float, Kinds.vector2], types: [.float, .float2], offsets: [0, 8], stride: 16),
    LayoutCase(
        name: "a float after a float2 needs no skip but pads the end", kinds: [Kinds.vector2, Kinds.float], types: [.float2, .float],
        offsets: [0, 8], stride: 16),
    LayoutCase(
        name: "a float4 after a float skips 12 bytes", kinds: [Kinds.float, Kinds.color], types: [.float, .float4], offsets: [0, 16], stride: 32),
    LayoutCase(
        name: "a float after a float4 pads the end to 16", kinds: [Kinds.color, Kinds.float], types: [.float4, .float], offsets: [0, 16], stride: 32),
    LayoutCase(
        name: "three 4-byte fields around a float2", kinds: [Kinds.float, Kinds.vector2, Kinds.float], types: [.float, .float2, .float],
        offsets: [0, 8, 16], stride: 24),
    LayoutCase(
        name: "a float2 after two floats needs no skip", kinds: [Kinds.float, Kinds.int, Kinds.vector2], types: [.float, .int, .float2],
        offsets: [0, 4, 8], stride: 16),
    LayoutCase(
        name: "a float2 after three floats skips 4 bytes and pads the end", kinds: [Kinds.float, Kinds.int, Kinds.bool, Kinds.vector2],
        types: [.float, .int, .uint, .float2],
        offsets: [0, 4, 8, 16], stride: 24),
    LayoutCase(
        name: "the spec's example manifest is 48 bytes, the number its static_assert names",
        kinds: rippleSpecs.map(\.kind), types: [.float, .int, .uint, .float4, .float2, .uint], offsets: [0, 4, 8, 16, 32, 40], stride: 48),
    LayoutCase(
        name: "32 floats", kinds: Array(repeating: Kinds.float, count: 32), types: Array(repeating: .float, count: 32),
        offsets: (0..<32).map { $0 * 4 }, stride: 128),
    LayoutCase(
        name: "32 colors", kinds: Array(repeating: Kinds.color, count: 32), types: Array(repeating: .float4, count: 32),
        offsets: (0..<32).map { $0 * 16 }, stride: 512),
]

@Suite("EffectParameterLayout")
struct EffectParameterLayoutTests {
    @Test("the layout of a list of parameters is the golden table's offsets and stride", arguments: layoutCases)
    func goldenLayout(_ row: LayoutCase) {
        let layout = EffectParameterLayout(specs(row.kinds))
        #expect(layout.fields.map(\.offset) == row.offsets)
        #expect(layout.fields.map(\.type) == row.types)
        #expect(layout.stride == row.stride)
    }

    @Test("the fields carry the parameter ids in manifest order")
    func fieldsKeepIdsAndOrder() {
        let layout = EffectParameterLayout(rippleSpecs)
        #expect(layout.fields.map(\.id) == ["strength", "rings", "inverted", "tint", "center", "mode"])
    }

    @Test("bool and choice are uint, vec2 is float2, color is float4, float and int keep their names")
    func kindToFieldTypeMapping() {
        #expect(Kinds.float.fieldType == .float)
        #expect(Kinds.int.fieldType == .int)
        #expect(Kinds.bool.fieldType == .uint)
        #expect(Kinds.choice.fieldType == .uint)
        #expect(Kinds.vector2.fieldType == .float2)
        #expect(Kinds.color.fieldType == .float4)
    }

    @Test("a field's size and alignment are 4/4 for float, int and uint, 8/8 for float2, 16/16 for float4")
    func fieldTypeSizes() {
        let table: [EffectParameterFieldType: Int] = [.float: 4, .int: 4, .uint: 4, .float2: 8, .float4: 16]
        #expect(Set(EffectParameterFieldType.allCases) == Set(table.keys), "a new field type needs a row here")
        for (type, size) in table {
            #expect(type.size == size)
            #expect(type.alignment == size)
        }
    }

    @Test(
        "every field sits on its natural alignment, none overlaps the one before, none could sit earlier, and the stride rounds up to the largest alignment",
        arguments: Seeds.range(0..<32))
    func layoutInvariants(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let layout = EffectParameterLayout(randomSpecs(&generator))
        let end = layout.fields.reduce(0) { previousEnd, field in
            #expect(field.offset % field.type.alignment == 0, "\(field.id) is misaligned")
            #expect(field.offset >= previousEnd, "\(field.id) overlaps the field before it")
            #expect(field.offset - previousEnd < field.type.alignment, "\(field.id) could have been placed earlier")
            return field.offset + field.type.size
        }
        let largest = layout.fields.map(\.type.alignment).max() ?? 1
        #expect(layout.stride % largest == 0)
        #expect(layout.stride >= end)
        #expect(layout.stride - end < largest)
    }

    @Test("labels, defaults and ranges do not move a field: only the kinds' field types do", arguments: Seeds.range(0..<32))
    func layoutIgnoresEverythingButFieldTypes(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let original = randomSpecs(&generator)
        let relabelled = original.map { EffectParameterSpec(id: $0.id, label: $0.label + "!", kind: otherKind(sharingFieldTypeWith: $0.kind)) }
        #expect(EffectParameterLayout(relabelled) == EffectParameterLayout(original))
    }
}

@Suite("EffectParameterBlock")
struct EffectParameterBlockTests {
    @Test("a block of no bytes is 16 zeros")
    func emptyBytesBecomeSixteenZeros() {
        #expect(EffectParameterBlock(bytes: []).bytes == [UInt8](repeating: 0, count: 16))
    }

    @Test("bytes shorter than 16 are padded with zeros after them", arguments: [1, 4, 8, 12, 15])
    func shortBytesArePadded(count: Int) {
        let bytes = (0..<count).map { UInt8($0 + 1) }
        let block = EffectParameterBlock(bytes: bytes)
        #expect(block.bytes.count == 16)
        #expect(Array(block.bytes.prefix(count)) == bytes)
        #expect(block.bytes.dropFirst(count).allSatisfy { $0 == 0 })
    }

    @Test("bytes of 16 or more are kept exactly", arguments: [16, 17, 48, 512])
    func longBytesAreKept(count: Int) {
        let bytes = (0..<count).map { UInt8(truncatingIfNeeded: $0 &+ 1) }
        #expect(EffectParameterBlock(bytes: bytes).bytes == bytes)
    }

    @Test("`none` is 16 bytes of zero, the block of an effect without parameters")
    func noneIsSixteenZeros() {
        #expect(EffectParameterBlock.none.bytes == [UInt8](repeating: 0, count: 16))
        #expect(EffectParameterBlock.none == EffectParameterBlock(bytes: []))
        #expect(EffectParameterBlock.minimumLength == 16)
    }

    @Test("a block is never empty, whatever it is built from", arguments: Seeds.range(0..<32))
    func neverEmpty(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let count = Int.random(in: 0...40, using: &generator)
        let bytes = (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        let block = EffectParameterBlock(bytes: bytes)
        #expect(block.bytes.count == max(16, count))
        #expect(Array(block.bytes.prefix(count)) == bytes)
    }

    @Test("two blocks are equal when their bytes are, so 3 bytes and the same 3 bytes padded are one value")
    func equalityIsOverTheBytes() {
        #expect(EffectParameterBlock(bytes: [1, 2, 3]) == EffectParameterBlock(bytes: [1, 2, 3] + [UInt8](repeating: 0, count: 13)))
        #expect(EffectParameterBlock(bytes: [1, 2, 3]) != EffectParameterBlock(bytes: [1, 2, 4]))
    }
}
