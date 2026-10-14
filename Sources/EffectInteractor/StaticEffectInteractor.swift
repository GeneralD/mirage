import Combine
import Domain

/// An effects menu that never changes: `state` publishes the one state it was made
/// with (nothing at all when it was made with none), `start` and `stop` do nothing, and
/// no command has an effect. Registered as the host's live `EffectInteractor` until the
/// real Interactor lands in this module (epic #42, D10), so the menu lane can be wired
/// before the pipeline under it is.
public struct StaticEffectInteractor: EffectInteractor, Sendable {
    private let current: EffectCatalogState?

    public init(state: EffectCatalogState? = nil) {
        current = state
    }

    public var state: AnyPublisher<EffectCatalogState, Never> {
        current.map { CurrentValueSubject<EffectCatalogState, Never>($0).eraseToAnyPublisher() }
            ?? Empty(completeImmediately: false).eraseToAnyPublisher()
    }

    public func start() {}

    public func stop() {}

    public func select(_ id: EffectID) {}

    public func openEffectsFolder() {}
}
