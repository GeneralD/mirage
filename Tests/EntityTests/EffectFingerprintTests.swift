import Foundation
import TestSupport
import Testing

@testable import Entity

private let kernel = "kernel void effect() {}"

private func fingerprint(
    _ source: String = kernel, entryPoint: String = "effect", precise: Bool = true, parameters: [EffectParameterSpec] = [], name: String = "Effect"
) -> EffectFingerprint {
    EffectFingerprint.of(
        EffectSource(name: name, source: source, options: ShaderCompileOptions(entryPoint: entryPoint, precise: precise), parameters: parameters))
}

@Suite("FNV1a64")
struct FNV1a64Tests {
    /// The published test vectors of the algorithm (the FNV authors' reference list).
    @Test(
        "the hash of a known input is the published FNV-1a 64-bit value",
        arguments: [
            ("", UInt64(0xCBF2_9CE4_8422_2325)),
            ("a", 0xAF63_DC4C_8601_EC8C),
            ("foobar", 0x8594_4171_F739_67E8),
        ])
    func publishedVectors(input: String, expected: UInt64) {
        #expect(FNV1a64.hash(Array(input.utf8)) == expected)
    }
}

@Suite("EffectFingerprint")
struct EffectFingerprintTests {
    // MARK: golden values

    /// Computed by a second, independent implementation of the same framing (outside Swift), so a
    /// change that moves them also invalidates every stored `DisabledEffectRecord`.
    @Test("the fingerprint of a fixed effect is a fixed value: nothing in it depends on the process")
    func goldenValues() {
        #expect(fingerprint().value == "321518f1bfcf7e49")
        #expect(fingerprint(precise: false).value == "e33dd4f952f747d6")
        #expect(fingerprint(parameters: rippleSpecs).value == "234dac8114a65cee")
        #expect(fingerprint("日本語🙂", parameters: [EffectParameterSpec(id: "a", label: "A", kind: Kinds.float)]).value == "150c75419d2fe3b6")
    }

    @Test("a hash that starts with zeros keeps them, so the value is always 16 digits wide")
    func leadingZerosAreKept() {
        let oneZero = fingerprint("kernel 13").value
        let threeZeros = fingerprint("kernel 1257").value
        #expect(oneZero == "0b370af466ea21d3")
        #expect(threeZeros == "000ca362b7a978e8")
        #expect(oneZero.count == 16 && threeZeros.count == 16)
    }

    @Test("a fingerprint is 16 lowercase hexadecimal digits, zeros kept", arguments: Seeds.range(0..<32))
    func shape(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let value = fingerprint(
            String(
                decoding: (0..<Int.random(in: 0...64, using: &generator)).map { _ in UInt8.random(in: 32...126, using: &generator) }, as: UTF8.self),
            parameters: randomSpecs(&generator)
        ).value
        #expect(value.count == 16)
        #expect(value.allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test("asking twice gives the same value")
    func repeatable() {
        #expect(fingerprint(parameters: rippleSpecs) == fingerprint(parameters: rippleSpecs))
    }

    // MARK: what is not part of it

    @Test("the display name does not change the fingerprint")
    func nameIsNotHashed() {
        #expect(fingerprint(name: "Ripple") == fingerprint(name: "Ripple, renamed"))
    }

    @Test("labels, defaults, ranges and steps do not change the fingerprint, only the parameters' layout does", arguments: Seeds.range(0..<32))
    func panelOnlyFieldsAreNotHashed(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let original = randomSpecs(&generator)
        let edited = original.map { EffectParameterSpec(id: $0.id, label: "Another " + $0.label, kind: otherKind(sharingFieldTypeWith: $0.kind)) }
        #expect(fingerprint(parameters: edited) == fingerprint(parameters: original))
    }

    @Test("a bool and a choice are the same field, so swapping them does not recompile")
    func boolAndChoiceShareAField() {
        let asBool = [EffectParameterSpec(id: "mode", label: "Mode", kind: Kinds.bool)]
        let asChoice = [EffectParameterSpec(id: "mode", label: "Mode", kind: Kinds.choice)]
        #expect(fingerprint(parameters: asBool) == fingerprint(parameters: asChoice))
    }

    // MARK: what is part of it

    @Test("another source is another fingerprint, even by one character")
    func sourceIsHashed() {
        #expect(fingerprint(kernel) != fingerprint(kernel + " "))
        #expect(fingerprint("kernel void effect() { }") != fingerprint("kernel void effect() {}"))
        #expect(fingerprint("") != fingerprint(" "))
    }

    @Test("another entry point or another precision is another fingerprint")
    func optionsAreHashed() {
        #expect(fingerprint(entryPoint: "effect") != fingerprint(entryPoint: "main"))
        #expect(fingerprint(precise: true) != fingerprint(precise: false))
    }

    @Test("another parameter id, field type, order or count is another fingerprint")
    func layoutIsHashed() {
        func one(_ id: String, _ kind: EffectParameterKind) -> [EffectParameterSpec] { [EffectParameterSpec(id: id, label: id, kind: kind)] }
        let base = fingerprint(parameters: one("a", Kinds.float))
        #expect(base != fingerprint(), "a parameter is added")
        #expect(base != fingerprint(parameters: one("b", Kinds.float)), "the id is the field name in the shader")
        #expect(base != fingerprint(parameters: one("a", Kinds.int)), "float and int are two types")
        #expect(base != fingerprint(parameters: one("a", Kinds.vector2)))
        #expect(base != fingerprint(parameters: one("a", Kinds.color)))
        #expect(base != fingerprint(parameters: one("a", Kinds.bool)), "float and uint are two types")

        let ab = [EffectParameterSpec(id: "a", label: "A", kind: Kinds.float), EffectParameterSpec(id: "b", label: "B", kind: Kinds.int)]
        #expect(fingerprint(parameters: ab) != fingerprint(parameters: ab.reversed()), "the order is the struct's order")
        #expect(fingerprint(parameters: ab) != fingerprint(parameters: Array(ab.prefix(1))))
    }

    @Test("every pair of the five field types has its own fingerprint")
    func everyFieldTypeIsDistinct() {
        let kinds: [EffectParameterKind] = [Kinds.float, Kinds.int, Kinds.bool, Kinds.vector2, Kinds.color]
        let values = kinds.map { fingerprint(parameters: [EffectParameterSpec(id: "a", label: "A", kind: $0)]).value }
        #expect(Set(values).count == kinds.count)
    }

    @Test("two parameter lists share a fingerprint exactly when they share a layout", arguments: Seeds.range(0..<64))
    func fingerprintFollowsTheLayout(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let first = randomSpecs(&generator)
        let second =
            Bool.random(using: &generator)
            ? first.map { EffectParameterSpec(id: $0.id, label: $0.label, kind: otherKind(sharingFieldTypeWith: $0.kind)) }
            : randomSpecs(&generator)
        #expect(
            (fingerprint(parameters: first) == fingerprint(parameters: second)) == (EffectParameterLayout(first) == EffectParameterLayout(second)))
    }

