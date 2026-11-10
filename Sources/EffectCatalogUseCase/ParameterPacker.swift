import Domain

// The packing of parameter values into one effect's `Parameters` block (`docs/hackathon/mvp-cd/specs/parameters.md`,
// pure policy). Pure and total: a value that cannot be used packs as its kind's default, and a field that does not
// fit the block is skipped, so no input traps.

/// Lays parameter values out as the bytes of the `Parameters` struct, at the offsets the layout names.
struct ParameterPacker {
    private init() {}

    /// The block for `values`. The i-th spec is paired with the i-th field of `layout`, by position, so two specs that
    /// share an id each pack that id's value in their own field. A value is `values[spec.id]` brought into its kind by
    /// `normalized`, or the kind's default when the id is not given. A spec with no field is skipped, and so is a value
    /// that would run past the end of the block. The block is at least `EffectParameterBlock.minimumLength` bytes long.
    static func pack(
        values: [String: EffectParameterValue], specs: [EffectParameterSpec], layout: EffectParameterLayout
    ) -> EffectParameterBlock {
        let packed = zip(specs, layout.fields).reduce(
            into: [UInt8](repeating: 0, count: max(layout.stride, EffectParameterBlock.minimumLength))
        ) { bytes, pair in
            let (spec, field) = pair
            let encoding = encoded(values[spec.id].map(spec.kind.normalized) ?? spec.kind.defaultValue)
            guard field.offset >= 0, field.offset + encoding.count <= bytes.count else { return }
            bytes.replaceSubrange(field.offset..<(field.offset + encoding.count), with: encoding)
        }
        return EffectParameterBlock(bytes: packed)
    }

    /// The little-endian bytes of `value` as its field reads them: a float or an int is one 4-byte word, a bool and a
    /// choice a `uint` (1 or 0, and the index), a vector2 two floats and a color four.
    private static func encoded(_ value: EffectParameterValue) -> [UInt8] {
        switch value {
        case .float(let number):
            return littleEndian(number.bitPattern)
        case .int(let number):
            return littleEndian(UInt32(bitPattern: number))
        case .bool(let flag):
            return littleEndian(flag ? 1 : 0)
        case .choice(let index):
            return littleEndian(UInt32(clamping: index))
        case .vector2(let vector):
            return [vector.x, vector.y].flatMap { littleEndian($0.bitPattern) }
        case .color(let color):
            return [color.x, color.y, color.z, color.w].flatMap { littleEndian($0.bitPattern) }
        }
    }

    /// The four bytes of `word`, least significant first.
    private static func littleEndian(_ word: UInt32) -> [UInt8] {
        (0..<4).map { UInt8(truncatingIfNeeded: word >> (8 * $0)) }
    }
}
