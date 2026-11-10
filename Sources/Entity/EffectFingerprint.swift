/// What an effect compiled to, not what it is called: a stable hash of the kernel source, the
/// compile options and the parameter layout. A pass is stamped with it when it is admitted, so a
/// pass that ends after the user picked another effect still counts for the effect that ran it, and
/// a stored verdict about an effect stops applying the moment its source, options or layout
/// change (an edit re-enables).
///
/// The value is persisted and compared across launches, so it cannot come from `Hasher`, which is
/// seeded per process.
public struct EffectFingerprint: Sendable, Hashable, Codable {
    /// 16 lowercase hexadecimal digits.
    public let value: String

    public init(value: String) {
        self.value = value
    }
}

extension EffectFingerprint {
    /// Labels, defaults, ranges and the display name are not hashed: none of them reaches the
    /// compiled shader, so changing one must not look like an edit of the kernel. The parameters
    /// enter through their layout (id, field type, offset, stride), which is all the generated
    /// `Parameters` struct is made of.
    public static func of(_ source: EffectSource) -> EffectFingerprint {
        let layout = EffectParameterLayout(source.parameters)
        let framed: [[UInt8]] = [
            Frame.text(source.source),
            Frame.text(source.options.entryPoint),
            [source.options.precise ? 1 : 0],
            Frame.number(layout.fields.count),
        ]
        let fields: [[UInt8]] = layout.fields.map { Frame.text($0.id) + [$0.type.stableTag] + Frame.number($0.offset) }
        let digits = String(FNV1a64.hash((framed + fields + [Frame.number(layout.stride)]).joined()), radix: 16)
        return EffectFingerprint(value: String(repeating: "0", count: 16 - digits.count) + digits)
    }
}

/// The 64-bit FNV-1a hash, by hand: the algorithm is fixed by its published constants, so the
/// value is the same on every machine and in every build, which no standard-library hasher promises.
enum FNV1a64 {
    private static let offsetBasis: UInt64 = 0xCBF2_9CE4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01B3

    static func hash(_ bytes: some Sequence<UInt8>) -> UInt64 {
        bytes.reduce(offsetBasis) { ($0 ^ UInt64($1)) &* prime }
    }
}

/// How the hashed fields become one byte stream. Every text is preceded by its length, so the
/// boundary between two fields is part of the bytes: a delimiter would be ambiguous, as a shader
/// source may contain any character, and `ab` + `c` would hash like `a` + `bc` without either.
private enum Frame {
    static func text(_ text: String) -> [UInt8] {
        let bytes = Array(text.utf8)
        return number(bytes.count) + bytes
    }

    /// Eight bytes, little-endian.
    static func number(_ value: Int) -> [UInt8] {
        let unsigned = UInt64(truncatingIfNeeded: value)
        return (0..<8).map { UInt8(truncatingIfNeeded: unsigned >> ($0 * 8)) }
    }
}

extension EffectParameterFieldType {
    /// Written out, not derived from the declaration order, so adding or moving a case never
    /// changes a fingerprint that was already stored. A new type takes the next number.
    fileprivate var stableTag: UInt8 {
        switch self {
        case .float: 1
        case .int: 2
        case .uint: 3
        case .float2: 4
        case .float4: 5
        }
    }
}
