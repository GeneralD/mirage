import EffectPackageDataSource
import Foundation
import Testing

/// `EffectScaffoldTemplate`: the names a new package may take, and the two files the scaffold writes.
/// Every name in a row is one an author could type.
@Suite("EffectScaffoldTemplate", .timeLimit(.minutes(1)))
struct EffectScaffoldTemplateTests {
    static let validNames: [String] = ["a", "A", "7up", "My Glitch", "a-b_c", "x y z", String(repeating: "n", count: 64)]

    static let invalidNames: [String] = [
        "", " a", "a ", "-a", "_a", "a/b", "a.b", "..", "a\"b", "a\\b", "a\nb", "a\tb", "日本語",
        "\u{E9}", "e\u{301}", String(repeating: "n", count: 65),
    ]

    @Test("the name limit is 64 characters")
    func nameLimit() {
        #expect(EffectScaffoldTemplate.nameLimit == 64)
    }

    @Test("a name of ASCII letters, digits, spaces, hyphens and underscores, up to the limit, is valid", arguments: validNames)
    func acceptsValidName(_ name: String) {
        #expect(EffectScaffoldTemplate.isValid(name: name))
    }

    @Test(
        "a name that is empty, over the limit, starts or ends with a space, starts with a hyphen or underscore, or holds any other character is invalid",
        arguments: invalidNames)
    func refusesInvalidName(_ name: String) {
        #expect(!EffectScaffoldTemplate.isValid(name: name))
    }

    @Test("manifest(named:) is the sample manifest with the given name, and nothing else changes")
    func manifestWritesName() {
        let expected = """
            {
              "formatVersion": 1,
              "name": "My Glitch",
              "parameters": [
                { "id": "strength", "label": "Strength", "type": "float", "min": 0, "max": 1, "default": 1, "step": 0.05 }
              ]
            }

            """
        #expect(EffectScaffoldTemplate.manifest(named: "My Glitch") == expected)
    }

    @Test("a manifest of every valid name decodes to the same name and one strength parameter", arguments: validNames)
    func manifestDecodesForValidName(_ name: String) throws {
        let manifest = try EffectManifestDecoding.decode(EffectScaffoldTemplate.manifest(named: name)).get()
        #expect(manifest.formatVersion == EffectManifestDecoding.supportedFormatVersion)
        #expect(manifest.name == name)
        #expect(manifest.parameters.map(\.id) == ["strength"])
    }

    @Test("effectSource declares the effect kernel")
    func effectSourceDeclaresKernel() {
        #expect(EffectScaffoldTemplate.effectSource.contains("kernel void effect("))
    }

    @Test("effectSource declares neither Uniforms nor Parameters, because the shader source assembly declares them")
    func effectSourceLeavesStructsToAssembly() {
        #expect(!EffectScaffoldTemplate.effectSource.contains("struct Uniforms"))
        #expect(!EffectScaffoldTemplate.effectSource.contains("struct Parameters"))
    }

    @Test("effectSource reads the strength parameter")
    func effectSourceReadsStrength() {
        #expect(EffectScaffoldTemplate.effectSource.contains("params.strength"))
    }

    @Test("effectSource ends with exactly one newline")
    func effectSourceEndsWithOneNewline() {
        let source = EffectScaffoldTemplate.effectSource
        #expect(source.hasSuffix("}\n"))
        #expect(!source.hasSuffix("\n\n"))
    }
}
