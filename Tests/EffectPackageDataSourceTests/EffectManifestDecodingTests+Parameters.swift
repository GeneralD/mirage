import Domain
import Foundation
import Testing

@testable import EffectPackageDataSource

/// `parameters`: the knobs a manifest declares, and the rules of
/// `docs/hackathon/mvp-cd/specs/parameters.md` that make a package with a wrong one broken. Every row is a
/// manifest an author could write; a rejection is pinned with the whole message, since the key it
/// names is what the author acts on.
extension EffectManifestDecodingTests {
    // MARK: Building manifests

    /// One parameter object of `type`, with `members` after the three keys every kind has.
    private static func parameter(_ type: String, _ members: String, id: String = "p", label: String = "P") -> String {
        #"{"id": "\#(id)", "label": "\#(label)", "type": "\#(type)", \#(members)}"#
    }

    private static func float(id: String = "p", min: String = "0", max: String = "1", value: String = "0.5", step: String? = nil) -> String {
        let stepMember = step.map { ", \"step\": \($0)" } ?? ""
        return parameter("float", "\"min\": \(min), \"max\": \(max), \"default\": \(value)\(stepMember)", id: id)
    }

    /// A `choice` of `count` options, `o0` to `o<count - 1>`, whose default is the last.
    private static func choice(optionCount count: Int) -> String {
        let options = (0..<count).map { "\"o\($0)\"" }.joined(separator: ", ")
        return parameter("choice", "\"options\": [\(options)], \"default\": \"o\(count - 1)\"")
    }

    private static func manifest(_ parameters: [String]) -> String {
        #"{"formatVersion": 1, "name": "Glitch", "parameters": [\#(parameters.joined(separator: ", "))]}"#
    }

    private static func accepted(_ parameters: [EffectParameterSpec]) -> Result<EffectManifest, EffectPackageProblem> {
        .success(EffectManifest(formatVersion: 1, name: "Glitch", parameters: parameters))
    }

    private static func rejected(_ message: String) -> Result<EffectManifest, EffectPackageProblem> {
        .failure(.manifestInvalid(message: message))
    }

    private static func spec(_ id: String, _ kind: EffectParameterKind, label: String = "P") -> EffectParameterSpec {
        EffectParameterSpec(id: id, label: label, kind: kind)
    }

    /// The manifest of the spec's example, verbatim.
    static let exampleText = """
        {
          "formatVersion": 1,
          "name": "Ripple",
          "parameters": [
            { "id": "strength", "label": "Strength", "type": "float", "min": 0, "max": 1, "default": 0.5, "step": 0.01 },
            { "id": "rings", "label": "Rings", "type": "int", "min": 1, "max": 16, "default": 4 },
            { "id": "inverted", "label": "Inverted", "type": "bool", "default": false },
            { "id": "tint", "label": "Tint", "type": "color", "default": [1, 0.8, 0.6, 1] },
            { "id": "center", "label": "Center", "type": "vec2", "min": [0, 0], "max": [1, 1], "default": [0.5, 0.5] },
            { "id": "mode", "label": "Mode", "type": "choice", "options": ["Soft", "Hard"], "default": "Soft" }
          ]
        }
        """

    /// The six parameters of the example, in its order.
    static let exampleSpecs: [EffectParameterSpec] = [
        EffectParameterSpec(id: "strength", label: "Strength", kind: .float(min: 0, max: 1, step: 0.01, defaultValue: 0.5)),
        EffectParameterSpec(id: "rings", label: "Rings", kind: .int(min: 1, max: 16, defaultValue: 4)),
        EffectParameterSpec(id: "inverted", label: "Inverted", kind: .bool(defaultValue: false)),
        EffectParameterSpec(id: "tint", label: "Tint", kind: .color(defaultValue: SIMD4<Float>(1, 0.8, 0.6, 1))),
        EffectParameterSpec(
            id: "center", label: "Center",
            kind: .vector2(min: SIMD2<Float>(0, 0), max: SIMD2<Float>(1, 1), defaultValue: SIMD2<Float>(0.5, 0.5))),
        EffectParameterSpec(id: "mode", label: "Mode", kind: .choice(options: ["Soft", "Hard"], defaultIndex: 0)),
    ]

    // MARK: What is read

