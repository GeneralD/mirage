import Domain
import Foundation

/// What a manifest's `parameters` must keep once they have the shape of their JSON
/// (`EffectParameter+Codable.swift`): the table of `docs/hackathon/mvp-cd/specs/parameters.md`. Pure,
/// like `EffectManifestDecoding`, which calls it and lets the package be broken with the reason.
///
/// - **How many.** At most 32, so the block bound with one `setBytes` stays small (512 bytes at the most).
/// - **`id`.** An identifier of 1 to 64 ASCII letters, digits and underscores that does not begin with
///   a digit (it is written verbatim into the `Parameters` struct, so this is what keeps the generated
///   line one line), not a word of `MSLReservedWords`, and not an earlier parameter's `id` (compared
///   as written: the language is case-sensitive).
/// - **`label`.** Not empty once trimmed; the trimmed label is what the panel shows, as the trimmed
///   name is what the menu shows.
/// - **`float`, `int`, `vec2`.** `min < max` (per component for a `vec2`) and `default` between them,
///   inclusive. A `float`'s `step`, when it has one, is above 0 and at most `max - min`. The numbers are
///   finite already: the decoder refuses the others.
/// - **`color`.** Every component of `default` in `0...1`.
/// - **`choice`.** 1 to 32 options, none empty as written and none twice.
///
/// The first rule broken is the one reported, so one wrong manifest gets one reason: the count first,
/// then each parameter in turn, its rules in the order of the list above. Each reason names the key by the same path
/// the decoder's errors use (`parameters[2].default`, and `parameters[2].default[1]` for one component).
enum EffectParameterValidation {
    static let maximumCount = 32
    static let maximumOptionCount = 32
    static let maximumIdentifierLength = 64

    /// `specs` with each label trimmed, or the problem that breaks the package.
    static func validate(_ specs: [EffectParameterSpec]) -> Result<[EffectParameterSpec], EffectPackageProblem> {
        guard specs.count <= maximumCount else {
            return .failure(.manifestInvalid(message: invalid("parameters", "has more than \(maximumCount) entries")))
        }
        guard let message = specs.indices.lazy.compactMap({ violation(ofSpecAt: $0, in: specs) }).first else {
            return .success(specs.map(trimmed))
        }
        return .failure(.manifestInvalid(message: message))
    }

    private static func trimmed(_ spec: EffectParameterSpec) -> EffectParameterSpec {
        EffectParameterSpec(id: spec.id, label: spec.label.trimmingCharacters(in: .whitespacesAndNewlines), kind: spec.kind)
    }

    private static func invalid(_ path: String, _ reason: String) -> String {
        "\"\(path)\" \(reason)"
    }

    // MARK: One parameter

    private static func violation(ofSpecAt index: Int, in specs: [EffectParameterSpec]) -> String? {
        let spec = specs[index]
        let path = "parameters[\(index)]"
        return idViolation(of: spec.id, at: index, before: specs[..<index])
            ?? labelViolation(of: spec.label, at: path)
            ?? kindViolation(of: spec.kind, at: path)
    }

    private static func idViolation(of id: String, at index: Int, before earlier: ArraySlice<EffectParameterSpec>) -> String? {
        let path = "parameters[\(index)].id"
        guard isIdentifier(id) else {
            return invalid(
                path, "is not an identifier (a letter or underscore, then up to \(maximumIdentifierLength - 1) letters, digits or underscores)")
        }
        guard !MSLReservedWords.contains(id) else { return invalid(path, "is a reserved word of the shader language") }
        return earlier.firstIndex { $0.id == id }.map { invalid(path, "repeats \"parameters[\($0)].id\"") }
    }

    /// Spelled out in ASCII scalars: `isLetter` and a regular expression's `\w` take other scripts, and `$`
    /// can match before a trailing newline, and none of them may reach the struct's text.
    private static func isIdentifier(_ id: String) -> Bool {
        let scalars = id.unicodeScalars
        guard let first = scalars.first, (1...maximumIdentifierLength).contains(scalars.count) else { return false }
        return isLetterOrUnderscore(first) && scalars.dropFirst().allSatisfy { isLetterOrUnderscore($0) || ("0"..."9").contains($0) }
    }

    private static func isLetterOrUnderscore(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || scalar == "_"
    }

    private static func labelViolation(of label: String, at path: String) -> String? {
        label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? invalid("\(path).label", "is empty") : nil
    }

    // MARK: By kind

    private static func kindViolation(of kind: EffectParameterKind, at path: String) -> String? {
        switch kind {
        case .float(let min, let max, let step, let defaultValue):
            return scalarRangeViolation(min: min, max: max, defaultValue: defaultValue, at: path)
                ?? step.flatMap { stepViolation($0, span: max - min, at: path) }
        case .int(let min, let max, let defaultValue):
            return scalarRangeViolation(min: min, max: max, defaultValue: defaultValue, at: path)
        case .bool:
            return nil
        case .color(let defaultValue):
            return (0..<4).lazy.compactMap { component in
                (0...1).contains(defaultValue[component]) ? nil : invalid("\(path).default[\(component)]", "is outside 0 to 1")
            }.first
        case .vector2(let min, let max, let defaultValue):
            return (0..<2).lazy.compactMap { component in
                scalarRangeViolation(
                    min: min[component], max: max[component], defaultValue: defaultValue[component], at: path, component: component)
            }.first
        case .choice(let options, _):
            return optionsViolation(options, at: path)
        }
    }

    /// `min < max` first, so a default is never judged against a range that is not one. `component`
    /// is the index of a `vec2`'s component and is left out of the key for a scalar.
    private static func scalarRangeViolation<Value: Comparable>(
        min: Value, max: Value, defaultValue: Value, at path: String, component: Int? = nil
    ) -> String? {
        let suffix = component.map { "[\($0)]" } ?? ""
        guard min < max else { return invalid("\(path).max\(suffix)", "is not greater than \"min\(suffix)\"") }
        guard min <= defaultValue, defaultValue <= max else {
            return invalid("\(path).default\(suffix)", "is outside \"min\(suffix)\" to \"max\(suffix)\"")
        }
        return nil
    }

    private static func stepViolation(_ step: Float, span: Float, at path: String) -> String? {
        step > 0 && step <= span ? nil : invalid("\(path).step", "is not above 0 and at most \"max\" - \"min\"")
    }

    private static func optionsViolation(_ options: [String], at path: String) -> String? {
        guard (1...maximumOptionCount).contains(options.count) else {
            return invalid("\(path).options", "does not have 1 to \(maximumOptionCount) entries")
        }
        return options.indices.lazy.compactMap { index in
            let option = "\(path).options[\(index)]"
            if options[index].isEmpty { return invalid(option, "is empty") }
            return options[..<index].firstIndex(of: options[index]).map { invalid(option, "repeats \"\(path).options[\($0)]\"") }
        }.first
    }
}