    // MARK: concatenation

    @Test("moving a character across a field boundary changes the fingerprint: `ab` + `c` is not `a` + `bc`")
    func fieldBoundariesAreHashed() {
        #expect(fingerprint("ab", entryPoint: "c") != fingerprint("a", entryPoint: "bc"))
        #expect(fingerprint("", entryPoint: "ab") != fingerprint("a", entryPoint: "b"))
        #expect(fingerprint("ab", entryPoint: "") != fingerprint("", entryPoint: "ab"))
    }

    @Test("a separator character inside a field cannot fake a boundary")
    func contentCannotImitateASeparator() {
        for separator in ["\u{0}", "\n", ",", ":", "|", " "] {
            #expect(
                fingerprint("a" + separator + "b", entryPoint: "c") != fingerprint("a", entryPoint: "b" + separator + "c"),
                "separator \(separator.debugDescription)")
        }
    }

    @Test("moving a character between two parameter ids changes the fingerprint: `ab`, `c` is not `a`, `bc`")
    func idBoundariesAreHashed() {
        func ids(_ first: String, _ second: String) -> [EffectParameterSpec] {
            [EffectParameterSpec(id: first, label: first, kind: Kinds.float), EffectParameterSpec(id: second, label: second, kind: Kinds.float)]
        }
        #expect(fingerprint(parameters: ids("ab", "c")) != fingerprint(parameters: ids("a", "bc")))
    }

    @Test("a parameter id cannot be read as the end of the source")
    func sourceAndIdsAreSeparated() {
        let one = [EffectParameterSpec(id: "b", label: "B", kind: Kinds.float)]
        #expect(fingerprint("a", parameters: one) != fingerprint("ab"))
        #expect(fingerprint("a", parameters: one) != fingerprint("a", entryPoint: "effectb"))
    }

    // MARK: persistence

    @Test("a fingerprint survives encode and decode", arguments: Seeds.range(0..<16))
    func codableRoundTrip(seed: UInt64) throws {
        var generator = SeededGenerator(seed: seed)
        let value = fingerprint(parameters: randomSpecs(&generator))
        #expect(try JSONDecoder().decode(EffectFingerprint.self, from: JSONEncoder().encode(value)) == value)
    }

    @Test("the JSON form is pinned: what the disabled-effect store of a later issue will persist")
    func jsonForm() throws {
        let data = try JSONEncoder().encode(EffectFingerprint(value: "321518f1bfcf7e49"))
        #expect(String(decoding: data, as: UTF8.self) == #"{"value":"321518f1bfcf7e49"}"#)
    }
}

@Suite("EffectSource parameters")
struct EffectSourceParametersTests {
    @Test("a source built the old way, without parameters, has none")
    func parametersDefaultToEmpty() {
        #expect(EffectSource(name: "Glitch", source: kernel).parameters.isEmpty)
        #expect(EffectSource(name: "Glitch", source: kernel, options: ShaderCompileOptions(precise: false)).parameters.isEmpty)
        #expect(EffectSource(name: "Glitch", source: kernel) == EffectSource(name: "Glitch", source: kernel, parameters: []))
    }

    @Test("a source keeps the parameters it was given, in order")
    func parametersAreKept() {
        #expect(EffectSource(name: "Ripple", source: kernel, parameters: rippleSpecs).parameters == rippleSpecs)
    }

    @Test("a source with parameters is not the source without them")
    func parametersAreIdentity() {
        #expect(EffectSource(name: "Ripple", source: kernel) != EffectSource(name: "Ripple", source: kernel, parameters: rippleSpecs))
    }
}
