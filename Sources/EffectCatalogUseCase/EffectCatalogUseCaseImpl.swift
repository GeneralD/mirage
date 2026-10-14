import Dependencies
import Domain

/// The effects menu's policy (epic #42, D5 / D6 / D11): choosing an effect `prepare`s it on
/// the effect runtime, a change to the chosen effect's source `prepare`s it again (hot
/// reload), a chosen package that goes away falls back to the bundled effect, and the
/// choice is restored at launch. The pipeline never learns that effects exist.
///
/// The decisions live in `EffectCatalogSession`, an actor; this type is the port's
/// face: `observe()` and `openEffectsFolder()` are synchronous in the port, so they are
/// answered here, from the broadcast the session publishes into and the Repository.
///
/// It resolves the three ports it is made of — the catalog and the effects' sources
/// (`EffectPackageRepository`), the runtime (`EffectRuntimeRepository`) and the
/// persisted choice (`SettingsRepository`) — and the two logs. A compile failure is not
/// logged here: the runtime logs it once, and a second line would only repeat it.
public struct EffectCatalogUseCaseImpl: Sendable {
    @Dependency(\.effectPackageRepository) private var packages
    private let broadcast: EffectCatalogBroadcast
    private let session: EffectCatalogSession

    public init() {
        let broadcast = EffectCatalogBroadcast()
        self.broadcast = broadcast
        session = EffectCatalogSession(broadcast: broadcast)
    }
}

extension EffectCatalogUseCaseImpl: EffectCatalogUseCase {
    public func run() async {
        await session.run()
    }

    /// The state now (none until the run has settled its first one), then every change; any
    /// number of observers each get the same states. The stream ends when the run does.
    public func observe() -> AsyncStream<EffectCatalogState> {
        broadcast.observe()
    }

    public func select(_ id: EffectID) async -> EffectSelectionOutcome {
        await session.select(id)
    }

    public func openEffectsFolder() {
        packages.openEffectsFolder()
    }
}
