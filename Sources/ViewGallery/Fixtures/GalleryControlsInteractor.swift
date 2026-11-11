import Combine
import Domain

/// The `ControlsInteractor` the controls-menu screens draw from: it publishes the one controls state it was made with, to every
/// subscriber, and its commands do nothing. A screen shows a state; it does not move it. It is not a test double (`Sources` may
/// not use `TestDoubles`), and no shipped product links this module.
struct GalleryControlsInteractor {
    let controls: ControlsState
}

extension GalleryControlsInteractor: ControlsInteractor {
    var state: AnyPublisher<ControlsState, Never> {
        Just(controls).eraseToAnyPublisher()
    }

    func start() {}

    func stop() {}

    func toggleBypass() {}
}
