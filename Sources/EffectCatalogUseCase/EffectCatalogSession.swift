import Dependencies
import Domain

/// The decisions of the effects menu (epic #42, D5 / D6 / D11), in one actor: which
/// effect is chosen, when the runtime must prepare it again, and which outcome the
/// menu shows. Off the frame path and low-rate (a listing per saved edit, a selection
/// per click), so an actor is the right tool here (`.claude/rules/swift-idioms.md`);
/// the frame path never meets it, and it holds no `IOSurface`.
///
/// **The state is published whenever it changes.** A listing that needs a `prepare`
/// publishes after the runtime has answered, with the outcome; one that needs none
/// publishes at once, carrying what the last attempt has answered so far (`outcome` is
/// `nil` while that attempt is still out). A source that cannot be read shows its problem
/// over the runtime's answer, which comes back with the next listing that reads it.
/// Identical states are not published twice.
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
    /// source) from a choice, to hand the runtime nothing it already has, and to say how
    /// the runtime took it (`answer`, `nil` while that is still out).
    private struct Prepared {
        var id: EffectID
        let source: EffectSource
        var answer: EffectSelectionOutcome?
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
    private var prepared: Prepared?
    /// Why the chosen effect's source could not be read at the last look; `nil` once a look
    /// succeeds (or a `prepare` is issued). It is shown over the runtime's answer, never
    /// instead of it: the runtime keeps running what it has.
    private var unreadableSource: EffectPackageProblem?
    private var generation = 0
    /// One per run, taken in the turn `run()` begins. A flow that was suspended across a run
    /// boundary (a choice waiting for its source, a cancelled run waiting for the runtime) finds
    /// the number changed when it resumes, and leaves what is now the new run's alone.
    private var epoch = 0
    /// One per look at an effect's source, taken in the turn that issues the read. Of two reads
    /// of the same effect (a choice and a listing, say) only the newer may act on its answer:
    /// the older one may hold files that have been edited since.
    private var readToken = 0

    /// How the chosen effect's last attempt went: the problem if its source could not be read
    /// at the last look, otherwise how the runtime took what it was last handed, if that was
    /// the chosen effect. `nil` while that attempt is still running, or has not begun: a choice
    /// is made before its `prepare` is issued, and an answer for the effect chosen before can
    /// arrive in between, which is not this choice's.
    private var outcome: EffectSelectionOutcome? {
        unreadableSource.map { .unavailable($0) } ?? (prepared?.id == selection ? prepared?.answer : nil)
    }

    init(broadcast: EffectCatalogBroadcast) {
        self.broadcast = broadcast
    }

    /// Restores the persisted choice, then follows the catalog until the caller's task is
    /// cancelled. A listing is the cue for everything: it is how a new package, a gone
    /// package and an edited shader all arrive (the Repository lists again after every
    /// change). The Interactor owns the task, and starts the next run only after the one before
    /// has returned, but a run that is started while the one before it still waits for the
    /// runtime takes over at once: the old one leaves without touching what is the new one's.
    func run() async {
        epoch += 1
        let mine = epoch
        clear()
        broadcast.forget()
        let restored = await settings.selectedEffect()
        guard epoch == mine else { return }
        selection = restored
        for await listing in packages.catalog() {
            await reconcile(listing, in: mine)
        }
        guard epoch == mine else { return }
        end()
    }

    func select(_ id: EffectID) async -> EffectSelectionOutcome {
        guard let entry = entries.first(where: { $0.id == id }) else { return .unavailable(nil) }
        if case .broken(let problem) = entry.availability { return .unavailable(problem) }
        let mine = epoch
        selection = id
        await settings.setSelectedEffect(id)
        // Another choice (or a fallback, or a new run) came in while the choice was being remembered: it owns the effect now.
        guard epoch == mine, selection == id else { return .unavailable(nil) }
        let source = await read(source: id)
        // Another choice, a newer read of this effect, a fallback or a new run came in while this one waited: it owns the effect now.
        guard epoch == mine, isNewest(source), selection == id else { return .unavailable(nil) }
        switch source.answer {
        case .success(let source): return await prepare(source, for: id, announcing: "selected")
        case .failure(let problem): return unreadable(id, problem)
        }
    }

    // MARK: - A listing

    private func reconcile(_ listing: [EffectCatalogEntry], in run: Int) async {
        guard epoch == run else { return }
        entries = listing
        guard let settled = settleSelection() else { return }
        let source = await read(source: settled.id)
        guard epoch == run, isNewest(source), selection == settled.id else { return }
        switch source.answer {
        case .failure(let problem):
            unreadable(settled.id, problem)
        case .success(let source) where source == prepared?.source:
            // The runtime has this very source already. If the last look could not read it, the menu
            // goes back to how the runtime took it (which may still be out).
            unreadableSource = nil
            prepared?.id = settled.id
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

    // MARK: - Reading a source

    /// What a look at an effect's source found, and the number the look was issued under.
    private struct SourceRead {
        let token: Int
        let answer: Result<EffectSource, EffectPackageProblem>
    }

    /// Reads the source of `id`. The number is taken before the read is issued, with no
    /// suspension in between, so a later read always holds a later number.
    private func read(source id: EffectID) async -> SourceRead {
        readToken += 1
        let token = readToken
        return SourceRead(token: token, answer: await packages.source(of: id))
    }

    /// Whether no read was issued after `read`. A read that is not the newest may hold files that
    /// have been edited since, whichever effect it was for, and must not act on its answer.
    private func isNewest(_ read: SourceRead) -> Bool {
        read.token == readToken
    }

    // MARK: - Handing the runtime an effect

    /// Prepares `source` as the effect `id` and publishes how that went, unless a newer
    /// request was issued while the runtime was busy: that one publishes its own, and this
    /// answer only reaches its caller.
    @discardableResult
    private func prepare(_ source: EffectSource, for id: EffectID, announcing verb: String?) async -> EffectSelectionOutcome {
        generation += 1
        let mine = generation
        prepared = Prepared(id: id, source: source, answer: nil)
        unreadableSource = nil
        if let verb {
            developerLog.record(.effect, "effect '\(source.name)' \(verb)")
        }

        let answer = await runtime.prepare(source).selectionOutcome
        guard generation == mine else { return answer }
        prepared?.answer = answer
        publish()
        return answer
    }

    /// The chosen effect is listed as usable but its source could not be read just now (the
    /// files changed between the listing and the read). The runtime keeps what it has, and
    /// a `prepare` still out goes on: its answer is kept (`Prepared.answer`) but the menu
    /// shows the problem until a listing reads the source again, which brings the answer back.
    @discardableResult
    private func unreadable(_ id: EffectID, _ problem: EffectPackageProblem) -> EffectSelectionOutcome {
        errorLog.record(.effect, "effect '\(displayName(of: id))' cannot be read: \(problem)")
        unreadableSource = problem
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
    /// from the persisted choice. Only the run that is still the newest ends the streams: one
    /// that a newer run took over from leaves them, and everything else, to that run.
    private func end() {
        clear()
        broadcast.endObservations()
    }

    /// Forgets everything a run decided, so that the next run starts from the persisted choice.
    /// `generation` only grows, so an answer still pending from the run before (the runtime
    /// ignores cancellation) publishes nothing into the next one.
    private func clear() {
        generation += 1
        entries = []
        selection = nil
        prepared = nil
        unreadableSource = nil
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
