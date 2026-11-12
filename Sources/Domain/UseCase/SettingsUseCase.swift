import Dependencies

/// Settings policy for the settings window and the launch: the stored schema version is
/// stamped on the first launch, a reset removes every stored value and stamps it again, and the
/// launch-at-login item and the global hotkeys are part of what the settings window reads and changes.
public protocol SettingsUseCase: Sendable {
    /// Called at launch. Stamps the current schema version when nothing is stored yet. A version
    /// a newer build wrote, and a value that cannot be read, are left where they are.
    func prepareStore() async

    /// Removes every stored value, then stamps the current schema version, then turns the
    /// launch-at-login item off, then applies the hotkeys: the defaults a reset returns to.
    func resetAll() async

    /// The launch-at-login status as the system reports it now.
    var launchAtLoginStatus: LaunchAtLoginStatus { get }

    /// Turns the launch-at-login item on or off and returns the status read back after the attempt.
    /// Never throws: a request that did not take effect is logged, and the returned status says
    /// what is actually in place.
    func setLaunchAtLogin(_ on: Bool) -> LaunchAtLoginStatus

    /// Opens the Login Items pane of System Settings.
    func openLoginItemsSettings()

    /// The state the settings window shows: the launch-at-login status, the stored hotkeys flag, and
    /// the hotkeys status. Reads only; it registers and releases nothing.
    func settings() async -> SettingsState

    /// Registers the default bindings when the stored flag is on, releases them when it is off, and
    /// returns the status. A binding the system refused is logged as one developer line.
    func applyHotkeys() async -> HotkeyStatus

    /// Stores the hotkeys flag, then applies it, and returns the status.
    func setHotkeysEnabled(_ on: Bool) async -> HotkeyStatus

    /// The presses of the registered hotkeys, as the repository reports them.
    func hotkeyPresses() async -> AsyncStream<HotkeyAction>
}

public enum SettingsUseCaseKey: TestDependencyKey {
    public static let testValue: any SettingsUseCase = UnimplementedSettingsUseCase()
}

extension DependencyValues {
    public var settingsUseCase: any SettingsUseCase {
        get { self[SettingsUseCaseKey.self] }
        set { self[SettingsUseCaseKey.self] = newValue }
    }
}

private struct UnimplementedSettingsUseCase: SettingsUseCase {
    func prepareStore() async {
        reportIssue("SettingsUseCase.prepareStore not implemented")
    }

    func resetAll() async {
        reportIssue("SettingsUseCase.resetAll not implemented")
    }

    var launchAtLoginStatus: LaunchAtLoginStatus {
        reportIssue("SettingsUseCase.launchAtLoginStatus not implemented")
        return .unavailable
    }

    func setLaunchAtLogin(_ on: Bool) -> LaunchAtLoginStatus {
        reportIssue("SettingsUseCase.setLaunchAtLogin not implemented")
        return .unavailable
    }

    func openLoginItemsSettings() {
        reportIssue("SettingsUseCase.openLoginItemsSettings not implemented")
    }

    func settings() async -> SettingsState {
        reportIssue("SettingsUseCase.settings not implemented")
        return SettingsState()
    }

    func applyHotkeys() async -> HotkeyStatus {
        reportIssue("SettingsUseCase.applyHotkeys not implemented")
        return .off
    }

    func setHotkeysEnabled(_ on: Bool) async -> HotkeyStatus {
        reportIssue("SettingsUseCase.setHotkeysEnabled not implemented")
        return .off
    }

    func hotkeyPresses() async -> AsyncStream<HotkeyAction> {
        reportIssue("SettingsUseCase.hotkeyPresses not implemented")
        return AsyncStream { $0.finish() }
    }
}
