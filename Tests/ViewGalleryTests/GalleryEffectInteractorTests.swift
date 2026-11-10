import Combine
import Domain
import TestSupport
import Testing

@testable import ViewGallery

@Suite("GalleryEffectInteractor")
struct GalleryEffectInteractorTests {
    private let interactor = GalleryEffectInteractor(catalog: effectPickerCatalog)

    private func firstState(of interactor: GalleryEffectInteractor) -> [EffectCatalogState] {
        let received = Collector<EffectCatalogState>()
        let subscription = interactor.state.sink { received.append($0) }
        withExtendedLifetime(subscription) {}
        return received.values
    }

    @Test("every subscription gets the catalog it was made with, at once")
    func publishesTheCatalog() {
        #expect(firstState(of: interactor) == [effectPickerCatalog])
        #expect(firstState(of: interactor) == [effectPickerCatalog])
    }

    @Test("start, stop, select, openEffectsFolder, setParameter and resetParameters change nothing")
    func commandsDoNothing() {
        interactor.start()
        interactor.select(EffectID(origin: .package, key: "ripple"))
        interactor.openEffectsFolder()
        interactor.setParameter("amount", to: .float(0.5))
        interactor.resetParameters()
        interactor.stop()

        #expect(firstState(of: interactor) == [effectPickerCatalog])
    }
}
