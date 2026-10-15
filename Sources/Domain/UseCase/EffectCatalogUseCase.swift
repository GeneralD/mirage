import Dependencies

/// The effects menu's policy (epic #42, D5 / D6 / D11): which effect is chosen and
/// what comes of running it. Choosing an effect `prepare`s it on the effect runtime
/// (the pipeline never learns that effects exist), a change to the chosen effect's
/// source `prepare`s it again (hot reload), a chosen package that goes away falls back
/// to the bundled default, and the choice is restored at launch.
public protocol EffectCatalogUseCase: Sendable {
    /// Keeps the catalog, the selection and the hot reload alive until the caller's
    /// task is cancelled: the one long-lived task of the effects menu, started by its
    /// Interactor.
    ///
    /// A run may be started while the one before it is still finishing: the runtime does
    /// not cancel a `prepare`, so a cancelled run can still be waiting for one. The new run
    /// takes over at once, and the old one ends without touching it: it clears nothing of
    /// the new run's state and ends no stream, so the streams open by then end with the new
    /// run, not with the old.
    func run() async

    /// The state now, then after every change (a new catalog, a selection, an outcome),
    /// until the stream ends. It starts from the current state when there is one, which
    /// is not before `run()` has listed the catalog and prepared the chosen effect, so an
    /// observer may be opened before `run()` starts. Any number of observers may be open at
    /// once, and each gets the same states. The stream ends when `run()` does.
    ///
    /// Open it while no run is ending. The stream is subscribed in two steps (the states,
    /// then the end), and a run ends in two (the end, then forgetting the state), so one
    /// opened in the very instant a run ends may be handed that run's last state, or miss
    /// the end and stay open into the next run. The Interactor opens its stream as its run
    /// begins, after the run before has returned, and so never meets that instant.
    func observe() -> AsyncStream<EffectCatalogState>

    /// Chooses `id`: prepares it, remembers the choice, and answers how that went. The
    /// same answer reaches `observe()` as `outcome`, unless a newer `prepare` overtook this
    /// one (the newest request's outcome is the one shown).
    ///
    /// What an `.unavailable` answer means depends on why there was nothing to prepare:
    /// - A broken package, or an id the catalog does not have, is refused up front: the
    ///   answer is only returned, and nothing changes (no choice, nothing remembered,
    ///   nothing published, the runtime not called).
    /// - A ready package becomes the choice and is remembered before its source is read.
    ///   When the source cannot be read just then, the answer is `.unavailable(problem)`
    ///   and the choice and the remembered one stand, the runtime keeps the effect it
    ///   has, and the problem is the outcome `observe()` shows until a listing reads the
    ///   source again.
    /// - A choice overtaken while it was being remembered or while its source was being
    ///   read answers `.unavailable(nil)`: it prepared nothing, and what overtook it owns
    ///   the effect and the outcome. That is another choice, the catalog losing the package,
    ///   a newer read of this effect's source (by a listing or by another choice of it),
    ///   or a new `run()`.
    func select(_ id: EffectID) async -> EffectSelectionOutcome

    /// Shows the effects folder to the user.
    func openEffectsFolder()
}

public enum EffectCatalogUseCaseKey: TestDependencyKey {
    public static let testValue: any EffectCatalogUseCase = UnimplementedEffectCatalogUseCase()
}

extension DependencyValues {
    public var effectCatalogUseCase: any EffectCatalogUseCase {
        get { self[EffectCatalogUseCaseKey.self] }
        set { self[EffectCatalogUseCaseKey.self] = newValue }
    }
}

private struct UnimplementedEffectCatalogUseCase: EffectCatalogUseCase {
    func run() async {
        reportIssue("EffectCatalogUseCase.run not implemented")
    }

    func observe() -> AsyncStream<EffectCatalogState> {
        reportIssue("EffectCatalogUseCase.observe not implemented")
        return AsyncStream { $0.finish() }
    }

    func select(_ id: EffectID) async -> EffectSelectionOutcome {
        reportIssue("EffectCatalogUseCase.select not implemented")
        return .unavailable(nil)
    }

    func openEffectsFolder() {
        reportIssue("EffectCatalogUseCase.openEffectsFolder not implemented")
    }
}
