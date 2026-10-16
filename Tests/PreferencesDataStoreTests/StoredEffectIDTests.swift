import Domain
import TestDoubles
import TestSupport
import Testing

@testable import PreferencesDataStore

/// Characters that make an id hard to cut: the separator itself (twice as likely as the rest),
/// the origins' own letters, spaces, path-like and escape characters, a combining mark that
/// fuses with whatever precedes it (a colon, here), a joiner, and non-ASCII text.
private let keyAlphabet: [Unicode.Scalar] = [
    ":", ":", ":", "a", "Z", "0", " ", "-", ".", "/", "\\", "_", "é", "\u{0301}", "\u{200D}", "日", "本", "🎞", "\n",
]

/// Words a stored string is made of in the second property: the origins, a near miss of each,
/// the separator and some filler, glued together at random.
private let tokens: [String] = ["bundled", "package", "Bundled", "PACKAGE", "unknown", ":", ":", "glitch", " ", "", "é", "\u{0301}"]

private func randomKey(_ generator: inout SeededGenerator) -> String {
    let count = Int.random(in: 0...12, using: &generator)
    let scalars = (0..<count).map { _ in keyAlphabet[Int.random(in: 0..<keyAlphabet.count, using: &generator)] }
    return String(String.UnicodeScalarView(scalars))
}

private func randomString(_ generator: inout SeededGenerator) -> String {
    let count = Int.random(in: 0...5, using: &generator)
    return (0..<count).map { _ in tokens[Int.random(in: 0..<tokens.count, using: &generator)] }.joined()
}

/// Strict equality: the same Unicode scalars, not merely the same string by canonical equivalence.
private func sameScalars(_ lhs: String, _ rhs: String) -> Bool {
    lhs.unicodeScalars.elementsEqual(rhs.unicodeScalars)
}

@Suite("StoredEffectID")
struct StoredEffectIDTests {
    @Test("an id is stored as its origin, one colon and its key: the form is a contract")
    func exactForm() {
        #expect(StoredEffectID.encode(.bundled("Chromatic Grain")) == "bundled:Chromatic Grain")
        #expect(StoredEffectID.encode(.package("glitch")) == "package:glitch")
        #expect(StoredEffectID.encode(.package("a:b:c")) == "package:a:b:c")
        #expect(StoredEffectID.encode(.package("")) == "package:")
    }

    @Test("each origin has the raw value it is persisted as")
    func originRawValues() {
        #expect(EffectOrigin.allCases.map(\.rawValue).sorted() == ["bundled", "package"])
    }

    @Test(
        "a string is cut at its first colon: the key is everything after it, colons included",
        arguments: [
            ("bundled:Chromatic Grain", EffectID.bundled("Chromatic Grain")),
            ("package:glitch", .package("glitch")),
            ("package:a:b:c", .package("a:b:c")),
            ("package:bundled:x", .package("bundled:x")),
            ("package::", .package(":")),
            ("package: glitch ", .package(" glitch ")),
            ("package:", .package("")),
            ("bundled:日本語 🎞", .bundled("日本語 🎞")),
        ])
    func decodes(stored: String, expected: EffectID) {
        #expect(StoredEffectID.decode(stored) == expected)
    }

    @Test(
        "a string that does not start with an origin and a colon decodes to nothing",
        arguments: [
            "", ":", "glitch", "bundled", "package", ":glitch", "unknown:glitch", "Bundled:x", "PACKAGE:x", " bundled:x", "bundled :x",
            "bundled\u{FF1A}x", "package.glitch", "package/glitch",
        ])
    func rejects(stored: String) {
        #expect(StoredEffectID.decode(stored) == nil)
    }

    @Test("a key that starts with a combining mark still decodes: the colon in front is not fused with it")
    func combiningMarkAfterTheColon() {
        let id = EffectID.package("\u{0301}x")
        let decoded = StoredEffectID.decode(StoredEffectID.encode(id))
        #expect(decoded.map { sameScalars($0.key, id.key) } == true)
        #expect(decoded?.origin == .package)
    }

    @Test("every id survives encode, then decode, whatever its key (seeded)", arguments: standardSeeds)
    func roundTrip(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        for _ in 0..<32 {
            let key = randomKey(&generator)
            for origin in EffectOrigin.allCases {
                let id = EffectID(origin: origin, key: key)
                let decoded = StoredEffectID.decode(StoredEffectID.encode(id))
                #expect(decoded == id, "seed \(seed): \(id)")
                #expect(decoded.map { sameScalars($0.key, key) } == true, "seed \(seed): the key keeps its exact scalars")
            }
        }
    }

    @Test("a string that decodes encodes back to itself, and nothing is read out of a string that does not (seeded)", arguments: standardSeeds)
    func canonicalForm(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        for _ in 0..<64 {
            let stored = randomString(&generator)
            guard let id = StoredEffectID.decode(stored) else { continue }
            #expect(sameScalars(StoredEffectID.encode(id), stored), "seed \(seed): \(stored.debugDescription)")
        }
    }

    @Test("the generators reach the interesting cases: a decodable string, a rejected one, a key with a colon")
    func generatorsCoverTheCases() {
        var generator = SeededGenerator(seed: 0)
        let strings = (0..<2000).map { _ in randomString(&generator) }
        let decoded = strings.compactMap(StoredEffectID.decode)
        #expect(!decoded.isEmpty)
        #expect(decoded.count < strings.count)
        #expect(decoded.contains { $0.key.contains(":") })
        #expect(Set(decoded.map(\.origin)) == Set(EffectOrigin.allCases))
    }
}
