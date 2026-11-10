import Domain

/// The block of an effect's `Parameters` struct at every parameter's declared default, packed where
/// `EffectParameterLayout` places each field. A still image has nobody to turn a knob, so it is
/// always rendered with these values.
public enum DefaultParameterBlock {
    /// The bytes that bind `specs` at their defaults. `EffectParameterBlock.none` when there are none.
    public static func make(for specs: [EffectParameterSpec]) -> EffectParameterBlock {
        let layout = EffectParameterLayout(specs)
        let bytes = zip(layout.fields, specs).reduce(into: [UInt8](repeating: 0, count: layout.stride)) { block, pair in
            let (field, spec) = pair
            block.replaceSubrange(field.offset..<field.offset + field.type.size, with: defaultBytes(of: spec.kind))
        }
        return EffectParameterBlock(bytes: bytes)
    }

    /// The little-endian bytes of one default, in the field type `EffectParameterKind.fieldType` names.
    private static func defaultBytes(of kind: EffectParameterKind) -> [UInt8] {
        switch kind {
        case .float(_, _, _, let defaultValue): word(defaultValue.bitPattern)
        case .int(_, _, let defaultValue): word(UInt32(bitPattern: defaultValue))
        case .bool(let defaultValue): word(defaultValue ? 1 : 0)
        case .color(let defaultValue): words([defaultValue.x, defaultValue.y, defaultValue.z, defaultValue.w])
        case .vector2(_, _, let defaultValue): words([defaultValue.x, defaultValue.y])
        // `truncatingIfNeeded` keeps a bad index from trapping; a valid index gives the same bytes.
        case .choice(_, let defaultIndex): word(UInt32(truncatingIfNeeded: defaultIndex))
        }
    }

    /// Four bytes, least significant first, so the layout does not depend on the host's endianness.
    private static func word(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
    }

    private static func words(_ floats: [Float]) -> [UInt8] {
        floats.flatMap { word($0.bitPattern) }
    }
}