    static let readRows: [Row] = [
        Row(
            name: "a manifest without `parameters` has none", text: #"{"formatVersion": 1, "name": "Glitch"}"#,
            expected: accepted([])),
        Row(
            name: "an empty `parameters` is none",
            text: #"{"formatVersion": 1, "name": "Glitch", "parameters": []}"#, expected: accepted([])),
        Row(
            name: "a `parameters` that is null is none, as a null thumbnail is no thumbnail",
            text: #"{"formatVersion": 1, "name": "Glitch", "parameters": null}"#, expected: accepted([])),
        Row(
            name: "the spec's example manifest reads as its six parameters, in order",
            text: exampleText,
            expected: .success(EffectManifest(formatVersion: 1, name: "Ripple", parameters: exampleSpecs))),
        Row(
            name: "a float without a step has none",
            text: manifest([float()]), expected: accepted([spec("p", .float(min: 0, max: 1, step: nil, defaultValue: 0.5))])),
        Row(
            name: "a float's step may be as wide as the whole range",
            text: manifest([float(min: "-2", max: "3", value: "0", step: "5")]),
            expected: accepted([spec("p", .float(min: -2, max: 3, step: 5, defaultValue: 0))])),
        Row(
            name: "a float's default may be its minimum or its maximum",
            text: manifest([float(id: "lo", value: "0"), float(id: "hi", value: "1")]),
            expected: accepted([
                spec("lo", .float(min: 0, max: 1, step: nil, defaultValue: 0)), spec("hi", .float(min: 0, max: 1, step: nil, defaultValue: 1)),
            ])),
        Row(
            name: "a float is the Float nearest to what is written, not the neighbour a Double would round to",
            text: manifest([float(min: "0", max: "2", value: "1.00000005960464477539062501")]),
            expected: accepted([spec("p", .float(min: 0, max: 2, step: nil, defaultValue: Float(1).nextUp))])),
        Row(
            name: "an int may be written as a whole number with a fraction part of zero",
            text: manifest([parameter("int", #""min": 1.0, "max": 1e1, "default": 4"#)]),
            expected: accepted([spec("p", .int(min: 1, max: 10, defaultValue: 4))])),
        Row(
            name: "an int may span the whole of 32 bits",
            text: manifest([parameter("int", #""min": -2147483648, "max": 2147483647, "default": 0"#)]),
            expected: accepted([spec("p", .int(min: Int32.min, max: Int32.max, defaultValue: 0))])),
        Row(
            name: "a color's components may be 0 and 1",
            text: manifest([parameter("color", #""default": [0, 1, 0, 1]"#)]),
            expected: accepted([spec("p", .color(defaultValue: SIMD4<Float>(0, 1, 0, 1)))])),
        Row(
            name: "a vec2's components are judged one by one: a default on a boundary in each",
            text: manifest([parameter("vec2", #""min": [-1, 0], "max": [1, 4], "default": [1, 0]"#)]),
            expected: accepted([
                spec("p", .vector2(min: SIMD2<Float>(-1, 0), max: SIMD2<Float>(1, 4), defaultValue: SIMD2<Float>(1, 0)))
            ])),
        Row(
            name: "a choice's default is the text of its option, and its index is what is kept",
            text: manifest([parameter("choice", #""options": ["Soft", "Hard", "Medium"], "default": "Medium""#)]),
            expected: accepted([spec("p", .choice(options: ["Soft", "Hard", "Medium"], defaultIndex: 2))])),
        Row(
            name: "a choice's options differing in case or by a space are different options",
            text: manifest([parameter("choice", #""options": ["soft", "Soft", "Soft "], "default": "Soft ""#)]),
            expected: accepted([spec("p", .choice(options: ["soft", "Soft", "Soft "], defaultIndex: 2))])),
        Row(
            name: "a bool is read from its default alone",
            text: manifest([parameter("bool", #""default": true"#)]), expected: accepted([spec("p", .bool(defaultValue: true))])),
        Row(
            name: "the label is trimmed: it is what the panel shows",
            text: manifest([parameter("bool", #""default": true"#, label: " \\t Inverted\\n")]),
            expected: accepted([spec("p", .bool(defaultValue: true), label: "Inverted")])),
        Row(
            name: "a label in any script, with escapes",
            text: manifest([parameter("bool", #""default": true"#, label: #"強さ \"2\" 🎞"#)]),
            expected: accepted([spec("p", .bool(defaultValue: true), label: #"強さ "2" 🎞"#)])),
        Row(
            name: "keys a kind does not read are ignored, a `step` on an int or a vec2 among them",
            text: manifest([
                parameter("int", #""min": 0, "max": 9, "default": 1, "step": 3, "options": 5, "unit": "px""#),
                parameter("vec2", #""min": [0, 0], "max": [1, 1], "default": [0, 0], "step": 0.1"#, id: "q"),
            ]),
            expected: accepted([
                spec("p", .int(min: 0, max: 9, defaultValue: 1)),
                spec("q", .vector2(min: SIMD2<Float>(0, 0), max: SIMD2<Float>(1, 1), defaultValue: SIMD2<Float>(0, 0))),
            ])),
        Row(
            name: "a step that is null is no step",
            text: manifest([parameter("float", #""min": 0, "max": 1, "default": 0, "step": null"#)]),
            expected: accepted([spec("p", .float(min: 0, max: 1, step: nil, defaultValue: 0))])),
        Row(
            name: "ids that differ only in case are two ids: the language tells them apart",
            text: manifest([float(id: "Amount"), float(id: "amount")]),
            expected: accepted([
                spec("Amount", .float(min: 0, max: 1, step: nil, defaultValue: 0.5)),
                spec("amount", .float(min: 0, max: 1, step: nil, defaultValue: 0.5)),
            ])),
        Row(
            name: "an id may be a single underscore, begin with one and hold digits",
            text: manifest([float(id: "_"), float(id: "_a1_B2")]),
            expected: accepted([
                spec("_", .float(min: 0, max: 1, step: nil, defaultValue: 0.5)), spec("_a1_B2", .float(min: 0, max: 1, step: nil, defaultValue: 0.5)),
            ])),
        Row(
            name: "an id of 64 characters is the longest",
            text: manifest([float(id: String(repeating: "a", count: 64))]),
            expected: accepted([spec(String(repeating: "a", count: 64), .float(min: 0, max: 1, step: nil, defaultValue: 0.5))])),
        Row(
            name: "a word that only differs in case from a reserved one is an id",
            text: manifest([float(id: "Kernel"), float(id: "Float")]),
            expected: accepted([
                spec("Kernel", .float(min: 0, max: 1, step: nil, defaultValue: 0.5)),
                spec("Float", .float(min: 0, max: 1, step: nil, defaultValue: 0.5)),
            ])),
        Row(
            name: "a name Metal builds in that the struct text does not use is an id",
            text: manifest([float(id: "uint2"), float(id: "atomic_uint"), float(id: "metal")]),
            expected: accepted([
                spec("uint2", .float(min: 0, max: 1, step: nil, defaultValue: 0.5)),
                spec("atomic_uint", .float(min: 0, max: 1, step: nil, defaultValue: 0.5)),
                spec("metal", .float(min: 0, max: 1, step: nil, defaultValue: 0.5)),
            ])),
        Row(
            name: "32 parameters are the most",
            text: manifest((0..<32).map { float(id: "p\($0)") }),
            expected: accepted((0..<32).map { spec("p\($0)", .float(min: 0, max: 1, step: nil, defaultValue: 0.5)) })),
        Row(
            name: "32 options are the most",
            text: manifest([choice(optionCount: 32)]),
            expected: accepted([spec("p", .choice(options: (0..<32).map { "o\($0)" }, defaultIndex: 31))])),
        Row(
            name: "the format version is judged before `parameters`, whatever they hold",
            text: #"{"formatVersion": 2, "name": "Glitch", "parameters": 7}"#, expected: .failure(.unsupportedFormatVersion(2))),
        Row(
            name: "the name is judged before the rules of the parameters",
            text: #"{"formatVersion": 1, "name": " ", "parameters": [\#(parameter("bool", #""default": true"#, id: "1"))]}"#,
            expected: rejected("\"name\" is empty")),
        Row(
            name: "the shape of the parameters is read with the rest of the manifest, so a wrong shape is named before an empty name",
            text: #"{"formatVersion": 1, "name": " ", "parameters": [{"id": "1"}]}"#,
            expected: rejected("missing required key \"parameters[0].label\"")),
    ]

    @Test("`parameters` reads as the knobs it declares, or as none", arguments: readRows)
    func readsParameters(_ row: Row) {
        #expect(EffectManifestDecoding.decode(row.text) == row.expected)
    }

    // MARK: What is wrong with the shape

    static let shapeRows: [Row] = [
        Row(
            name: "`parameters` that is not a list",
            text: #"{"formatVersion": 1, "name": "Glitch", "parameters": 7}"#, expected: rejected("\"parameters\" has the wrong type")),
        Row(
            name: "`parameters` that is an object",
            text: #"{"formatVersion": 1, "name": "Glitch", "parameters": {"id": "a"}}"#, expected: rejected("\"parameters\" has the wrong type")),
        Row(
            name: "a parameter that is not an object names its place in the list",
            text: manifest([float(), "5"]), expected: rejected("\"parameters[1]\" has the wrong type")),
        Row(
            name: "a parameter without an id names the missing key at its index",
            text: manifest([float(), #"{"label": "P", "type": "bool", "default": true}"#]),
            expected: rejected("missing required key \"parameters[1].id\"")),
        Row(
            name: "a parameter without a label",
            text: manifest([#"{"id": "a", "type": "bool", "default": true}"#]), expected: rejected("missing required key \"parameters[0].label\"")),
        Row(
            name: "a parameter without a type",
            text: manifest([#"{"id": "a", "label": "A", "default": true}"#]), expected: rejected("missing required key \"parameters[0].type\"")),
        Row(
            name: "a float without a minimum",
            text: manifest([parameter("float", #""max": 1, "default": 0"#)]), expected: rejected("missing required key \"parameters[0].min\"")),
        Row(
            name: "a float without a maximum",
            text: manifest([parameter("float", #""min": 0, "default": 0"#)]), expected: rejected("missing required key \"parameters[0].max\"")),
        Row(
            name: "a float without a default: every kind has one",
            text: manifest([parameter("float", #""min": 0, "max": 1"#)]), expected: rejected("missing required key \"parameters[0].default\"")),
        Row(
            name: "a bool without a default",
            text: manifest([#"{"id": "a", "label": "A", "type": "bool"}"#]),
            expected: rejected("missing required key \"parameters[0].default\"")),
        Row(
            name: "a choice without options",
            text: manifest([parameter("choice", #""default": "a""#)]), expected: rejected("missing required key \"parameters[0].options\"")),
        Row(
            name: "an id that is not text",
            text: manifest([#"{"id": 5, "label": "A", "type": "bool", "default": true}"#]),
            expected: rejected("\"parameters[0].id\" has the wrong type")),
        Row(
            name: "a type that is not text",
            text: manifest([#"{"id": "a", "label": "A", "type": 3, "default": true}"#]),
            expected: rejected("\"parameters[0].type\" has the wrong type")),
        Row(
            name: "a default that is null has no value",
            text: manifest([parameter("float", #""min": 0, "max": 1, "default": null"#)]),
            expected: rejected("\"parameters[0].default\" has no value")),
        Row(
            name: "a float minimum that is text",
            text: manifest([float(min: "\"0\"")]), expected: rejected("\"parameters[0].min\" has the wrong type")),
        Row(
            name: "a bool default that is a number",
            text: manifest([parameter("bool", #""default": 1"#)]), expected: rejected("\"parameters[0].default\" has the wrong type")),
        Row(
            name: "a choice's default that is a number",
            text: manifest([parameter("choice", #""options": ["a"], "default": 0"#)]),
            expected: rejected("\"parameters[0].default\" has the wrong type")),
        Row(
            name: "options that are not a list",
            text: manifest([parameter("choice", #""options": "a", "default": "a""#)]),
            expected: rejected("\"parameters[0].options\" has the wrong type")),
        Row(
            name: "an option that is not text names its index",
            text: manifest([parameter("choice", #""options": ["a", 2], "default": "a""#)]),
            expected: rejected("\"parameters[0].options[1]\" has the wrong type")),
        Row(
            name: "a color default that is not a list",
            text: manifest([parameter("color", #""default": 1"#)]), expected: rejected("\"parameters[0].default\" has the wrong type")),
        Row(
            name: "a color component that is text names its index",
            text: manifest([parameter("color", #""default": [1, 1, "a", 1]"#)]),
            expected: rejected("\"parameters[0].default[2]\" has the wrong type")),
        Row(
            name: "a color of three components",
            text: manifest([parameter("color", #""default": [1, 1, 1]"#)]),
            expected: rejected("\"parameters[0].default\" is not a list of 4 numbers")),
        Row(
            name: "a color of five components",
            text: manifest([parameter("color", #""default": [1, 1, 1, 1, 1]"#)]),
            expected: rejected("\"parameters[0].default\" is not a list of 4 numbers")),
        Row(
            name: "a vec2 minimum of one component",
            text: manifest([parameter("vec2", #""min": [0], "max": [1, 1], "default": [0, 0]"#)]),
            expected: rejected("\"parameters[0].min\" is not a list of 2 numbers")),
        Row(
            name: "a vec2 default of three components",
            text: manifest([parameter("vec2", #""min": [0, 0], "max": [1, 1], "default": [0, 0, 0]"#)]),
            expected: rejected("\"parameters[0].default\" is not a list of 2 numbers")),
        Row(
            name: "the first parameter that has the wrong shape is the one named, even after a rule is broken before it",
            text: manifest([float(min: "1", max: "0"), #"{"id": "b"}"#]), expected: rejected("missing required key \"parameters[1].label\"")),
        Row(
            name: "a wrong shape beyond the 32nd parameter is named before the count is judged",
            text: manifest((0..<32).map { float(id: "p\($0)") } + [#"{"id": "b"}"#]),
            expected: rejected("missing required key \"parameters[32].label\"")),
    ]

    @Test("a parameter of the wrong shape breaks the package and names the key", arguments: shapeRows)
    func rejectsWrongShape(_ row: Row) {
        #expect(EffectManifestDecoding.decode(row.text) == row.expected)
    }

    // MARK: Types, numbers and the options

    static let typeAndNumberRows: [Row] = [
        Row(
            name: "an unknown type rejects the package, naming the six it knows",
            text: manifest([parameter("vector2", #""min": [0, 0], "max": [1, 1], "default": [0, 0]"#)]),
            expected: rejected("\"parameters[0].type\" is not one of float, int, bool, color, vec2, choice")),
        Row(
            name: "a type is matched exactly: not by case",
            text: manifest([parameter("Float", #""min": 0, "max": 1, "default": 0"#)]),
            expected: rejected("\"parameters[0].type\" is not one of float, int, bool, color, vec2, choice")),
        Row(
            name: "an empty type",
            text: manifest([parameter("", #""default": true"#)]),
            expected: rejected("\"parameters[0].type\" is not one of float, int, bool, color, vec2, choice")),
        Row(
            name: "an unknown type is named at its own index",
            text: manifest([float(), float(id: "q"), parameter("texture", #""default": 0"#)]),
            expected: rejected("\"parameters[2].type\" is not one of float, int, bool, color, vec2, choice")),
        Row(
            name: "a float beyond the largest Float is out of range: infinity is refused",
            text: manifest([float(max: "1e39")]), expected: rejected("\"parameters[0].max\" is out of range")),
        Row(
            name: "and so is one beyond the smallest",
            text: manifest([float(min: "-1e39")]), expected: rejected("\"parameters[0].min\" is out of range")),
        Row(
            name: "a step beyond it",
            text: manifest([float(step: "1e39")]), expected: rejected("\"parameters[0].step\" is out of range")),
        Row(
            name: "a number too small for a Float to hold is out of range as well",
            text: manifest([float(min: "1e-60", max: "1")]), expected: rejected("\"parameters[0].min\" is out of range")),
        Row(
            name: "a component of a vec2 beyond a Float names the component",
            text: manifest([parameter("vec2", #""min": [0, 0], "max": [1, 1e39], "default": [0, 0]"#)]),
            expected: rejected("\"parameters[0].max[1]\" is out of range")),
        Row(
            name: "a component of a color beyond a Float names the component",
            text: manifest([parameter("color", #""default": [0, 0, -1e39, 0]"#)]),
            expected: rejected("\"parameters[0].default[2]\" is out of range")),
        Row(
            name: "a number beyond even a Double has no key to name: it stays text that is not JSON",
            text: manifest([float(max: "1e400")]), expected: rejected("not valid JSON")),
        Row(
            name: "an int with a fraction is not an integer",
            text: manifest([parameter("int", #""min": 0, "max": 9, "default": 1.5"#)]),
            expected: rejected("\"parameters[0].default\" is not a 32-bit integer")),
        Row(
            name: "an int beyond 32 bits is not a 32-bit integer",
            text: manifest([parameter("int", #""min": 0, "max": 2147483648, "default": 1"#)]),
            expected: rejected("\"parameters[0].max\" is not a 32-bit integer")),
        Row(
            name: "and so is one below it",
            text: manifest([parameter("int", #""min": -2147483649, "max": 9, "default": 1"#)]),
            expected: rejected("\"parameters[0].min\" is not a 32-bit integer")),
        Row(
            name: "an int that is text",
            text: manifest([parameter("int", #""min": "0", "max": 9, "default": 1"#)]),
            expected: rejected("\"parameters[0].min\" has the wrong type")),
        Row(
            name: "a choice whose default is none of its options",
            text: manifest([parameter("choice", #""options": ["Soft", "Hard"], "default": "soft""#)]),
            expected: rejected("\"parameters[0].default\" is not one of \"options\"")),
        Row(
            name: "a choice with no options has no default to be",
            text: manifest([parameter("choice", #""options": [], "default": "a""#)]),
            expected: rejected("\"parameters[0].default\" is not one of \"options\"")),
    ]

    @Test("a type or a number the shape cannot hold breaks the package and names the key", arguments: typeAndNumberRows)
    func rejectsTypesAndNumbers(_ row: Row) {
        #expect(EffectManifestDecoding.decode(row.text) == row.expected)
    }

    // MARK: The rules

    static let ruleRows: [Row] = [
        // How many.
        Row(
            name: "33 parameters are one too many",
            text: manifest((0..<33).map { float(id: "p\($0)") }), expected: rejected("\"parameters\" has more than 32 entries")),
        Row(
            name: "the count is judged before the rules of any one parameter",
            text: manifest([float(id: "1")] + (1..<33).map { float(id: "p\($0)") }), expected: rejected("\"parameters\" has more than 32 entries")),

        // The id.
        Row(
            name: "an empty id", text: manifest([float(id: "")]),
            expected: rejected(
                "\"parameters[0].id\" is not an identifier (a letter or underscore, then up to 63 letters, digits or underscores)")),
        Row(
            name: "an id that begins with a digit", text: manifest([float(id: "1a")]),
            expected: rejected(
                "\"parameters[0].id\" is not an identifier (a letter or underscore, then up to 63 letters, digits or underscores)")),
        Row(
            name: "an id with a hyphen", text: manifest([float(id: "a-b")]),
            expected: rejected(
                "\"parameters[0].id\" is not an identifier (a letter or underscore, then up to 63 letters, digits or underscores)")),
        Row(
            name: "an id with a space", text: manifest([float(id: "a b")]),
            expected: rejected(
                "\"parameters[0].id\" is not an identifier (a letter or underscore, then up to 63 letters, digits or underscores)")),
        Row(
            name: "an id with a letter that is not ASCII", text: manifest([float(id: "caf\\u00e9")]),
            expected: rejected(
                "\"parameters[0].id\" is not an identifier (a letter or underscore, then up to 63 letters, digits or underscores)")),
        Row(
            name: "an id in another script", text: manifest([float(id: "強さ")]),
            expected: rejected(
                "\"parameters[0].id\" is not an identifier (a letter or underscore, then up to 63 letters, digits or underscores)")),
        Row(
            name: "an id that ends in a newline: it would end the struct's one line",
            text: manifest([float(id: "a\\n")]),
            expected: rejected(
                "\"parameters[0].id\" is not an identifier (a letter or underscore, then up to 63 letters, digits or underscores)")),
        Row(
            name: "an id that carries a statement",
            text: manifest([float(id: "a; int b")]),
            expected: rejected(
                "\"parameters[0].id\" is not an identifier (a letter or underscore, then up to 63 letters, digits or underscores)")),
        Row(
            name: "an id of 65 characters is one too long", text: manifest([float(id: String(repeating: "a", count: 65))]),
            expected: rejected(
                "\"parameters[0].id\" is not an identifier (a letter or underscore, then up to 63 letters, digits or underscores)")),
        Row(
            name: "an id that is a reserved word of the shader language", text: manifest([float(id: "kernel")]),
            expected: rejected("\"parameters[0].id\" is a reserved word of the shader language")),
        Row(
            name: "an id that is the name of a type the struct uses", text: manifest([float(id: "float2")]),
            expected: rejected("\"parameters[0].id\" is a reserved word of the shader language")),
        Row(
            name: "an id that is a keyword of C++", text: manifest([float(id: "class")]),
            expected: rejected("\"parameters[0].id\" is a reserved word of the shader language")),
        Row(
            name: "an id that is the as_type operator of Metal", text: manifest([float(id: "as_type")]),
            expected: rejected("\"parameters[0].id\" is a reserved word of the shader language")),
        Row(
            name: "an id that repeats an earlier one names it",
            text: manifest([float(id: "a"), float(id: "b"), float(id: "a")]),
            expected: rejected("\"parameters[2].id\" repeats \"parameters[0].id\"")),
        Row(
            name: "an id is judged for being reserved before it is compared with the others",
            text: manifest([float(id: "kernel"), float(id: "kernel")]),
            expected: rejected("\"parameters[0].id\" is a reserved word of the shader language")),

        // The label.
        Row(
            name: "an empty label", text: manifest([parameter("bool", #""default": true"#, label: "")]),
            expected: rejected("\"parameters[0].label\" is empty")),
        Row(
            name: "a label of whitespace only", text: manifest([parameter("bool", #""default": true"#, label: " \\t\\n\\u00a0\\u3000")]),
            expected: rejected("\"parameters[0].label\" is empty")),
        Row(
            name: "the id of a parameter is judged before its label",
            text: manifest([parameter("bool", #""default": true"#, id: "1", label: "")]),
            expected: rejected(
                "\"parameters[0].id\" is not an identifier (a letter or underscore, then up to 63 letters, digits or underscores)")),

        // float.
        Row(
            name: "a float whose minimum equals its maximum",
            text: manifest([float(min: "1", max: "1", value: "1")]), expected: rejected("\"parameters[0].max\" is not greater than \"min\"")),
        Row(
            name: "a float whose minimum is above its maximum",
            text: manifest([float(min: "2", max: "1", value: "1")]), expected: rejected("\"parameters[0].max\" is not greater than \"min\"")),
        Row(
            name: "a float default below the minimum",
            text: manifest([float(min: "0", max: "1", value: "-0.001")]),
            expected: rejected("\"parameters[0].default\" is outside \"min\" to \"max\"")),
        Row(
            name: "a float default above the maximum",
            text: manifest([float(min: "0", max: "1", value: "1.001")]),
            expected: rejected("\"parameters[0].default\" is outside \"min\" to \"max\"")),
        Row(
            name: "a float step of zero",
            text: manifest([float(step: "0")]), expected: rejected("\"parameters[0].step\" is not above 0 and at most \"max\" - \"min\"")),
        Row(
            name: "a float step below zero",
            text: manifest([float(step: "-0.1")]), expected: rejected("\"parameters[0].step\" is not above 0 and at most \"max\" - \"min\"")),
        Row(
            name: "a float step wider than the range",
            text: manifest([float(min: "0", max: "1", step: "1.5")]),
            expected: rejected("\"parameters[0].step\" is not above 0 and at most \"max\" - \"min\"")),
        Row(
            name: "the range is judged before the default, and the default before the step",
            text: manifest([float(min: "2", max: "1", value: "9", step: "0")]),
            expected: rejected("\"parameters[0].max\" is not greater than \"min\"")),

        // int.
        Row(
            name: "an int whose minimum equals its maximum",
            text: manifest([parameter("int", #""min": 3, "max": 3, "default": 3"#)]),
            expected: rejected("\"parameters[0].max\" is not greater than \"min\"")),
        Row(
            name: "an int default above the maximum",
            text: manifest([parameter("int", #""min": 1, "max": 16, "default": 17"#)]),
            expected: rejected("\"parameters[0].default\" is outside \"min\" to \"max\"")),
        Row(
            name: "an int default below the minimum",
            text: manifest([parameter("int", #""min": 1, "max": 16, "default": 0"#)]),
            expected: rejected("\"parameters[0].default\" is outside \"min\" to \"max\"")),

        // color.
        Row(
            name: "a color component below 0 names the component",
            text: manifest([parameter("color", #""default": [1, -0.1, 0, 1]"#)]),
            expected: rejected("\"parameters[0].default[1]\" is outside 0 to 1")),
        Row(
            name: "a color component above 1 names the component",
            text: manifest([parameter("color", #""default": [1, 0, 0, 1.5]"#)]),
            expected: rejected("\"parameters[0].default[3]\" is outside 0 to 1")),

        // vec2.
        Row(
            name: "a vec2 whose first component has no room",
            text: manifest([parameter("vec2", #""min": [1, 0], "max": [1, 1], "default": [1, 0]"#)]),
            expected: rejected("\"parameters[0].max[0]\" is not greater than \"min[0]\"")),
        Row(
            name: "a vec2 whose second component is the wrong way round",
            text: manifest([parameter("vec2", #""min": [0, 5], "max": [1, 1], "default": [0, 5]"#)]),
            expected: rejected("\"parameters[0].max[1]\" is not greater than \"min[1]\"")),
        Row(
            name: "a vec2 default outside in its second component only",
            text: manifest([parameter("vec2", #""min": [0, 0], "max": [1, 1], "default": [0.5, 2]"#)]),
            expected: rejected("\"parameters[0].default[1]\" is outside \"min[1]\" to \"max[1]\"")),

        // choice.
        Row(
            name: "33 options are one too many",
            text: manifest([choice(optionCount: 33)]),
            expected: rejected("\"parameters[0].options\" does not have 1 to 32 entries")),
        Row(
            name: "an empty option names its index",
            text: manifest([parameter("choice", #""options": ["a", "", "c"], "default": "a""#)]),
            expected: rejected("\"parameters[0].options[1]\" is empty")),
        Row(
            name: "an option that repeats an earlier one names it",
            text: manifest([parameter("choice", #""options": ["a", "b", "a"], "default": "b""#)]),
            expected: rejected("\"parameters[0].options[2]\" repeats \"parameters[0].options[0]\"")),

        // Which parameter.
        Row(
            name: "the first parameter that breaks a rule is the one named",
            text: manifest([float(), float(id: "b", min: "1", max: "0"), float(id: "c", min: "1", max: "0")]),
            expected: rejected("\"parameters[1].max\" is not greater than \"min\"")),
    ]

    @Test("a parameter that breaks a rule breaks the package and names the key", arguments: ruleRows)
    func rejectsRuleBreakers(_ row: Row) {
        #expect(EffectManifestDecoding.decode(row.text) == row.expected)
    }

    // MARK: Reserved words

    @Test("every word of the reserved list is refused as an id", arguments: MSLReservedWords.all.sorted())
    func reservedWordsAreRefused(_ word: String) {
        let decoded = EffectManifestDecoding.decode(Self.manifest([Self.float(id: word)]))

        #expect(decoded == Self.rejected("\"parameters[0].id\" is a reserved word of the shader language"))
    }

    @Test(
        "a word of the reserved list with a letter changed in case is an id: the language is case-sensitive", arguments: MSLReservedWords.all.sorted()
    )
    func caseVariantsOfReservedWordsAreIds(_ word: String) {
        let variant = word.prefix(1).uppercased() + word.dropFirst()

        let decoded = EffectManifestDecoding.decode(Self.manifest([Self.float(id: variant)]))

        #expect(decoded == Self.accepted([Self.spec(variant, .float(min: 0, max: 1, step: nil, defaultValue: 0.5))]))
    }

    @Test("the reserved list holds no word twice")
    func reservedListHasNoDuplicates() {
        let words = MSLReservedWords.cxxKeywords + MSLReservedWords.metalKeywords + MSLReservedWords.typeNames
        #expect(Set(words).count == words.count)
        #expect(MSLReservedWords.all.count == words.count)
    }

    // MARK: Whole packages

    @Test("the type names an author may write are the six, in the order the spec lists them")
    func typeNames() {
        #expect(EffectParameterSpec.typeNames == ["float", "int", "bool", "color", "vec2", "choice"])
    }

    @Test("a manifest with parameters keeps everything else it says, as written")
    func parametersLeaveTheRestAlone() {
        let text = """
            {"formatVersion": 1, "name": " Glitch ", "author": "Ada", "description": "d", "thumbnail": "t.png",
             "parameters": [{"id": "a", "label": "A", "type": "bool", "default": false}]}
            """
        #expect(
            EffectManifestDecoding.decode(text)
                == .success(
                    EffectManifest(
                        formatVersion: 1, name: "Glitch", author: "Ada", description: "d", thumbnail: "t.png",
                        parameters: [Self.spec("a", .bool(defaultValue: false), label: "A")])))
    }

    // MARK: Writing

    @Test("a manifest without parameters is written without the key, as it was before they existed")
    func noParametersNoKey() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let json = String(decoding: try encoder.encode(EffectManifest(formatVersion: 1, name: "Glitch")), as: UTF8.self)

        #expect(json == #"{"formatVersion":1,"name":"Glitch"}"#)
    }

    @Test("each kind is written as the manifest's JSON reads it", arguments: Array(zip(exampleSpecs, writtenExample)))
    func writtenForm(_ pair: (EffectParameterSpec, String)) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let json = String(decoding: try encoder.encode(pair.0), as: UTF8.self)

        #expect(json == pair.1)
    }

    static let writtenExample = [
        #"{"default":0.5,"id":"strength","label":"Strength","max":1,"min":0,"step":0.01,"type":"float"}"#,
        #"{"default":4,"id":"rings","label":"Rings","max":16,"min":1,"type":"int"}"#,
        #"{"default":false,"id":"inverted","label":"Inverted","type":"bool"}"#,
        #"{"default":[1,0.8,0.6,1],"id":"tint","label":"Tint","type":"color"}"#,
        #"{"default":[0.5,0.5],"id":"center","label":"Center","max":[1,1],"min":[0,0],"type":"vec2"}"#,
        #"{"default":"Soft","id":"mode","label":"Mode","options":["Soft","Hard"],"type":"choice"}"#,
    ]

    @Test("a choice whose default index is none of its options cannot be written")
    func choiceWithBadDefaultIndexIsNotWritten() {
        let broken = Self.spec("p", .choice(options: ["a", "b"], defaultIndex: 2))

        #expect(throws: EncodingError.self) { try JSONEncoder().encode(broken) }
    }

    // MARK: NaN and infinity

    /// A decoder that reads `"nan"` and `"inf"` from text, the only way a decoder gives a Float that is not finite.
    private static func nonConformingDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return decoder
    }

    @Test("NaN and the infinities are refused, in a float, a step and the components of a vector", arguments: ["nan", "inf", "-inf"])
    func nonFiniteNumbersAreRefused(_ word: String) {
        let objects = [
            (#"{"id": "a", "label": "A", "type": "float", "min": "\#(word)", "max": 1, "default": 0}"#, "min"),
            (#"{"id": "a", "label": "A", "type": "float", "min": 0, "max": "\#(word)", "default": 0}"#, "max"),
            (#"{"id": "a", "label": "A", "type": "float", "min": 0, "max": 1, "default": "\#(word)"}"#, "default"),
            (#"{"id": "a", "label": "A", "type": "float", "min": 0, "max": 1, "default": 0, "step": "\#(word)"}"#, "step"),
            (#"{"id": "a", "label": "A", "type": "color", "default": [0, "\#(word)", 0, 0]}"#, "default"),
        ]
        for (object, key) in objects {
            do {
                _ = try Self.nonConformingDecoder().decode(EffectParameterSpec.self, from: Data(object.utf8))
                Issue.record("\(object) decoded")
            } catch DecodingError.dataCorrupted(let context) {
                #expect(context.underlyingError as? EffectParameterSpec.Rejection == .outOfRange)
                #expect(context.codingPath.first?.stringValue == key)
            } catch {
                Issue.record("\(object) threw \(error)")
            }
        }
    }
}
