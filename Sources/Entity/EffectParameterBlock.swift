/// The bytes of one effect's `Parameters` struct, laid out by `EffectParameterLayout`, ready to be
/// bound with a single `setBytes`.
///
/// Never shorter than `minimumLength`: `setBytes` of length 0 is invalid, and an effect without
/// parameters still binds a block, so the Metal gateway has one code path and no branch.
public struct EffectParameterBlock: Sendable, Hashable {
    public static let minimumLength = 16

    public let bytes: [UInt8]

    /// Bytes shorter than `minimumLength` are padded with zeros; longer ones are kept as they are.
    public init(bytes: [UInt8]) {
        self.bytes = bytes + [UInt8](repeating: 0, count: max(0, Self.minimumLength - bytes.count))
    }

    /// The block of an effect that declares no parameters.
    public static let none = EffectParameterBlock(bytes: [])
}
