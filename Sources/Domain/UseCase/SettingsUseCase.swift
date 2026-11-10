import Dependencies

/// Settings policy for the settings window and the launch: the stored schema version is
/// stamped on the first launch, and a reset removes every stored value and stamps it again.
public protocol SettingsUseCase: Sendable {
    /// Called at launch. Stamps the current schema version when nothing is stored yet. A version
    /// a newer build wrote, and a value that cannot be read, are left where they are.
    func prepareStore() async

    /// Removes every stored value, then stamps the current schema version.
    func resetAll() async
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
}
