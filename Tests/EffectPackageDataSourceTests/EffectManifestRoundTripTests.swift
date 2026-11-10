import Domain
import EffectPackageDataSource
import Foundation
import TestSupport
import Testing

/// The property half: for any manifest the shape allows, writing it out as JSON and decoding it
/// back gives the same manifest. The seed names the case, so a failure replays by its seed.
@Suite("EffectManifest round trip", .timeLimit(.minutes(1)))
struct EffectManifestRoundTripTests {
    /// Characters that need escaping in JSON, that are not ASCII, that are two scalars wide and
    /// that only a careless decoder would trim or split, the no-break space and the ideographic
    /// space (whitespace that is not ASCII) among them.
    private static let alphabet: [Character] = [
        "a", "Z", "7", " ", "-", "_", "é", "日", "本", "🎞", "👩‍💻", "\"", "\\", "/", "\n", "\t", "{", "}", "[", ",", ":", "\u{7f}", "\u{a0}",
        "\u{3000}",
    ]

    /// Whitespace around a name: ASCII, a no-break space and an ideographic space.
    private static let padding = " \t\n\u{a0}\u{3000}"

    private static func text(_ generator: inout SeededGenerator, length: ClosedRange<Int>) -> String {
        String((0..<Int.random(in: length, using: &generator)).map { _ in alphabet.randomElement(using: &generator) ?? "a" })
    }

    /// Text that survives the name's trim and is not empty after it.
    private static func name(_ generator: inout SeededGenerator) -> String {
        let trimmed = text(&generator, length: 1...24).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "x" : trimmed
    }

    private static func optionalText(_ generator: inout SeededGenerator) -> String? {
        Bool.random(using: &generator) ? text(&generator, length: 0...40) : nil
    }

    /// One of each kind the manifest has, built to keep every rule: a range with room in it and a
    /// default inside, options that differ.
    private static let kinds: [@Sendable (inout SeededGenerator) -> EffectParameterKind] = [
        { generator in
            let min = Float.random(in: -100..<0, using: &generator)
            let max = Float.random(in: 1...100, using: &generator)
            let step = Bool.random(using: &generator) ? Float.random(in: 0.01...(max - min), using: &generator) : nil
            return .float(min: min, max: max, step: step, defaultValue: Float.random(in: min...max, using: &generator))
        },
        { generator in
            let min = Int32.random(in: -1000..<0, using: &generator)
            let max = Int32.random(in: 1...1000, using: &generator)
            return .int(min: min, max: max, defaultValue: Int32.random(in: min...max, using: &generator))
        },
        { generator in .bool(defaultValue: Bool.random(using: &generator)) },
        { generator in
            .color(defaultValue: SIMD4<Float>((0..<4).map { _ in Float.random(in: 0...1, using: &generator) }))
        },
        { generator in
            let min = SIMD2<Float>((0..<2).map { _ in Float.random(in: -100..<0, using: &generator) })
            let max = SIMD2<Float>((0..<2).map { _ in Float.random(in: 1...100, using: &generator) })
            let value = SIMD2<Float>((0..<2).map { Float.random(in: min[$0]...max[$0], using: &generator) })
            return .vector2(min: min, max: max, defaultValue: value)
        },
        { generator in
            let count = Int.random(in: 1...32, using: &generator)
            let options = (0..<count).map { "\($0): \(text(&generator, length: 0...8))" }
            return .choice(options: options, defaultIndex: Int.random(in: 0..<count, using: &generator))
        },
    ]

    /// Between none and the 32 the manifest allows, of any kind, with ids that differ and labels that survive the trim.
    private static func parameters(_ generator: inout SeededGenerator) -> [EffectParameterSpec] {
        let count = Bool.random(using: &generator) ? 0 : Int.random(in: 1...32, using: &generator)
        return (0..<count).map { index in
            let kind = kinds[Int.random(in: 0..<kinds.count, using: &generator)]
            return EffectParameterSpec(id: "p\(index)", label: name(&generator), kind: kind(&generator))
        }
    }

    private static func manifest(seed: UInt64) -> EffectManifest {
        var generator = SeededGenerator(seed: seed)
        return EffectManifest(
            formatVersion: EffectManifestDecoding.supportedFormatVersion,
            name: name(&generator),
            author: optionalText(&generator),
            description: optionalText(&generator),
            thumbnail: optionalText(&generator),
            parameters: parameters(&generator))
    }

    @Test("encoding a manifest and decoding it again gives the manifest back", arguments: Seeds.range(0..<64))
    func roundTrips(seed: UInt64) throws {
        let manifest = Self.manifest(seed: seed)

        let json = String(decoding: try JSONEncoder().encode(manifest), as: UTF8.self)

        #expect(EffectManifestDecoding.decode(json) == .success(manifest))
    }

    @Test(
        "a name and the labels padded with whitespace decode to the name and the labels, and the rest is kept as written",
        arguments: Seeds.range(0..<32))
    func paddingIsTrimmed(seed: UInt64) throws {
        let manifest = Self.manifest(seed: seed)
        let padded = EffectManifest(
            formatVersion: manifest.formatVersion, name: Self.padding + manifest.name + String(Self.padding.reversed()), author: manifest.author,
            description: manifest.description, thumbnail: manifest.thumbnail,
            parameters: manifest.parameters.map {
                EffectParameterSpec(id: $0.id, label: Self.padding + $0.label + String(Self.padding.reversed()), kind: $0.kind)
            })

        let json = String(decoding: try JSONEncoder().encode(padded), as: UTF8.self)

        #expect(EffectManifestDecoding.decode(json) == .success(manifest))
    }
}
