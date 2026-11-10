import Combine
import Domain

/// The `EffectInteractor` every gallery screen draws from: it publishes the one catalog state it was made with, to every
/// subscriber, and its commands do nothing. A screen shows a state; it does not move it. It is not a test double (`Sources` may
/// not use `TestDoubles`), and no shipped product links this module.
struct GalleryEffectInteractor {
    let catalog: EffectCatalogState
}

extension GalleryEffectInteractor: EffectInteractor {
    var state: AnyPublisher<EffectCatalogState, Never> {
        Just(catalog).eraseToAnyPublisher()
    }

    func start() {}

    func stop() {}

    func select(_ id: EffectID) {}

    func openEffectsFolder() {}

    func setParameter(_ id: String, to value: EffectParameterValue) {}

    func resetParameters() {}
}
