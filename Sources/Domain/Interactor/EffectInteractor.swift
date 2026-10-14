import Combine
import Dependencies

/// The effects menu's Combine pipeline over `EffectCatalogUseCase` (epic #42, D9): it
/// turns the UseCase's stream into a publisher the Presenter subscribes to, and owns
/// the one task that runs the catalog. The menu reads `state`; its items call
/// `select` and `openEffectsFolder`.
public protocol EffectInteractor: Sendable {
    /// The catalog's state, the current one first once `start()` has run.
    var state: AnyPublisher<EffectCatalogState, Never> { get }

    /// Starts the catalog and begins publishing `state`. Calling it again while started does nothing.
    func start()

    /// Ends what `start()` began. `state` publishes nothing more until the next `start()`.
    func stop()

    /// Chooses `id`. The answer arrives in `state` as the outcome.
    func select(_ id: EffectID)

    func openEffectsFolder()
}

public enum EffectInteractorKey: TestDependencyKey {
    public static let testValue: any EffectInteractor = UnimplementedEffectInteractor()
}

extension DependencyValues {
    public var effectInteractor: any EffectInteractor {
        get { self[EffectInteractorKey.self] }
        set { self[EffectInteractorKey.self] = newValue }
    }
}

private struct UnimplementedEffectInteractor: EffectInteractor {
    var state: AnyPublisher<EffectCatalogState, Never> {
        reportIssue("EffectInteractor.state not implemented")
        return Empty(completeImmediately: true).eraseToAnyPublisher()
    }

    func start() {
        reportIssue("EffectInteractor.start not implemented")
    }

    func stop() {
        reportIssue("EffectInteractor.stop not implemented")
    }

    func select(_ id: EffectID) {
        reportIssue("EffectInteractor.select not implemented")
    }

    func openEffectsFolder() {
        reportIssue("EffectInteractor.openEffectsFolder not implemented")
    }
}
