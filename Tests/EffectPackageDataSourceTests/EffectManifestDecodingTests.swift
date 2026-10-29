import Domain
import EffectPackageDataSource
import Foundation
import TestSupport
import Testing

/// The pure half of the DataSource: what the text of a `manifest.json` decodes to, or why it
/// does not. Every row is a manifest an author could write.
@Suite("EffectManifestDecoding", .timeLimit(.minutes(1)))
struct EffectManifestDecodingTests {
    private static func invalid(_ message: String) -> Result<EffectManifest, EffectPackageProblem> {
        .failure(.manifestInvalid(message: message))
    }

    private static func manifest(
        _ name: String, author: String? = nil, description: String? = nil
    ) -> Result<EffectManifest, EffectPackageProblem> {
        .success(EffectManifest(formatVersion: 1, name: name, author: author, description: description))
    }

    struct Row: Sendable, CustomTestStringConvertible {
        let name: String
        let text: String
        let expected: Result<EffectManifest, EffectPackageProblem>

        var testDescription: String { name }
    }

    static let rows: [Row] = [
        // What is read.
        Row(name: "the minimal manifest", text: #"{"formatVersion": 1, "name": "Glitch"}"#, expected: manifest("Glitch")),
        Row(
            name: "author and description",
            text: #"{"formatVersion": 1, "name": "Glitch", "author": "Ada", "description": "Tears the frame"}"#,
            expected: manifest("Glitch", author: "Ada", description: "Tears the frame")),
        Row(
            name: "a name with spaces inside is kept as written",
            text: #"{"formatVersion": 1, "name": "Chromatic  Grain"}"#, expected: manifest("Chromatic  Grain")),
        Row(
            name: "a name in any script, with escapes",
            text: #"{"formatVersion": 1, "name": "グリッチ \"2\" 🎞"}"#,
            expected: manifest("グリッチ \"2\" 🎞")),
        Row(
            name: "the name is trimmed: it is what the menu shows",
            text: #"{"formatVersion": 1, "name": " \t Glitch\n"}"#, expected: manifest("Glitch")),
        Row(
            name: "keys this build does not know are ignored, whatever they hold",
            text: #"{"formatVersion": 1, "name": "Glitch", "thumbnail": "t.png", "inputs": ["camera"], "x": {"y": null}}"#,
            expected: manifest("Glitch")),
        Row(
            name: "`parameters` is read past and not interpreted",
            text: #"{"formatVersion": 1, "name": "Glitch", "parameters": [{"id": "amount", "type": "float", "default": 0.5}]}"#,
            expected: manifest("Glitch")),
        Row(
            name: "`parameters` is ignored even when it is not an array",
            text: #"{"formatVersion": 1, "name": "Glitch", "parameters": 7}"#, expected: manifest("Glitch")),
        Row(
            name: "the order of the keys does not matter",
            text: #"{"description": "d", "name": "Glitch", "formatVersion": 1}"#, expected: manifest("Glitch", description: "d")),

        // The format version decides first.
        Row(name: "a newer format", text: #"{"formatVersion": 2, "name": "Glitch"}"#, expected: .failure(.unsupportedFormatVersion(2))),
        Row(
            name: "a newer format is reported as that even when its other keys have another shape",
            text: #"{"formatVersion": 2, "title": {"en": "Glitch"}}"#, expected: .failure(.unsupportedFormatVersion(2))),
        Row(name: "version 0", text: #"{"formatVersion": 0, "name": "Glitch"}"#, expected: .failure(.unsupportedFormatVersion(0))),
        Row(name: "a negative version", text: #"{"formatVersion": -1, "name": "Glitch"}"#, expected: .failure(.unsupportedFormatVersion(-1))),
        Row(
            name: "a version that is a number but not an integer is reported by name, not as text that is not JSON",
            text: #"{"formatVersion": 1.5, "name": "Glitch"}"#, expected: invalid("\"formatVersion\" is not an integer")),
        Row(
            name: "and so is one before the other keys are looked at",
            text: #"{"formatVersion": 1.5, "title": {"en": "Glitch"}}"#, expected: invalid("\"formatVersion\" is not an integer")),
        Row(
            name: "a whole version beyond Int is out of range",
            text: #"{"formatVersion": 99999999999999999999, "name": "Glitch"}"#, expected: invalid("\"formatVersion\" is out of range")),
        Row(
            name: "and so is a negative one",
            text: #"{"formatVersion": -99999999999999999999, "name": "Glitch"}"#, expected: invalid("\"formatVersion\" is out of range")),
        Row(
            name: "a version above 2^53 is read exactly, not rounded to the Double next to it",
            text: #"{"formatVersion": 9007199254740993, "name": "Glitch"}"#, expected: .failure(.unsupportedFormatVersion(9_007_199_254_740_993))),
        Row(
            name: "the largest Int is an unsupported version, not out of range",
            text: #"{"formatVersion": 9223372036854775807, "name": "Glitch"}"#, expected: .failure(.unsupportedFormatVersion(Int.max))),
        Row(
            name: "and so is the smallest",
            text: #"{"formatVersion": -9223372036854775808, "name": "Glitch"}"#, expected: .failure(.unsupportedFormatVersion(Int.min))),
        Row(
            name: "one past the largest Int is out of range",
            text: #"{"formatVersion": 9223372036854775808, "name": "Glitch"}"#, expected: invalid("\"formatVersion\" is out of range")),
        Row(
            name: "1.0 is the integer 1",
            text: #"{"formatVersion": 1.0, "name": "Glitch"}"#, expected: manifest("Glitch")),
        Row(
            name: "and so is 1e0",
            text: #"{"formatVersion": 1e0, "name": "Glitch"}"#, expected: manifest("Glitch")),
        Row(
            name: "a number beyond even a Double has no key to name: it stays text that is not JSON",
            text: #"{"formatVersion": 1e400, "name": "Glitch"}"#, expected: invalid("not valid JSON")),

        // What is invalid.
        Row(name: "an empty name", text: #"{"formatVersion": 1, "name": ""}"#, expected: invalid("\"name\" is empty")),
        Row(
            name: "a name of whitespace only",
            text: #"{"formatVersion": 1, "name": " \n\t "}"#, expected: invalid("\"name\" is empty")),
        Row(name: "no name", text: #"{"formatVersion": 1}"#, expected: invalid("missing required key \"name\"")),
        Row(name: "no format version", text: #"{"name": "Glitch"}"#, expected: invalid("missing required key \"formatVersion\"")),
        Row(
            name: "a name that is not text",
            text: #"{"formatVersion": 1, "name": 5}"#, expected: invalid("\"name\" has the wrong type")),
        Row(
            name: "a format version that is text",
            text: #"{"formatVersion": "1", "name": "Glitch"}"#, expected: invalid("\"formatVersion\" has the wrong type")),
        Row(
            name: "a format version that is null",
            text: #"{"formatVersion": null, "name": "Glitch"}"#, expected: invalid("\"formatVersion\" has no value")),
        Row(
            name: "a name that is null",
            text: #"{"formatVersion": 1, "name": null}"#, expected: invalid("\"name\" has no value")),
        Row(
            name: "an author that is not text",
            text: #"{"formatVersion": 1, "name": "Glitch", "author": ["Ada"]}"#, expected: invalid("\"author\" has the wrong type")),
        Row(name: "text that is not JSON", text: "name = Glitch", expected: invalid("not valid JSON")),
        Row(name: "nothing at all", text: "", expected: invalid("not valid JSON")),
        Row(name: "JSON cut short", text: #"{"formatVersion": 1, "name": "Gli"#, expected: invalid("not valid JSON")),
        Row(
            name: "a lone surrogate escape inside a value names no key either: the decoder reports it without a path",
            text: #"{"formatVersion": 1, "name": "\ud800"}"#, expected: invalid("not valid JSON")),
        Row(name: "an array in place of an object", text: "[]", expected: invalid("the manifest has the wrong type")),
        Row(name: "a bare string", text: #""Glitch""#, expected: invalid("the manifest has the wrong type")),
    ]

    @Test("a manifest decodes to its value, or to the reason it cannot", arguments: rows)
    func decodes(_ row: Row) {
        #expect(EffectManifestDecoding.decode(row.text) == row.expected)
    }

    @Test("a manifest with `parameters` decodes to exactly what the same manifest without it does")
    func parametersChangeNothing() {
        let without = EffectManifestDecoding.decode(#"{"formatVersion": 1, "name": "Glitch", "author": "Ada"}"#)
        let with = EffectManifestDecoding.decode(
            #"{"formatVersion": 1, "name": "Glitch", "author": "Ada", "parameters": [{"id": "a"}, {"id": "b", "range": [0, 1]}]}"#)

        #expect(with == without)
    }

    @Test("only format version 1 is read")
    func supportedVersion() {
        #expect(EffectManifestDecoding.supportedFormatVersion == 1)
    }
}
