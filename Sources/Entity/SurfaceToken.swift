/// A process-local reference to a pooled surface: the slot index plus the
/// generation the slot was in when the token was issued. A token whose
/// generation is stale resolves to nothing, so a double release or a use after
/// release is detected rather than silently touching the slot's next tenant.
/// Tokens are never serialized; a surface crosses the process boundary only as
/// a Mach port.
public struct SurfaceToken: Sendable, Hashable {
    public let index: Int
    public let generation: UInt64

    public init(index: Int, generation: UInt64) {
        self.index = index
        self.generation = generation
    }
}
