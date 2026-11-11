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

    /// Counts `outcome` if it is a pass of the effect the runtime holds in this run. A pass that succeeds lowers
    /// `isGPUUnavailable`, whichever effect ran it. A verdict to switch off a package effect is remembered in the settings,
    /// logged, and answered by preparing the bundled effect in its place (`holdBundled`), which publishes the state that
    /// shows it. A verdict to switch off the bundled effect records nothing and falls back to nothing: there is no effect
    /// left to move frames, so it raises `isGPUUnavailable`.
    func receive(_ outcome: EffectPassOutcome, in run: Int) async {
        guard epoch == run, var health = armed, health.fingerprint == outcome.fingerprint else { return }
        if case .success = outcome.result, isGPUUnavailable {
            isGPUUnavailable = false
            publish()
        }
        let verdict = health.policy.record(outcome.result)
        armed = health
        guard case .disable(let reason, let retryAfter) = verdict else { return }
        guard health.id.origin == .package else {
            isGPUUnavailable = true
            publish()
            return
        }
        disabled[health.id] = DisabledEntry(
            record: DisabledEffectRecord(
                id: health.id, fingerprint: health.fingerprint, reason: reason, retriesAutomatically: retryAfter != nil))
        // The record is written before the fallback, so that a crash after the switch-off cannot run the effect again.
        await settings.setDisabledEffects(disabled.values.map(\.record))
        guard epoch == run else { return }
        errorLog.record(.effect, switchOffMessage(of: health.id, reason: reason))
        await holdBundled(instead: health.id, in: run)
    }

    /// The bundled effect that is ready in the listing: what the menu falls back to.
    var readyBundled: EffectCatalogEntry? {
        entries.first { $0.origin == .bundled && $0.availability == .ready }
    }

    /// Reads the source of `id` as `read(source:)` does, but takes no read token: a peek is a look that makes no flow stale.
    /// A choice or a listing waiting for its own read keeps its place however many peeks land meanwhile. The answer is the
    /// caller's to weigh; a peek changes no state.
    func peek(_ id: EffectID) async -> Result<EffectSource, EffectPackageProblem> {
        await packages.source(of: id)
    }

    /// Lifts the switch-off of each switched-off effect the listing has ready whose source has changed since it was switched off,
    /// so the next choice of it prepares the edited source. The records are compared by fingerprint (`EffectFingerprint.of`), so
    /// the comparison takes in the shader and its layout only. A row whose source cannot be read stays switched off. A record that
    /// a newer switch-off replaced while the sources were being read is kept. The settings are written only when something was
    /// lifted, and nothing is prepared here.
    func releaseEdited(in run: Int) async {
        let candidates = entries.compactMap { row -> (id: EffectID, recorded: EffectFingerprint)? in
            guard row.availability == .ready, let switchedOff = disabled[row.id] else { return nil }
            return (row.id, switchedOff.record.fingerprint)
        }
        guard !candidates.isEmpty else { return }
        // Read one at a time: the listing is a handful of rows, and each peek is a plain file read.
        var edited: [(id: EffectID, recorded: EffectFingerprint)] = []
        for candidate in candidates {
            if case .success(let source) = await peek(candidate.id), EffectFingerprint.of(source) != candidate.recorded {
                edited.append(candidate)
            }
        }
        guard epoch == run else { return }
        let lifted = edited.filter { disabled[$0.id]?.record.fingerprint == $0.recorded }
        guard !lifted.isEmpty else { return }
        for item in lifted { disabled[item.id] = nil }
        await settings.setDisabledEffects(disabled.values.map(\.record))
        guard epoch == run else { return }
        publish()
    }

    /// Prepares the bundled effect in place of `id`, the package effect that was just switched off, and publishes how that went.
    /// The choice stays `id`: the user's selection and the remembered one are not rewritten. Nothing is prepared when the choice
    /// moved on meanwhile (a `select`, a newer `prepare`, a new run) or when the runtime already holds the bundled effect. The
    /// source is read with `peek`, not `read(source:)`: a read takes a token, and that would make a listing or a choice still
    /// waiting for its source look stale.
    func holdBundled(instead id: EffectID, in run: Int) async {
        guard epoch == run, selection == id, let bundled = readyBundled, prepared?.id != bundled.id else {
            publish()
            return
        }
        let mine = generation
        let answer = await peek(bundled.id)
        guard epoch == run, generation == mine, selection == id, case .success(let source) = answer else {
            publish()
            return
        }
        await prepare(source, for: bundled.id, announcing: nil)
    }

    /// Lifts the switch-off of `id` and chooses it again. The record is forgotten and the settings written without it before
    /// the choice is made, so the choice runs instead of being refused by `select`. With no record there is nothing to lift:
    /// nothing is written, and the call is a plain `select`.
    func reenable(_ id: EffectID) async -> EffectSelectionOutcome {
        guard disabled[id] != nil else { return await select(id) }
        let mine = epoch
        disabled[id] = nil
        await settings.setDisabledEffects(disabled.values.map(\.record))
        // A run that ended or restarted while the record was being written owns the state now: this choice does not go on.
        guard epoch == mine else { return .unavailable(nil) }
        return await select(id)
    }

    /// The developer-facing line for a switch-off: the effect's name, why, and the bundled effect it falls back to. With no ready
    /// bundled effect there is nothing to fall back to, so the line ends after the reason.
    private func switchOffMessage(of id: EffectID, reason: EffectDisableReason) -> String {
        let cause: String
        switch reason {
        case .failure(let kind): cause = kind.rawValue
        case .overBudget: cause = "overBudget"
        }
        let fallback = readyBundled.map { "; back to '\($0.displayName)'" } ?? ""
        return "effect '\(displayName(of: id))' disabled (\(cause))\(fallback)"
    }
}
