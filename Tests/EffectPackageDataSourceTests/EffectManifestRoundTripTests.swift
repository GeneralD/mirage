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
    /// that only a careless decoder would trim or split.
    private static let alphabet: [Character] = [
        "a", "Z", "7", " ", "-", "_", "é", "日", "本", "🎞", "👩‍💻", "\"", "\\", "/", "\n", "\t", "{", "}", "[", ",", ":", "\u{7f}",
    ]

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

    private static func manifest(seed: UInt64) -> EffectManifest {
        var generator = SeededGenerator(seed: seed)
        return EffectManifest(
            formatVersion: EffectManifestDecoding.supportedFormatVersion,
            name: name(&generator),
            author: optionalText(&generator),
            description: optionalText(&generator),
            thumbnail: optionalText(&generator))
    }

    @Test("encoding a manifest and decoding it again gives the manifest back", arguments: Seeds.range(0..<64))
    func roundTrips(seed: UInt64) throws {
        let manifest = Self.manifest(seed: seed)

        let json = String(decoding: try JSONEncoder().encode(manifest), as: UTF8.self)

        #expect(EffectManifestDecoding.decode(json) == .success(manifest))
    }

    @Test("a name padded with whitespace decodes to the name, and the rest is kept as written", arguments: Seeds.range(0..<32))
    func paddingIsTrimmed(seed: UInt64) throws {
        let manifest = Self.manifest(seed: seed)
        let padded = EffectManifest(
            formatVersion: manifest.formatVersion, name: " \t\n" + manifest.name + "\n \t", author: manifest.author,
            description: manifest.description, thumbnail: manifest.thumbnail)

        let json = String(decoding: try JSONEncoder().encode(padded), as: UTF8.self)

        #expect(EffectManifestDecoding.decode(json) == .success(manifest))
    }
}
