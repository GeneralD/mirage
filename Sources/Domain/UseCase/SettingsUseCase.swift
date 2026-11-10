import Dependencies

/// Settings policy for the settings window and the launch: the stored schema version is
/// stamped on the first launch, a reset removes every stored value and stamps it again, and the
/// launch-at-login item is part of what the settings window reads and changes.
public protocol SettingsUseCase: Sendable {
    /// Called at launch. Stamps the current schema version when nothing is stored yet. A version
    /// a newer build wrote, and a value that cannot be read, are left where they are.
    func prepareStore() async

    /// Removes every stored value, then stamps the current schema version, then turns the
    /// launch-at-login item off, the default a reset returns to.
    func resetAll() async

    /// The launch-at-login status as the system reports it now.
    var launchAtLoginStatus: LaunchAtLoginStatus { get }

    /// Turns the launch-at-login item on or off and returns the status read back after the attempt.
    /// Never throws: a request that did not take effect is logged, and the returned status says
    /// what is actually in place.
    func setLaunchAtLogin(_ on: Bool) -> LaunchAtLoginStatus

    /// Opens the Login Items pane of System Settings.
    func openLoginItemsSettings()
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
}
