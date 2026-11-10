/// One parameter as an author writes it in `manifest.json` (`docs/hackathon/mvp-cd/specs/parameters.md`):
/// a flat object, whatever the kind, in which `type` says which of the other keys are read.
///
/// | `type`   | keys read                                                                 |
/// |----------|---------------------------------------------------------------------------|
/// | `float`  | `min`, `max`, `default` (numbers), `step` (optional number)               |
/// | `int`    | `min`, `max`, `default` (whole numbers within 32 bits)                    |
/// | `bool`   | `default` (`true` / `false`)                                              |
/// | `color`  | `default` (four numbers, red to alpha)                                    |
/// | `vec2`   | `min`, `max`, `default` (two numbers each)                                |
/// | `choice` | `options` (texts), `default` (the text of one of them)                    |
///
/// `id`, `label` and `type` are always read; a key the kind does not read is ignored, like any key
/// this build does not know. This is the shape only. What a value may be (ranges, ids, how many) is
/// the manifest reader's to rule on, so a spec that decodes here has not yet been allowed. What the
/// shape cannot hold is refused at once, with `Rejection`: a `type` that is not one of the six
/// (`typeNames`), a `choice` whose `default` is none of its `options`, and the numbers below.
///
/// Every number is read so that a failure names its key: a number the decoder reports as text that is
/// not JSON, with no path (1e39 as a `Float`, 1.5 or 3e9 as an `Int32`), is read again as a `Double`, and
/// being there it is `Rejection.outOfRange` or `.notAnInteger` at its key. NaN and the infinities
/// (which only a decoder set to read them from text can produce) are `.outOfRange` as well, so no
/// spec holds a value that is not finite. A number beyond even a `Double` stays "not valid JSON".
extension EffectParameterSpec: Codable {
    /// The `type` values, in the order the manifest documents them.
    public static var typeNames: [String] { TypeName.allCases.map(\.rawValue) }

    /// Why the object has the shape of a parameter and still cannot be one. Carried as the
    /// `underlyingError` of a `DecodingError.dataCorrupted` whose coding path is the key at fault, so
    /// whoever reports it words it from the case and not from the decoder's text.
    public enum Rejection: Error, Sendable, Hashable {
        /// `type` is not one of `typeNames`.
        case unknownType
        /// A number is not finite, or does not fit the width its field has.
        case outOfRange
        /// An `int` field holds a fraction or a number beyond 32 bits.
        case notAnInteger
        /// A list of numbers does not have the length its field has.
        case wrongComponentCount(expected: Int)
        /// A `choice`'s `default` is none of its `options`.
        case notAnOption
    }

    fileprivate enum TypeName: String, CaseIterable {
        case float, int, bool, color, vec2, choice
    }

