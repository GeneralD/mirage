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
    func run() async

    /// The state now, then after every change (a new catalog, a selection, an outcome),
    /// until the stream ends. It starts from the current state when there is one, which
    /// is not before `run()` has listed the catalog and prepared the chosen effect, so an
    /// observer may be opened before `run()` starts. Any number of observers may be open at
    /// once, and each gets the same states. The stream ends when `run()` does.
    func observe() -> AsyncStream<EffectCatalogState>

    /// Chooses `id`: prepares it, remembers the choice, and answers how that went. The
    /// same answer reaches `observe()` as `outcome`, unless a newer `prepare` overtook this
    /// one (the newest request's outcome is the one shown). An `.unavailable` answer
    /// changes nothing, so it is only returned.
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
