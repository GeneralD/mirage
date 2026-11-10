import Combine
import Dependencies

/// The effects menu's Combine pipeline over `EffectCatalogUseCase` (epic #42, D9): it
/// turns the UseCase's stream into a publisher the Presenter subscribes to, and owns
/// the one task that runs the catalog. The menu reads `state`; its items call
/// `select` and `openEffectsFolder`.
public protocol EffectInteractor: Sendable {
    /// The catalog's state, the current one first once `start()` has run. The panel reads
    /// `state.parameters`, the chosen effect's parameters with their current values.
    var state: AnyPublisher<EffectCatalogState, Never> { get }

    /// Starts the catalog and begins publishing `state`. Calling it again while started
    /// restarts it: the first run ends before the next begins, so exactly one is alive.
    /// Returns at once; `start()` and `stop()` are carried out in the order they were given.
    func start()

    /// Ends what `start()` began. `state` publishes nothing more until the next `start()`.
    /// Returns at once.
    func stop()

    /// Chooses `id`. The answer arrives in `state` as the outcome. A choice is not queued behind
    /// `start()`, `stop()` or another choice, so a slow preparation never holds a newer choice
    /// back; two calls made in the same instant may therefore reach the UseCase in either order.
    /// A caller that needs an order waits for the first outcome in `state`.
    func select(_ id: EffectID)

    /// Sets the parameter `id` of the chosen effect to `value`. The UseCase clamps and snaps it, and the
    /// result arrives in `state`. Calls are carried out one at a time, in the order they were made, by a
    /// queue of their own: `start()`, `stop()` and `select(_:)` neither wait for it nor hold it back.
    /// Returns at once.
    func setParameter(_ id: String, to value: EffectParameterValue)

    /// Puts every parameter of the chosen effect back to its default. It shares the order of
    /// `setParameter(_:to:)`, so a reset lands after the sets made before it. Returns at once.
    func resetParameters()

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

    func setParameter(_ id: String, to value: EffectParameterValue) {
        reportIssue("EffectInteractor.setParameter not implemented")
    }

    func resetParameters() {
        reportIssue("EffectInteractor.resetParameters not implemented")
    }

    func openEffectsFolder() {
        reportIssue("EffectInteractor.openEffectsFolder not implemented")
    }
}
