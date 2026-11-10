/// The failures that can disable an effect, in the form that is stored. `EffectFailure` carries
/// a raw code for the log (`unknown(code:)`) and the causes that are the runtime's own; a record
/// keeps only the cause a user can be told about. Closed, and the raw value is the persisted
/// form, so a case is never renamed.
public enum EffectFailureKind: String, Sendable, Hashable, Codable, CaseIterable {
    case timeout
    case pageFault
    case accessRevoked
    case outOfMemory
    case unknown
}

/// Why an effect was switched off: one failure kind, or passes that kept running over budget.
public enum EffectDisableReason: Sendable, Hashable, Codable {
    case failure(EffectFailureKind)
    case overBudget
}

/// The memory of a disabled effect, kept across launches so a crash loop cannot repeat. It is keyed
/// by the effect and the fingerprint it had: once the package is edited the fingerprint differs
/// and the record no longer applies, and writing a new record for an effect replaces its old one.
public struct DisabledEffectRecord: Sendable, Hashable, Codable {
    public let id: EffectID
    public let fingerprint: EffectFingerprint
    public let reason: EffectDisableReason
    /// Whether the cool-down may end in an automatic trial. `false` for the causes where a retry
    /// would hang or fault the user's call again, which need an edit or an explicit re-enable.
    public let retriesAutomatically: Bool

    public init(id: EffectID, fingerprint: EffectFingerprint, reason: EffectDisableReason, retriesAutomatically: Bool) {
        self.id = id
        self.fingerprint = fingerprint
        self.reason = reason
        self.retriesAutomatically = retriesAutomatically
    }
}
