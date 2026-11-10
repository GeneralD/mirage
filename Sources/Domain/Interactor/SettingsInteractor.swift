import Combine
import Dependencies

/// The settings window's interactor (epic E6, menu and settings): it turns the settings UseCase
/// into a publisher the Presenter subscribes to, and carries the window's commands to the UseCase.
/// The window reads `state`; its controls call the commands below.
public protocol SettingsInteractor: Sendable {
    /// The current settings first, then after every change. It holds a value from construction on
    /// (`SettingsState()` until the first `refresh()`).
    var state: AnyPublisher<SettingsState, Never> { get }

    /// Reads the settings now and publishes them; the window calls it each time it opens. Returns at once.
    func refresh()

    /// Turns launch at login on or off. The commands are carried out one at a time, in call order.
    func setLaunchAtLogin(_ on: Bool)

    /// Opens the system's Login Items settings, where a pending approval is given.
    func openLoginItemsSettings()

    /// Turns the global hotkeys on or off. The commands are carried out one at a time, in call order.
    func setHotkeysEnabled(_ on: Bool)

    /// Puts every setting back to its default. Returns once the reset is done and the new settings are published.
    func resetAll() async
}

public enum SettingsInteractorKey: TestDependencyKey {
    public static let testValue: any SettingsInteractor = UnimplementedSettingsInteractor()
}

extension DependencyValues {
    public var settingsInteractor: any SettingsInteractor {
        get { self[SettingsInteractorKey.self] }
        set { self[SettingsInteractorKey.self] = newValue }
    }
}

private struct UnimplementedSettingsInteractor: SettingsInteractor {
    var state: AnyPublisher<SettingsState, Never> {
        reportIssue("SettingsInteractor.state not implemented")
        return Empty(completeImmediately: true).eraseToAnyPublisher()
    }

    func refresh() {
        reportIssue("SettingsInteractor.refresh not implemented")
    }

    func setLaunchAtLogin(_ on: Bool) {
        reportIssue("SettingsInteractor.setLaunchAtLogin not implemented")
    }

    func openLoginItemsSettings() {
        reportIssue("SettingsInteractor.openLoginItemsSettings not implemented")
    }

    func setHotkeysEnabled(_ on: Bool) {
        reportIssue("SettingsInteractor.setHotkeysEnabled not implemented")
    }

    func resetAll() async {
        reportIssue("SettingsInteractor.resetAll not implemented")
    }
}
