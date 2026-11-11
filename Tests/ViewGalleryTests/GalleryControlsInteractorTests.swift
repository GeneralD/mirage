import Combine
import Domain
import TestSupport
import Testing

@testable import ViewGallery

@Suite("GalleryControlsInteractor")
struct GalleryControlsInteractorTests {
    private let controls = ControlsState(isBypassed: false, framesPerSecond: 30)

    private func firstState(of interactor: GalleryControlsInteractor) -> [ControlsState] {
        let received = Collector<ControlsState>()
        let subscription = interactor.state.sink { received.append($0) }
        withExtendedLifetime(subscription) {}
        return received.values
    }

    @Test("a subscriber gets the state the interactor was made with, at once")
    func publishesTheState() {
        let interactor = GalleryControlsInteractor(controls: controls)

        #expect(firstState(of: interactor) == [controls])
        #expect(firstState(of: interactor) == [controls])
    }

    @Test("start, stop and toggleBypass change nothing: a new subscriber still gets the same state")
    func commandsDoNothing() {
        let interactor = GalleryControlsInteractor(controls: controls)

        interactor.start()
        interactor.toggleBypass()
        interactor.stop()

        #expect(firstState(of: interactor) == [controls])
    }
}
