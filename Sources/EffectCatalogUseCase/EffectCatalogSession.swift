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
    /// the runtime took it (`answer`, `nil` while that is still out). `model` holds the
    /// parameter values handed with `source`, which the panel shows and edits.
    struct Prepared {
        var id: EffectID
        let source: EffectSource
        var answer: EffectSelectionOutcome?
        var model: ParameterModel
        /// The block the runtime was last handed for `source`: the one `prepare` carried, or the last resend. A write made
        /// while the prepare is out goes to the runtime at once but does not update this, so the answer can tell it moved.
        var sent: EffectParameterBlock
        /// The compiler's diagnostic for a source the runtime refused, asked for once with `answer`; `nil` for a source that compiled.
        var compilerMessage: String? = nil
    }

    @Dependency(\.effectPackageRepository) var packages
    @Dependency(\.effectRuntimeRepository) var runtime
    @Dependency(\.settingsRepository) var settings
    @Dependency(\.developerLog) var developerLog
    @Dependency(\.errorLog) var errorLog

    let broadcast: EffectCatalogBroadcast
    var entries: [EffectCatalogEntry] = []
    /// The chosen effect: restored at the start of a run, set by `select`, replaced by the
    /// bundled one when the chosen one is gone. `nil` until the run has restored it and
    /// listed a catalog to settle it against.
    var selection: EffectID?
    var prepared: Prepared?
    /// Why the chosen effect's source could not be read at the last look; `nil` once a look
    /// succeeds (or a `prepare` is issued). It is shown over the runtime's answer, never
    /// instead of it: the runtime keeps running what it has.
    var unreadableSource: EffectPackageProblem?
    var generation = 0
    /// One per run, taken in the turn `run()` begins. A flow that was suspended across a run
    /// boundary (a choice waiting for its source, a cancelled run waiting for the runtime) finds
    /// the number changed when it resumes, and leaves what is now the new run's alone.
    var epoch = 0
    /// One per look at an effect's source, taken in the turn that issues the read. Of two reads
    /// of the same effect (a choice and a listing, say) only the newer may act on its answer:
    /// the older one may hold files that have been edited since.
    var readToken = 0
    /// The effect health counts the outcomes of: the one the runtime was last prepared with, and the policy counting its
    /// passes. Every `prepare` replaces it; a run clears it.
    var armed: ArmedHealth?
    /// The effects health has switched off, each with the record its reason comes from. A run starts it from the records the settings hold.
    var disabled: [EffectID: DisabledEntry] = [:]
    /// Set when the bundled effect itself is switched off by health: no effect can move frames, so the menu says the GPU is
    /// unavailable. A passing pass of any effect lowers it again; a run clears it.
    var isGPUUnavailable = false

    /// How the chosen effect's last attempt went: the problem if its source could not be read
    /// at the last look, otherwise how the runtime took what it was last handed, if that was
    /// the chosen effect. `nil` while that attempt is still running, or has not begun: a choice
    /// is made before its `prepare` is issued, and an answer for the effect chosen before can
    /// arrive in between, which is not this choice's.
    var outcome: EffectSelectionOutcome? {
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
        // Subscribed before the first suspension: the runtime replays nothing to a subscriber that comes later.
        let outcomes = runtime.outcomes()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [self] in await follow(outcomes, in: mine) }
            await listen(in: mine)
            group.cancelAll()
        }
        guard epoch == mine else { return }
        end()
    }

    /// Restores the persisted choice and the switched-off effects, then reconciles every listing of the catalog for `run`.
    private func listen(in run: Int) async {
        let restored = await settings.selectedEffect()
        let stored = await settings.disabledEffects()
        guard epoch == run else { return }
        selection = restored
        // The records of the bundled effect come from another build: they are read away, and never written back.
        disabled = Dictionary(
            stored.filter { $0.id.origin == .package }.map { ($0.id, DisabledEntry(record: $0)) },
            uniquingKeysWith: { _, last in last })
        for await listing in packages.catalog() {
            await reconcile(listing, in: run)
        }
    }

    /// Chooses the effect `id` and prepares it. A switched-off effect is refused at the door, as a broken package is.
    func select(_ id: EffectID) async -> EffectSelectionOutcome {
        guard let entry = entries.first(where: { $0.id == id }) else { return .unavailable(nil) }
        if case .broken(let problem) = entry.availability { return .unavailable(problem) }
        guard disabled[id] == nil else { return .unavailable(nil) }
        let mine = epoch
        selection = id
        await settings.setSelectedEffect(id)
        // Another choice (or a fallback, or a new run) came in while the choice was being remembered: it owns the effect now.
        guard epoch == mine, selection == id else { return .unavailable(nil) }
        let source = await read(source: id)
        // Another choice, a newer read, a fallback, a new run or a switch-off came in while this one waited: it owns the effect now.
        guard epoch == mine, isNewest(source), selection == id, disabled[id] == nil else { return .unavailable(nil) }
        switch source.answer {
        case .success(let effect):
            let restoring = await startingValues(for: id, source: effect)
            // The stored values were read in an await of their own: the same check again before anything is prepared.
            guard epoch == mine, isNewest(source), selection == id, disabled[id] == nil else { return .unavailable(nil) }
            return await prepare(effect, for: id, announcing: "selected", restoring: restoring)
        case .failure(let problem): return unreadable(id, problem)
        }
    }

    /// Chooses the ready neighbour of the chosen effect, as `select` chooses it. The neighbour is found in the same
    /// actor turn that `select` starts from, so no other message can move the choice in between.
    func selectAdjacent(_ step: EffectStep) async -> EffectSelectionOutcome? {
        guard let id = effectNeighbor(of: selection, in: entries, step: step) else { return nil }
        return await select(id)
    }

    /// Sets one parameter of the chosen effect (`docs/hackathon/mvp-cd/specs/parameters.md`). It prepares nothing, and it
    /// is not `async`: the turn has no suspension, so the model update, the publish and the runtime write cannot be
    /// interleaved with another message.
    func setParameter(_ id: String, to value: EffectParameterValue) {
        guard let current = prepared, current.id == selection else {
            developerLog.record(.effect, "parameter '\(id)' ignored: no effect is chosen")
            return
        }
        guard let setting = current.model.setting(id, to: value) else {
            developerLog.record(.effect, "parameter '\(id)' of '\(current.source.name)' rejected")
            return
        }
        adopt(setting)
    }

    /// Puts every parameter of the chosen effect back to its default, under the rules of `setParameter`.
    func resetParameters() {
        guard let current = prepared, current.id == selection else {
            developerLog.record(.effect, "parameter reset ignored: no effect is chosen")
            return
        }
        adopt(current.model.resetting())
    }

    /// Takes the model an edit produced. A model equal to the one held changes nothing; any other is published and
    /// handed to the runtime with the source it runs, in this same turn.
    private func adopt(_ model: ParameterModel) {
        guard let current = prepared, model != current.model else { return }
        prepared?.model = model
        publish()
        runtime.setParameters(model.block, of: current.source)
    }

    // MARK: - A listing

    private func reconcile(_ listing: [EffectCatalogEntry], in run: Int) async {
        guard epoch == run else { return }
        entries = listing
        await releaseEdited(in: run)
        guard epoch == run else { return }
        guard let settled = settleSelection() else { return }
        // A switched-off effect is never prepared again: the bundled effect stands in for it, as it did at the switch-off.
        guard disabled[settled.id] == nil else {
            await holdBundled(instead: settled.id, in: run)
            return
        }
        let source = await read(source: settled.id)
        guard epoch == run, isNewest(source), selection == settled.id else { return }
        switch source.answer {
        case .failure(let problem):
            unreadable(settled.id, problem)
        case .success(let source) where source == prepared?.source && (prepared?.id == settled.id || source.parameters.isEmpty):
            // The runtime has this very source already. If the last look could not read it, the menu
            // goes back to how the runtime took it (which may still be out). A source that declares
            // parameters, now chosen under another id, is prepared afresh: its model is the other effect's.
            unreadableSource = nil
            prepared?.id = settled.id
            publish()
        case .success(let effect):
            let restoring = await startingValues(for: settled.id, source: effect)
            // The stored values were read in an await of their own: the listing's check again before anything is prepared.
            guard epoch == run, isNewest(source), selection == settled.id else { return }
            // A fallback says what happened itself; a first choice and a hot reload are announced here.
            let announcement = settled.fellBack ? nil : (prepared?.id == settled.id ? "reloaded" : "selected")
            await prepare(effect, for: settled.id, announcing: announcement, restoring: restoring)
        }
    }

    /// The effect this listing leaves chosen: the current choice when the listing has it ready,
    /// otherwise the bundled effect (which is a first start, a package that went away, or one
    /// whose files can no longer be used). A fallback is not remembered: the persisted choice
    /// stays the user's last explicit one, and comes back at the next launch if its package has.
    /// `nil` when the listing offers nothing to choose.
    func settleSelection() -> (id: EffectID, fellBack: Bool)? {
        if let chosen = selection, entries.contains(where: { $0.id == chosen && $0.availability == .ready }) {
            return (chosen, false)
        }
        guard let bundled = readyBundled else { return nil }
        let lost = selection.map(displayName(of:))
        selection = bundled.id
        if let lost {
            developerLog.record(.effect, "effect '\(lost)' is gone; back to '\(bundled.displayName)'")
        }
        return (bundled.id, lost != nil)
    }

    /// What the user knows `id` as: its row's name, or (the row is gone) the name of the source
    /// the runtime was last handed for it, or its key.
    func displayName(of id: EffectID) -> String {
        entries.first { $0.id == id }?.displayName ?? (prepared?.id == id ? prepared?.source.name : nil) ?? id.key
    }

    // MARK: - Handing the runtime an effect

    /// The stored values a choice of `id` starts from: what the settings hold for it, read once, when `source` declares
    /// parameters and `id` is not the effect already prepared. A hot reload or a re-choice of that one keeps the values in
    /// memory, which are the newest, so it reads nothing; a source that declares none reads nothing either.
    private func startingValues(for id: EffectID, source: EffectSource) async -> [String: EffectParameterValue] {
        guard !source.parameters.isEmpty, prepared?.id != id else { return [:] }
        return await settings.parameterValues(of: id)
    }

    /// Prepares `source` as the effect `id` and publishes how that went, unless a newer
    /// request was issued while the runtime was busy: that one publishes its own, and this
    /// answer only reaches its caller.
    @discardableResult
    func prepare(
        _ source: EffectSource, for id: EffectID, announcing verb: String?, restoring stored: [String: EffectParameterValue] = [:]
    ) async -> EffectSelectionOutcome {
        generation += 1
        let mine = generation
        // A hot reload or a re-choice of the same effect keeps its values; any other choice starts from the stored ones
        // (the defaults, when it holds none).
        let model =
            if let previous = prepared, previous.id == id {
                previous.model.respecified(source.parameters)
            } else {
                ParameterModel(specs: source.parameters, restoring: stored)
            }
        let block = model.block
        prepared = Prepared(id: id, source: source, answer: nil, model: model, sent: block)
        armed = ArmedHealth(id: id, fingerprint: .of(source), policy: EffectHealthPolicy())
        unreadableSource = nil
        if let verb {
            developerLog.record(.effect, "effect '\(source.name)' \(verb)")
        }

        let answer = await runtime.prepare(source, parameters: block).selectionOutcome
        guard generation == mine else { return answer }
        let message = await diagnostic(of: source, answered: answer)
        // The diagnostic is an await of its own: a newer request may have been issued while it was asked for.
        guard generation == mine else { return answer }
        prepared?.answer = answer
        prepared?.compilerMessage = message
        publish()
        resendIfMoved(for: id)
        return answer
    }

    /// Hands the runtime the model's block again when a write made while the prepare of `id` was out left it different from
    /// the block that prepare carried. That write reached the runtime at once, but the runtime may have dropped it: it can
    /// land before the `begin` of the prepare (`EffectRuntimeStateDataSourceImpl.setParameters`). Synchronous, so the answer
    /// adds no suspension, and the outcome the prepare returns is left as it is.
    private func resendIfMoved(for id: EffectID) {
        guard let current = prepared, current.id == id else { return }
        let block = current.model.block
        guard block != current.sent else { return }
        prepared?.sent = block
        runtime.setParameters(block, of: current.source)
    }

    /// What the runtime says about a source it has just refused. Asked only for a refusal: a source that compiled has none to say.
    private func diagnostic(of source: EffectSource, answered answer: EffectSelectionOutcome) async -> String? {
        guard case .failed = answer else { return nil }
        return await runtime.compilerMessage(of: source)
    }

    /// The chosen effect is listed as usable but its source could not be read just now (the
    /// files changed between the listing and the read). The runtime keeps what it has, and
    /// a `prepare` still out goes on: its answer is kept (`Prepared.answer`) but the menu
    /// shows the problem until a listing reads the source again, which brings the answer back.
    @discardableResult
    func unreadable(_ id: EffectID, _ problem: EffectPackageProblem) -> EffectSelectionOutcome {
        errorLog.record(.effect, "effect '\(displayName(of: id))' cannot be read: \(problem)")
        unreadableSource = problem
        publish()
        return .unavailable(problem)
    }

    func publish() {
        guard let selection else { return }
        // The parameters belong to the effect the runtime was handed: while a choice is still out, the panel lists none.
        let parameters = prepared?.id == selection ? (prepared?.model.states ?? []) : []
        let state = EffectCatalogState(
            entries: entries, selection: selection, outcome: outcome, parameters: parameters,
            disabled: disabled.mapValues(\.record.reason), isGPUUnavailable: isGPUUnavailable,
            compilerMessage: shownDiagnostic)
        guard state != broadcast.current else { return }
        broadcast.publish(state)
    }

    /// The diagnostic the menu shows: the chosen effect's, and only while its last attempt is `.failed`. An unreadable
    /// source's problem replaces that outcome, so the diagnostic goes with it.
    private var shownDiagnostic: String? {
        guard case .failed? = outcome else { return nil }
        return prepared?.compilerMessage
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
    func clear() {
        generation += 1
        entries = []
        selection = nil
        prepared = nil
        unreadableSource = nil
        armed = nil
        disabled = [:]
        isGPUUnavailable = false
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
