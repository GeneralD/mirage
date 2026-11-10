import Domain

/// The effect health counts for: the effect the runtime was last prepared with, its stamp, and the policy counting its passes.
struct ArmedHealth {
    let id: EffectID
    let fingerprint: EffectFingerprint
    var policy: EffectHealthPolicy
}

/// An effect health has switched off in this run: the record the menu takes its reason from.
struct DisabledEntry {
    var record: DisabledEffectRecord
}

/// `EffectCatalogSession`, health half: counts the pass outcomes the runtime reports for the effect it holds, and switches a
/// package effect off when its policy says so. The pure counting is `EffectHealthPolicy`; this file only decides which
/// outcome counts and what the menu is told.
extension EffectCatalogSession {
    /// Counts one run's pass outcomes one at a time, in the order the runtime reported them, until the stream ends or the
    /// caller's task is cancelled.
    func follow(_ stream: AsyncStream<EffectPassOutcome>, in run: Int) async {
        for await outcome in stream { await receive(outcome, in: run) }
    }

    /// Counts `outcome` if it is a pass of the effect the runtime holds in this run. A verdict to switch off a package effect
    /// is published; a bundled effect is never switched off here (#133 decides what happens to it).
    func receive(_ outcome: EffectPassOutcome, in run: Int) async {
        guard epoch == run, var health = armed, health.fingerprint == outcome.fingerprint else { return }
        let verdict = health.policy.record(outcome.result)
        armed = health
        guard case .disable(let reason, let retryAfter) = verdict, health.id.origin == .package else { return }
        disabled[health.id] = DisabledEntry(
            record: DisabledEffectRecord(
                id: health.id, fingerprint: health.fingerprint, reason: reason, retriesAutomatically: retryAfter != nil))
        publish()
    }
}
