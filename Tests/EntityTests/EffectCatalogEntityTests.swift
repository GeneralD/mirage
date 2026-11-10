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

    @Test("a key this build does not know is ignored: a newer package still reads")
    func unknownKeysAreIgnored() throws {
        let json = #"{"formatVersion":1,"name":"Glitch","author":"me","license":"MIT","inputs":["camera"]}"#
        let manifest = try JSONDecoder().decode(EffectManifest.self, from: Data(json.utf8))
        #expect(manifest == EffectManifest(formatVersion: 1, name: "Glitch", author: "me"))
    }

    @Test("`parameters` is read when it is there, and is the empty list when it is absent or null")
    func parametersAreOptional() throws {
        let decoder = JSONDecoder()
        let parameter = #"{"id":"amount","label":"Amount","type":"bool","default":true}"#
        let spec = EffectParameterSpec(id: "amount", label: "Amount", kind: .bool(defaultValue: true))

        let with = try decoder.decode(EffectManifest.self, from: Data(#"{"formatVersion":1,"name":"Glitch","parameters":[\#(parameter)]}"#.utf8))
        let null = try decoder.decode(EffectManifest.self, from: Data(#"{"formatVersion":1,"name":"Glitch","parameters":null}"#.utf8))

        #expect(with == EffectManifest(formatVersion: 1, name: "Glitch", parameters: [spec]))
        #expect(null == EffectManifest(formatVersion: 1, name: "Glitch"))
        #expect(EffectManifest(formatVersion: 1, name: "Glitch").parameters.isEmpty)
    }
}

@Suite("EffectPackageListing")
struct EffectPackageListingTests {
    private let id = EffectID(origin: .package, key: "glitch")

    @Test("a listing is known by the id of its package, ready or broken")
    func listingId() {
        let package = EffectPackage(
            id: id, manifest: EffectManifest(formatVersion: 1, name: "Glitch"),
            source: EffectSource(name: "Glitch", source: "kernel void effect() {}"))
        #expect(EffectPackageListing.ready(package).id == id)
        #expect(EffectPackageListing.broken(id, .sourceMissing).id == id)
    }

    @Test("an inventory with nothing in it watches nothing")
    func emptyInventory() {
        #expect(EffectPackageInventory.empty.listings.isEmpty)
        #expect(EffectPackageInventory.empty.watchSet == EffectWatchSet(directories: [], files: []))
    }
}

@Suite("EffectCatalogState")
struct EffectCatalogStateTests {
    private let chromatic = EffectCatalogEntry(
        id: EffectID(origin: .bundled, key: "chromatic"), displayName: "Chromatic", origin: .bundled, availability: .ready)
    private let glitch = EffectCatalogEntry(
        id: EffectID(origin: .package, key: "glitch"), displayName: "Glitch", origin: .package, availability: .ready)
    private let parameters = [
        EffectParameterState(spec: EffectParameterSpec(id: "strength", label: "Strength", kind: Kinds.float), value: .float(0.25)),
        EffectParameterState(spec: EffectParameterSpec(id: "rings", label: "Rings", kind: Kinds.int), value: .int(6)),
    ]

    @Test("a state given no parameters declares none")
    func noParametersByDefault() {
        let state = EffectCatalogState(entries: [chromatic], selection: chromatic.id)
        #expect(state.parameters == [])
    }

    @Test("a state keeps the parameters it was given, in the order it was given them")
    func parametersKeepTheirOrder() {
        let state = EffectCatalogState(entries: [chromatic], selection: chromatic.id, parameters: parameters)
        #expect(state.parameters == parameters)
        #expect(state.parameters.map(\.spec.id) == ["strength", "rings"])
    }

    @Test("two states that differ only in their parameters are different states")
    func differentParametersAreDifferentStates() {
        let bare = EffectCatalogState(entries: [chromatic], selection: chromatic.id)
        let withParameters = EffectCatalogState(entries: [chromatic], selection: chromatic.id, parameters: parameters)
        #expect(bare != withParameters)
        #expect(EffectCatalogState(entries: [chromatic], selection: chromatic.id, parameters: Array(parameters.reversed())) != withParameters)
    }

    @Test("two states with the same parameters are the same value, so a set keeps one of them")
    func equalParametersAreOneValue() {
        let first = EffectCatalogState(entries: [chromatic], selection: chromatic.id, parameters: parameters)
        let second = EffectCatalogState(entries: [chromatic], selection: chromatic.id, parameters: parameters)
        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
        #expect(Set([first, second]).count == 1)
    }

    @Test("the parameters do not hide a difference in the entries, the selection or the outcome")
    func parametersDoNotMaskOtherFields() {
        let base = EffectCatalogState(entries: [chromatic], selection: chromatic.id, outcome: .prepared, parameters: parameters)
        #expect(base != EffectCatalogState(entries: [glitch], selection: chromatic.id, outcome: .prepared, parameters: parameters))
        #expect(base != EffectCatalogState(entries: [chromatic], selection: glitch.id, outcome: .prepared, parameters: parameters))
        #expect(base != EffectCatalogState(entries: [chromatic], selection: chromatic.id, outcome: nil, parameters: parameters))
        #expect(
            base
                != EffectCatalogState(
                    entries: [chromatic], selection: chromatic.id, outcome: .failed(.compileFailed), parameters: parameters))
    }
}
