import Combine
import Domain
import TestSupport
import Testing

@testable import ViewGallery

@Suite("GallerySettingsInteractor")
struct GallerySettingsInteractorTests {
    private let settings = SettingsState(launchAtLogin: .needsApproval, hotkeysEnabled: false, hotkeys: .conflicted([.nextEffect]))

    private func firstState(of interactor: GallerySettingsInteractor) -> [SettingsState] {
        let received = Collector<SettingsState>()
        let subscription = interactor.state.sink { received.append($0) }
        withExtendedLifetime(subscription) {}
        return received.values
    }

    @Test("every subscription receives the settings as they were made, at once")
    func publishesTheSettings() {
        let interactor = GallerySettingsInteractor(settings: settings)

        #expect(firstState(of: interactor) == [settings])
        #expect(firstState(of: interactor) == [settings])
    }

    @Test("refresh, each command and resetAll change nothing: a later subscription still gets the same settings")
    func commandsDoNothing() async {
        let interactor = GallerySettingsInteractor(settings: settings)

        interactor.refresh()
        interactor.setLaunchAtLogin(true)
        interactor.openLoginItemsSettings()
        interactor.setHotkeysEnabled(true)
        await interactor.resetAll()

        #expect(firstState(of: interactor) == [settings])
    }
}
