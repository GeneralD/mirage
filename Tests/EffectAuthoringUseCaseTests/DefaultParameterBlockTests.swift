import Domain
import EffectAuthoringUseCase
import TestSupport
import Testing

@Suite("DefaultParameterBlock")
struct DefaultParameterBlockTests {
    @Test("no parameters make `.none`, which is 16 bytes of zero")
    func noParametersMakeNone() {
        let block = DefaultParameterBlock.make(for: [])
        #expect(block == EffectParameterBlock.none)
        #expect(block.bytes == [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    }

    @Test("the Vignette's two floats pack at their defaults, 0.5 then 0.8, and the 8-byte stride is padded to 16 bytes")
    func vignetteDefaults() {
        let block = DefaultParameterBlock.make(for: [
            spec("strength", .float(min: 0, max: 1, step: nil, defaultValue: 0.5)),
            spec("radius", .float(min: 0, max: 1, step: nil, defaultValue: 0.8)),
        ])
        let expected: [UInt8] = [0x00, 0x00, 0x00, 0x3F, 0xCD, 0xCC, 0x4C, 0x3F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        #expect(block.bytes == expected)
    }

    @Test("the Pixelate's int blockSize packs its default 8 as four little-endian bytes, then 12 bytes of zero padding")
    func pixelateDefaults() {
        let block = DefaultParameterBlock.make(for: [spec("blockSize", .int(min: 1, max: 64, defaultValue: 8))])
        let expected: [UInt8] = [0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        #expect(block.bytes == expected)
    }

    @Test("the Duotone's two colours and its float pack at their defaults, and the 48-byte stride's padding is zero")
    func duotoneDefaults() {
        let block = DefaultParameterBlock.make(for: [
            spec("shadows", .color(defaultValue: SIMD4<Float>(0.05, 0.05, 0.25, 1))),
            spec("highlights", .color(defaultValue: SIMD4<Float>(1, 0.85, 0.5, 1))),
            spec("amount", .float(min: 0, max: 1, step: nil, defaultValue: 1)),
        ])
        let expected: [UInt8] = [
            0xCD, 0xCC, 0x4C, 0x3D, 0xCD, 0xCC, 0x4C, 0x3D, 0x00, 0x00, 0x80, 0x3E, 0x00, 0x00, 0x80, 0x3F,
            0x00, 0x00, 0x80, 0x3F, 0x9A, 0x99, 0x59, 0x3F, 0x00, 0x00, 0x00, 0x3F, 0x00, 0x00, 0x80, 0x3F,
            0x00, 0x00, 0x80, 0x3F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        ]
        #expect(block.bytes == expected)
    }

    @Test("the Parameter Tour packs every kind at its default, with the bool, the choice and the padding each in place")
    func parameterTourDefaults() {
        let block = DefaultParameterBlock.make(for: [
            spec("strength", .float(min: 0, max: 1, step: 0.05, defaultValue: 0.5)),
            spec("reach", .int(min: 1, max: 8, defaultValue: 4)),
            spec("inverted", .bool(defaultValue: false)),
            spec("tint", .color(defaultValue: SIMD4<Float>(1, 0.8, 0.6, 1))),
            spec("center", .vector2(min: SIMD2<Float>(0, 0), max: SIMD2<Float>(1, 1), defaultValue: SIMD2<Float>(0.5, 0.5))),
            spec("mode", .choice(options: ["Soft", "Hard"], defaultIndex: 0)),
        ])
        let expected: [UInt8] = [
            0x00, 0x00, 0x00, 0x3F, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x80, 0x3F, 0xCD, 0xCC, 0x4C, 0x3F, 0x9A, 0x99, 0x19, 0x3F, 0x00, 0x00, 0x80, 0x3F,
            0x00, 0x00, 0x00, 0x3F, 0x00, 0x00, 0x00, 0x3F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        ]
        #expect(block.bytes == expected)
    }

    @Test("a bool whose default is true packs as the uint 1")
    func boolDefaultTrueIsOne() {
        let block = DefaultParameterBlock.make(for: [spec("inverted", .bool(defaultValue: true))])
        let expected: [UInt8] = [0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        #expect(block.bytes == expected)
    }

    @Test("a choice whose default index is 1 packs as the uint 1")
    func choiceDefaultIndexOneIsOne() {
        let block = DefaultParameterBlock.make(for: [spec("mode", .choice(options: ["Soft", "Hard"], defaultIndex: 1))])
        let expected: [UInt8] = [0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        #expect(block.bytes == expected)
    }

    @Test("an int whose default is -3 packs as its two's complement bytes, 0xFD 0xFF 0xFF 0xFF")
    func negativeIntDefaultIsTwosComplement() {
        let block = DefaultParameterBlock.make(for: [spec("offset", .int(min: -10, max: 10, defaultValue: -3))])
        let expected: [UInt8] = [0xFD, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        #expect(block.bytes == expected)
    }

    @Test("a vector2 whose default is (0.25, 0.75) packs as two little-endian floats")
    func vector2DefaultIsTwoFloats() {
        let block = DefaultParameterBlock.make(for: [
            spec("center", .vector2(min: SIMD2<Float>(0, 0), max: SIMD2<Float>(1, 1), defaultValue: SIMD2<Float>(0.25, 0.75)))
        ])
        let expected: [UInt8] = [0x00, 0x00, 0x80, 0x3E, 0x00, 0x00, 0x40, 0x3F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        #expect(block.bytes == expected)
    }

    @Test(
        "a block is as long as its layout's stride but never shorter than 16 bytes, and every byte outside a field is zero",
        arguments: Seeds.range(0..<32))
    func lengthAndPaddingFollowTheLayout(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let specs = randomSpecs(&generator)
        let layout = EffectParameterLayout(specs)
        let block = DefaultParameterBlock.make(for: specs)
        #expect(block.bytes.count == max(layout.stride, 16))
        let fieldBytes = Set(layout.fields.flatMap { $0.offset..<$0.offset + $0.type.size })
        for (index, byte) in block.bytes.enumerated() where !fieldBytes.contains(index) {
            #expect(byte == 0, "byte \(index) is padding and must be zero")
        }
    }

    private func spec(_ id: String, _ kind: EffectParameterKind) -> EffectParameterSpec {
        EffectParameterSpec(id: id, label: id, kind: kind)
    }

    /// Up to the 32 parameters a manifest allows, each with a random kind and random defaults.
    private func randomSpecs(_ generator: inout SeededGenerator) -> [EffectParameterSpec] {
        let count = Int.random(in: 0...32, using: &generator)
        return (0..<count).map { index in
            spec("p\(index)", randomKind(&generator))
        }
    }

    private func randomKind(_ generator: inout SeededGenerator) -> EffectParameterKind {
        let kind = Int.random(in: 0..<6, using: &generator)
        let first = Float.random(in: 0...1, using: &generator)
        let second = Float.random(in: 0...1, using: &generator)
        let option = Int.random(in: 0...2, using: &generator)
        switch kind {
        case 0: return .float(min: 0, max: 1, step: nil, defaultValue: first)
        case 1: return .int(min: -100, max: 100, defaultValue: Int32(option) - 1)
        case 2: return .bool(defaultValue: first < second)
        case 3: return .color(defaultValue: SIMD4<Float>(first, second, first, 1))
        case 4: return .vector2(min: SIMD2<Float>(0, 0), max: SIMD2<Float>(1, 1), defaultValue: SIMD2<Float>(first, second))
        default: return .choice(options: ["a", "b", "c"], defaultIndex: option)
        }
    }
}
