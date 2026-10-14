import Dependencies

/// `SettingsRepository`: the user's settings as the UseCases see them, over
/// `PreferencesDataStore`. For now only the chosen effect, which survives a relaunch
/// (epic #42, D6): a relaunch selects it again if the catalog still has it.
public protocol SettingsRepository: Sendable {
    func selectedEffect() async -> EffectID?
    func setSelectedEffect(_ id: EffectID) async
}

public enum SettingsRepositoryKey: TestDependencyKey {
    public static let testValue: any SettingsRepository = UnimplementedSettingsRepository()
}

extension DependencyValues {
    public var settingsRepository: any SettingsRepository {
        get { self[SettingsRepositoryKey.self] }
        set { self[SettingsRepositoryKey.self] = newValue }
    }
}

private struct UnimplementedSettingsRepository: SettingsRepository {
    func selectedEffect() async -> EffectID? {
        reportIssue("SettingsRepository.selectedEffect not implemented")
        return nil
    }

    func setSelectedEffect(_ id: EffectID) async {
        reportIssue("SettingsRepository.setSelectedEffect not implemented")
    }
}