    private enum Key: String, CodingKey {
        case id, label, type, min, max, step, options
        case defaultValue = "default"
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: Key.self)
        let id = try fields.decode(String.self, forKey: .id)
        let label = try fields.decode(String.self, forKey: .label)
        let typeName = try fields.decode(String.self, forKey: .type)
        guard let type = TypeName(rawValue: typeName) else { throw Self.reject(.unknownType, at: fields.codingPath + [Key.type]) }
        self.init(id: id, label: label, kind: try Self.kind(of: type, in: fields))
    }

    public func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: Key.self)
        try fields.encode(id, forKey: .id)
        try fields.encode(label, forKey: .label)
        try fields.encode(kind.typeName.rawValue, forKey: .type)
        switch kind {
        case .float(let min, let max, let step, let defaultValue):
            try fields.encode(min, forKey: .min)
            try fields.encode(max, forKey: .max)
            try fields.encodeIfPresent(step, forKey: .step)
            try fields.encode(defaultValue, forKey: .defaultValue)
        case .int(let min, let max, let defaultValue):
            try fields.encode(min, forKey: .min)
            try fields.encode(max, forKey: .max)
            try fields.encode(defaultValue, forKey: .defaultValue)
        case .bool(let defaultValue):
            try fields.encode(defaultValue, forKey: .defaultValue)
        case .color(let defaultValue):
            try fields.encode(defaultValue, forKey: .defaultValue)
        case .vector2(let min, let max, let defaultValue):
            try fields.encode(min, forKey: .min)
            try fields.encode(max, forKey: .max)
            try fields.encode(defaultValue, forKey: .defaultValue)
        case .choice(let options, let defaultIndex):
            guard options.indices.contains(defaultIndex) else {
                throw EncodingError.invalidValue(
                    defaultIndex,
                    EncodingError.Context(
                        codingPath: fields.codingPath + [Key.defaultValue], debugDescription: "the default index is not an index of the options"))
            }
            try fields.encode(options, forKey: .options)
            try fields.encode(options[defaultIndex], forKey: .defaultValue)
        }
    }

    private static func kind(of type: TypeName, in fields: KeyedDecodingContainer<Key>) throws -> EffectParameterKind {
        switch type {
        case .float:
            return .float(
                min: try fields.decode(FiniteFloat.self, forKey: .min).value,
                max: try fields.decode(FiniteFloat.self, forKey: .max).value,
                step: try fields.decodeIfPresent(FiniteFloat.self, forKey: .step)?.value,
                defaultValue: try fields.decode(FiniteFloat.self, forKey: .defaultValue).value)
        case .int:
            return .int(
                min: try fields.decode(WholeNumber.self, forKey: .min).value,
                max: try fields.decode(WholeNumber.self, forKey: .max).value,
                defaultValue: try fields.decode(WholeNumber.self, forKey: .defaultValue).value)
        case .bool:
            return .bool(defaultValue: try fields.decode(Bool.self, forKey: .defaultValue))
        case .color:
            return .color(defaultValue: try vector(.defaultValue, in: fields))
        case .vec2:
            return .vector2(
                min: try vector(.min, in: fields), max: try vector(.max, in: fields), defaultValue: try vector(.defaultValue, in: fields))
        case .choice:
            let options = try fields.decode([String].self, forKey: .options)
            let defaultValue = try fields.decode(String.self, forKey: .defaultValue)
            guard let defaultIndex = options.firstIndex(of: defaultValue) else {
                throw reject(.notAnOption, at: fields.codingPath + [Key.defaultValue])
            }
            return .choice(options: options, defaultIndex: defaultIndex)
        }
    }

    private static func vector<Vector: SIMD>(_ key: Key, in fields: KeyedDecodingContainer<Key>) throws -> Vector where Vector.Scalar == Float {
        let components = try fields.decode([FiniteFloat].self, forKey: key)
        guard components.count == Vector.scalarCount else {
            throw reject(.wrongComponentCount(expected: Vector.scalarCount), at: fields.codingPath + [key])
        }
        return Vector(components.map(\.value))
    }

    fileprivate static func reject(_ rejection: Rejection, at path: [any CodingKey]) -> DecodingError {
        .dataCorrupted(DecodingError.Context(codingPath: path, debugDescription: "\(rejection)", underlyingError: rejection))
    }
}

extension EffectParameterKind {
    fileprivate var typeName: EffectParameterSpec.TypeName {
        switch self {
        case .float: .float
        case .int: .int
        case .bool: .bool
        case .color: .color
        case .vector2: .vec2
        case .choice: .choice
        }
    }
}

/// A `Float` read straight from the text, so that it is the nearest `Float` to what the author wrote
/// (through a `Double` it could land on the neighbour), and only a finite one.
private struct FiniteFloat: Decodable {
    let value: Float

    init(from decoder: any Decoder) throws {
        let number = try decoder.singleValueContainer()
        guard let value = try? number.decode(Float.self), value.isFinite else {
            // Not a `Float`: read as a `Double`, which throws the type or key error of a value that is no
            // number, and otherwise means the number is there and out of range.
            _ = try number.decode(Double.self)
            throw EffectParameterSpec.reject(.outOfRange, at: decoder.codingPath)
        }
        self.value = value
    }
}

/// An `Int32` read like `FiniteFloat`: a whole number such as `2.0` is the integer it names.
private struct WholeNumber: Decodable {
    let value: Int32

    init(from decoder: any Decoder) throws {
        let number = try decoder.singleValueContainer()
        guard let value = try? number.decode(Int32.self) else {
            _ = try number.decode(Double.self)
            throw EffectParameterSpec.reject(.notAnInteger, at: decoder.codingPath)
        }
        self.value = value
    }
}
