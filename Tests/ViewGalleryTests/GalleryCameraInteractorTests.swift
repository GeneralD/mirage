import Combine
import Domain
import TestSupport
import Testing

@testable import ViewGallery

@Suite("GalleryCameraInteractor")
struct GalleryCameraInteractorTests {
    private let interactor = GalleryCameraInteractor(selection: cameraMenuState)

    private func firstState(of interactor: GalleryCameraInteractor) -> [CameraState] {
        let received = Collector<CameraState>()
        let subscription = interactor.state.sink { received.append($0) }
        withExtendedLifetime(subscription) {}
        return received.values
    }

    @Test("every subscription gets the camera state it was made with, at once")
    func publishesTheState() {
        #expect(firstState(of: interactor) == [cameraMenuState])
        #expect(firstState(of: interactor) == [cameraMenuState])
    }

    @Test("start, stop, selectDevice, selectResolution, selectFrameRate and setMirrored change nothing")
    func commandsDoNothing() {
        interactor.start()
        interactor.selectDevice("studio")
        interactor.selectResolution(CameraResolution(width: 1920, height: 1080))
        interactor.selectFrameRate(24)
        interactor.setMirrored(true)
        interactor.stop()

        #expect(firstState(of: interactor) == [cameraMenuState])
    }
}
