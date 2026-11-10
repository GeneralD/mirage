/// The types a `Parameters` field can have in the shader. Closed and small on purpose: each is
/// 4, 8 or 16 bytes with the alignment equal to its size, which is what lets the layout be plain
/// arithmetic. `float3` is absent: Metal gives it 16/16 where `packed_float3` has 12/4, and
/// mixing the two up is the classic padding drift.
public enum EffectParameterFieldType: Sendable, Hashable, CaseIterable {
    case float
    case int
    case uint
    case float2
    case float4

    public var size: Int {
        switch self {
        case .float, .int, .uint: 4
        case .float2: 8
        case .float4: 16
        }
    }

    /// Natural alignment, which equals the size for every type here.
    public var alignment: Int { size }
}

extension EffectParameterKind {
    /// The field a parameter of this kind occupies. The one table both sides read, the shader
    /// source and the packer, so a kind cannot be one type in the text and another in the bytes.
    public var fieldType: EffectParameterFieldType {
        switch self {
        case .float: .float
        case .int: .int
        case .bool, .choice: .uint
        case .vector2: .float2
        case .color: .float4
        }
    }
}

/// Where each parameter sits in the `Parameters` struct, and how big the struct is. Pure, as
/// `DispatchGrid` is, and the single source for both the struct's text and the packed bytes: the
/// UseCase that packs and the DataSource that assembles the source may not import each other, so
/// neither keeps a table of its own to drift from the other.
///
/// Fields keep manifest order, each at its natural alignment; the stride is the end rounded up to
/// the largest alignment, which is what Metal's `sizeof(Parameters)` reports.
public struct EffectParameterLayout: Sendable, Hashable {
    public struct Field: Sendable, Hashable {
        public let id: String
        public let type: EffectParameterFieldType
        /// Byte offset from the start of the struct.
        public let offset: Int

        public init(id: String, type: EffectParameterFieldType, offset: Int) {
            self.id = id
            self.type = type
            self.offset = offset
        }
    }

    public let fields: [Field]
    /// `0` for no parameters; the block that is bound is then `EffectParameterBlock.none`.
    public let stride: Int

    public init(_ specs: [EffectParameterSpec]) {
        let placed = specs.reduce(into: (fields: [Field](), end: 0, alignment: 1)) { placed, spec in
            let type = spec.kind.fieldType
            let offset = placed.end.rounded(upToMultipleOf: type.alignment)
            placed.fields.append(Field(id: spec.id, type: type, offset: offset))
            placed.end = offset + type.size
            placed.alignment = max(placed.alignment, type.alignment)
        }
        self.fields = placed.fields
        self.stride = placed.end.rounded(upToMultipleOf: placed.alignment)
    }
}

extension Int {
    fileprivate func rounded(upToMultipleOf unit: Int) -> Int {
        (self + unit - 1) / unit * unit
    }
}
