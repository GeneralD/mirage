import Combine
import Domain

/// The `SettingsInteractor` the settings screens draw from: it publishes the one settings state it was made with, to every
/// subscriber, and its commands do nothing. A screen shows a state; it does not move it. It is not a test double (`Sources` may
/// not use `TestDoubles`), and no shipped product links this module.
struct GallerySettingsInteractor {
    let settings: SettingsState
}

extension GallerySettingsInteractor: SettingsInteractor {
    var state: AnyPublisher<SettingsState, Never> {
        Just(settings).eraseToAnyPublisher()
    }

    func refresh() {}

    func setLaunchAtLogin(_ on: Bool) {}

    func openLoginItemsSettings() {}

    func setHotkeysEnabled(_ on: Bool) {}

    func resetAll() async {}
}
