import Dependencies
import Domain

/// The decisions of the effects menu (epic #42, D5 / D6 / D11), in one actor: which
/// effect is chosen, when the runtime must prepare it again, and which outcome the
/// menu shows. Off the frame path and low-rate (a listing per saved edit, a selection
/// per click), so an actor is the right tool here (`.claude/rules/swift-idioms.md`);
/// the frame path never meets it, and it holds no `IOSurface`.
///
/// **The state is published only when it is settled.** A listing that needs a
/// `prepare` publishes after the runtime has answered, with the outcome; one that needs
/// none publishes at once. Identical states are not published twice.
///
/// **Newest wins, twice over.** The runtime keeps the effect of its newest `prepare`
/// (`EffectRuntimeRepository`), so what the menu shows must be the newest request's
/// outcome too. `generation` is taken in the same actor turn that calls `prepare` — no
/// suspension in between — so its order is the runtime's order. An answer that comes
/// back after a newer `prepare` was issued still reaches its own caller but publishes
/// nothing. Before it issues anything, each flow re-checks that the effect it read the
/// source of is still the chosen one: a `select` that arrives while a listing waits
/// for a source, or the other way round, leaves the effect the newest choice names to
/// the flow of that choice.
actor EffectCatalogSession {
    /// What the runtime was last handed: kept to tell a hot reload (same effect, new
    /// source) from a choice, and to hand the runtime nothing it already has.
    private struct Prepared: Equatable {
        let id: EffectID
        let source: EffectSource
    }

    @Dependency(\.effectPackageRepository) private var packages
    @Dependency(\.effectRuntimeRepository) private var runtime
    @Dependency(\.settingsRepository) private var settings
    @Dependency(\.developerLog) private var developerLog
    @Dependency(\.errorLog) private var errorLog

    private let broadcast: EffectCatalogBroadcast
    private var entries: [EffectCatalogEntry] = []
    /// The chosen effect: restored at the start of a run, set by `select`, replaced by the
    /// bundled one when the chosen one is gone. `nil` until the run has restored it and
    /// listed a catalog to settle it against.
    private var selection: EffectID?
    /// How the chosen effect's last attempt went; `nil` while that attempt is still running.
    private var outcome: EffectSelectionOutcome?
    private var prepared: Prepared?
    private var generation = 0

    init(broadcast: EffectCatalogBroadcast) {
        self.broadcast = broadcast
    }

    /// Restores the persisted choice, then follows the catalog until the caller's task is
    /// cancelled. A listing is the cue for everything: it is how a new package, a gone
    /// package and an edited shader all arrive (the Repository lists again after every
    /// change). One run at a time: the Interactor owns the task.
    func run() async {
        selection = await settings.selectedEffect()
        for await listing in packages.catalog() {
            await reconcile(listing)
        }
        end()
    }

    func select(_ id: EffectID) async -> EffectSelectionOutcome {
        guard let entry = entries.first(where: { $0.id == id }) else { return .unavailable(nil) }
        if case .broken(let problem) = entry.availability { return .unavailable(problem) }
        selection = id
        await settings.setSelectedEffect(id)
        let source = await packages.source(of: id)
        // Another choice (or a fallback) came in while this one waited: it owns the effect now.
        guard selection == id else { return .unavailable(nil) }
        switch source {
        case .success(let source): return await prepare(source, for: id, announcing: "selected")
        case .failure(let problem): return unreadable(id, problem)
        }
    }

    // MARK: - A listing

    private func reconcile(_ listing: [EffectCatalogEntry]) async {
        entries = listing
        guard let settled = settleSelection() else { return }
        let source = await packages.source(of: settled.id)
        guard selection == settled.id else { return }
        switch source {
        case .failure(let problem):
            unreadable(settled.id, problem)
        case .success(let source) where source == prepared?.source:
            prepared = Prepared(id: settled.id, source: source)
            publish()
        case .success(let source):
            // A fallback says what happened itself; a first choice and a hot reload are announced here.
            let announcement = settled.fellBack ? nil : (prepared?.id == settled.id ? "reloaded" : "selected")
            await prepare(source, for: settled.id, announcing: announcement)
        }
    }

    /// The effect this listing leaves chosen: the current choice when the listing has it ready,
    /// otherwise the bundled effect (which is a first start, a package that went away, or one
    /// whose files can no longer be used). A fallback is not remembered: the persisted choice
    /// stays the user's last explicit one, and comes back at the next launch if its package has.
    /// `nil` when the listing offers nothing to choose.
    private func settleSelection() -> (id: EffectID, fellBack: Bool)? {
        if let chosen = selection, entries.contains(where: { $0.id == chosen && $0.availability == .ready }) {
            return (chosen, false)
        }
        guard let bundled = entries.first(where: { $0.origin == .bundled && $0.availability == .ready }) else { return nil }
        let lost = selection.map(displayName(of:))
        selection = bundled.id
        if let lost {
            developerLog.record(.effect, "effect '\(lost)' is gone; back to '\(bundled.displayName)'")
        }
        return (bundled.id, lost != nil)
    }

    /// What the user knows `id` as: its row's name, or (the row is gone) the name of the source
    /// the runtime was last handed for it, or its key.
    private func displayName(of id: EffectID) -> String {
        entries.first { $0.id == id }?.displayName ?? (prepared?.id == id ? prepared?.source.name : nil) ?? id.key
    }

    // MARK: - Handing the runtime an effect

    /// Prepares `source` as the effect `id` and publishes how that went, unless a newer
    /// request was issued while the runtime was busy: that one publishes its own, and this
    /// answer only reaches its caller.
    @discardableResult
    private func prepare(_ source: EffectSource, for id: EffectID, announcing verb: String?) async -> EffectSelectionOutcome {
        generation += 1
        let mine = generation
        prepared = Prepared(id: id, source: source)
        outcome = nil
        if let verb {
            developerLog.record(.effect, "effect '\(source.name)' \(verb)")
        }

        let answer = await runtime.prepare(source).selectionOutcome
        guard generation == mine else { return answer }
        outcome = answer
        publish()
        return answer
    }

    /// The chosen effect is listed as usable but its source could not be read just now (the
    /// files changed between the listing and the read). The runtime keeps what it has;
    /// the menu is told, and the next listing tries again.
    @discardableResult
    private func unreadable(_ id: EffectID, _ problem: EffectPackageProblem) -> EffectSelectionOutcome {
        errorLog.record(.effect, "effect '\(displayName(of: id))' cannot be read: \(problem)")
        generation += 1
        outcome = .unavailable(problem)
        publish()
        return .unavailable(problem)
    }

    private func publish() {
        guard let selection else { return }
        let state = EffectCatalogState(entries: entries, selection: selection, outcome: outcome)
        guard state != broadcast.current else { return }
        broadcast.publish(state)
    }

    /// The run is over: close the streams, and forget everything so that the next run starts
    /// from the persisted choice. `generation` only grows, so an answer still pending from this
    /// run (the runtime ignores cancellation) publishes nothing into the next one.
    private func end() {
        generation += 1
        entries = []
        selection = nil
        outcome = nil
        prepared = nil
        broadcast.endObservations()
    }
}

extension Result where Success == Void, Failure == EffectFailure {
    fileprivate var selectionOutcome: EffectSelectionOutcome {
        switch self {
        case .success: .prepared
        case .failure(let failure): .failed(failure)
        }
    }
}
