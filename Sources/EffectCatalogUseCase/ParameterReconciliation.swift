import Domain

// The values an effect starts from once its manifest may have changed since they were stored
// (`docs/hackathon/mvp-cd/specs/parameters.md`, pure policy). Pure and total: the result holds exactly the
// declared ids, and each value is of its kind's own case within the kind's range.

/// Stored parameter values reconciled with the parameters a manifest declares now.
struct ParameterReconciliation {
    private init() {}

    /// One entry per declared id and no other, so an id the manifest dropped is gone. A stored value of the kind's
    /// case is brought into the kind by `normalized`, so a narrowed range clamps it. A stored value of another case
    /// (the type changed) and a missing one both take the kind's default. When two specs share an id, the first one
    /// decides, and nothing traps.
    static func reconcile(stored: [String: EffectParameterValue], specs: [EffectParameterSpec]) -> [String: EffectParameterValue] {
        Dictionary(
            specs.map { spec in
                (spec.id, stored[spec.id].map { spec.kind.normalized($0) } ?? spec.kind.defaultValue)
            },
            uniquingKeysWith: { first, _ in first })
    }
}
