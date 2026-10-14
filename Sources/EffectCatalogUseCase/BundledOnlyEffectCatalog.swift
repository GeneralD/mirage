import Dependencies
import Domain

/// The effects menu with the bundled effect chosen and nothing else to choose: the
/// state it reports, once, is the first catalog the Repository lists with its first
/// entry selected. Registered as the host's live `EffectCatalogUseCase` until the real
/// UseCase lands in this module (epic #42, D10).
///
/// It prepares nothing and remembers nothing. That is not a lie about the runtime:
/// while nothing has been prepared the runtime applies the bundled default
/// (`BundledEffects.defaultEffect`), which is the one effect this catalog lists, so
/// choosing it is already what is running.
public struct BundledOnlyEffectCatalog: EffectCatalogUseCase, Sendable {
    @Dependency(\.effectPackageRepository) private var repository

    public init() {}

    /// There is no catalog to keep current, so this only waits: it returns when the
    /// caller's task is cancelled, as the real UseCase's `run()` does.
    public func run() async {
        let parked = AsyncStream<Void> { _ in }
        for await _ in parked {}
    }

    /// Yields the bundled-only state once and then stays open, since nothing changes it,
    /// until the consumer lets go.
    public func observe() -> AsyncStream<EffectCatalogState> {
        let repository = repository
        return AsyncStream { continuation in
            let listing = Task {
                for await entries in repository.catalog() {
                    guard let selection = entries.first?.id else { continue }
                    continuation.yield(EffectCatalogState(entries: entries, selection: selection))
                    return
                }
            }
            continuation.onTermination = { _ in listing.cancel() }
        }
    }

    /// `.prepared` for an effect the catalog lists, which is the one already running;
    /// `.unavailable` for any other.
    public func select(_ id: EffectID) async -> EffectSelectionOutcome {
        for await entries in repository.catalog() {
            return entries.contains { $0.id == id } ? .prepared : .unavailable(nil)
        }
        return .unavailable(nil)
    }

    public func openEffectsFolder() {
        repository.openEffectsFolder()
    }
}
