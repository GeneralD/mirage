import Combine
import Domain

/// The `CameraSelectionInteractor` every camera menu screen draws from: it publishes the one camera state it was made with, to every
/// subscriber, and its commands do nothing. A screen shows a state; it does not move it. It is not a test double (`Sources` may
/// not use `TestDoubles`), and no shipped product links this module.
struct GalleryCameraInteractor {
    let selection: CameraState
}

extension GalleryCameraInteractor: CameraSelectionInteractor {
    var state: AnyPublisher<CameraState, Never> {
        Just(selection).eraseToAnyPublisher()
    }

    func start() {}

    func stop() {}

    func selectDevice(_ id: String) {}

    func selectResolution(_ resolution: CameraResolution) {}

    func selectFrameRate(_ framesPerSecond: Int) {}

    func setMirrored(_ isMirrored: Bool) {}
}
