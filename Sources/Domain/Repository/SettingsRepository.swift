import Dependencies

/// `SettingsRepository`: the user's settings as the UseCases see them, over `PreferencesDataStore`
/// and `StoreMaintenance`. The chosen effect, which survives a relaunch (epic #42, D6): a
/// relaunch selects it again if the catalog still has it. And the records of disabled
/// effects, which survive a relaunch too, so that a crash loop cannot repeat. The global hotkeys
/// flag, which survives a relaunch as well. The stored schema version and the reset that removes
/// every stored value are passed through to `StoreMaintenance` unchanged.
public protocol SettingsRepository: Sendable {
    func selectedEffect() async -> EffectID?
    func setSelectedEffect(_ id: EffectID) async
    func disabledEffects() async -> [DisabledEffectRecord]
    func setDisabledEffects(_ records: [DisabledEffectRecord]) async
    func hotkeysEnabled() async -> Bool
    func setHotkeysEnabled(_ on: Bool) async
    func storedSchemaVersion() async -> StoredSchemaVersion
    func stampSchemaVersion(_ version: Int) async
    func resetAll() async
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

    func disabledEffects() async -> [DisabledEffectRecord] {
        reportIssue("SettingsRepository.disabledEffects not implemented")
        return []
    }

    func setDisabledEffects(_ records: [DisabledEffectRecord]) async {
        reportIssue("SettingsRepository.setDisabledEffects not implemented")
    }

    func hotkeysEnabled() async -> Bool {
        reportIssue("SettingsRepository.hotkeysEnabled not implemented")
        return true
    }

    func setHotkeysEnabled(_ on: Bool) async {
        reportIssue("SettingsRepository.setHotkeysEnabled not implemented")
    }

    func storedSchemaVersion() async -> StoredSchemaVersion {
        reportIssue("SettingsRepository.storedSchemaVersion not implemented")
        return .unreadable
    }

    func stampSchemaVersion(_ version: Int) async {
        reportIssue("SettingsRepository.stampSchemaVersion not implemented")
    }

    func resetAll() async {
        reportIssue("SettingsRepository.resetAll not implemented")
    }
}
