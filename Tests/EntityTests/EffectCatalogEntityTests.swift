import Entity
import Foundation
import TestSupport
import Testing

/// A random string over characters that stress a JSON round trip: quotes, a backslash, a
/// slash, a newline, whitespace, multi-byte letters and an emoji.
private func randomText(_ generator: inout SeededGenerator) -> String {
    let alphabet = Array("aZ09 _-./\\\"\n\t日本語é🙂")
    let length = Int.random(in: 0...12, using: &generator)
    return String((0..<length).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &generator)] })
}

private func maybe(_ generator: inout SeededGenerator) -> String? {
    Bool.random(using: &generator) ? randomText(&generator) : nil
}

@Suite("EffectID")
struct EffectIDTests {
    @Test("the persisted form of an origin is its raw value, so a case is never renamed")
    func originRawValues() {
        #expect(EffectOrigin.allCases.map(\.rawValue) == ["bundled", "package"])
    }

    @Test("the same key under another origin is another effect")
    func originIsPartOfTheIdentity() {
        #expect(EffectID(origin: .bundled, key: "a") != EffectID(origin: .package, key: "a"))
        #expect(Set([EffectID(origin: .bundled, key: "a"), EffectID(origin: .bundled, key: "a")]).count == 1)
    }

    @Test("an id survives encode and decode, whatever characters its key has", arguments: Seeds.range(0..<32))
    func codableRoundTrip(seed: UInt64) throws {
        var generator = SeededGenerator(seed: seed)
        let id = EffectID(origin: EffectOrigin.allCases.randomElement(using: &generator) ?? .bundled, key: randomText(&generator))
        let decoded = try JSONDecoder().decode(EffectID.self, from: JSONEncoder().encode(id))
        #expect(decoded == id)
    }

    @Test("the JSON form is pinned: what the selection store of a later issue will persist")
    func jsonForm() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(EffectID(origin: .package, key: "Glitch"))
        #expect(String(decoding: data, as: UTF8.self) == #"{"key":"Glitch","origin":"package"}"#)
    }
}

@Suite("EffectManifest")
struct EffectManifestTests {
    @Test("a manifest survives encode and decode, optional fields present or absent", arguments: Seeds.range(0..<32))
    func codableRoundTrip(seed: UInt64) throws {
        var generator = SeededGenerator(seed: seed)
        let manifest = EffectManifest(
            formatVersion: Int.random(in: 0...5, using: &generator),
            name: randomText(&generator),
            author: maybe(&generator),
            description: maybe(&generator))
        let decoded = try JSONDecoder().decode(EffectManifest.self, from: JSONEncoder().encode(manifest))
        #expect(decoded == manifest)
    }

    @Test("author and description are optional; formatVersion and name are not")
    func requiredKeys() throws {
        let decoder = JSONDecoder()
        let minimal = try decoder.decode(EffectManifest.self, from: Data(#"{"formatVersion":1,"name":"Glitch"}"#.utf8))
        #expect(minimal == EffectManifest(formatVersion: 1, name: "Glitch"))

        #expect(throws: DecodingError.self) { try decoder.decode(EffectManifest.self, from: Data(#"{"formatVersion":1}"#.utf8)) }
        #expect(throws: DecodingError.self) { try decoder.decode(EffectManifest.self, from: Data(#"{"name":"Glitch"}"#.utf8)) }
        #expect(throws: DecodingError.self) { try decoder.decode(EffectManifest.self, from: Data(#"{"formatVersion":"1","name":"Glitch"}"#.utf8)) }
    }

    @Test("a key this build does not know is ignored, `parameters` included: a newer package still reads")
    func unknownKeysAreIgnored() throws {
        let json = #"{"formatVersion":1,"name":"Glitch","author":"me","parameters":[{"id":"amount","type":"float"}],"license":"MIT"}"#
        let manifest = try JSONDecoder().decode(EffectManifest.self, from: Data(json.utf8))
        #expect(manifest == EffectManifest(formatVersion: 1, name: "Glitch", author: "me"))
    }
}

@Suite("EffectPackageListing")
struct EffectPackageListingTests {
    private let id = EffectID(origin: .package, key: "glitch")

    @Test("a listing is known by the id of its package, ready or broken")
    func listingId() {
        let package = EffectPackage(
            id: id, manifest: EffectManifest(formatVersion: 1, name: "Glitch"), source: EffectSource(name: "Glitch", source: "kernel void effect() {}"))
        #expect(EffectPackageListing.ready(package).id == id)
        #expect(EffectPackageListing.broken(id, .sourceMissing).id == id)
    }

    @Test("an inventory with nothing in it watches nothing")
    func emptyInventory() {
        #expect(EffectPackageInventory.empty.listings.isEmpty)
        #expect(EffectPackageInventory.empty.watchSet == EffectWatchSet(directories: [], files: []))
    }
}
