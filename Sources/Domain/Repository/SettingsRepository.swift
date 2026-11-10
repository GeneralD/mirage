import Dependencies

/// `SettingsRepository`: the user's settings as the UseCases see them, over `PreferencesDataStore`,
/// `StoreMaintenance`, `LoginItem` and `Hotkeys`. The chosen effect, which survives a relaunch (epic #42, D6): a
/// relaunch selects it again if the catalog still has it. And the records of disabled
/// effects, which survive a relaunch too, so that a crash loop cannot repeat. The global hotkeys
/// flag, which survives a relaunch as well. The stored schema version and the reset that removes
/// every stored value are passed through to `StoreMaintenance` unchanged.
///
/// The system integrations are passed through unchanged as well: the launch-at-login status and its
/// toggle go to `LoginItem`, and the global hotkeys registration, the presses and the release go to
/// `Hotkeys`. The hotkey members are `async` because `Hotkeys` is main-actor isolated, so the hop
/// belongs to the caller's `await`.
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
    var launchAtLoginStatus: LaunchAtLoginStatus { get }
    func setLaunchAtLogin(_ on: Bool) -> LaunchAtLoginStatus
    func openLoginItemsSettings()
    func registerHotkeys(_ bindings: [HotkeyBinding]) async -> HotkeyRegistration
    func unregisterHotkeys() async
    var hotkeyRegistration: HotkeyRegistration { get async }
    func hotkeyPresses() async -> AsyncStream<HotkeyAction>
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

    var launchAtLoginStatus: LaunchAtLoginStatus {
        reportIssue("SettingsRepository.launchAtLoginStatus not implemented")
        return .unavailable
    }

    func setLaunchAtLogin(_ on: Bool) -> LaunchAtLoginStatus {
        reportIssue("SettingsRepository.setLaunchAtLogin not implemented")
        return .unavailable
    }

    func openLoginItemsSettings() {
        reportIssue("SettingsRepository.openLoginItemsSettings not implemented")
    }

    func registerHotkeys(_ bindings: [HotkeyBinding]) async -> HotkeyRegistration {
        reportIssue("SettingsRepository.registerHotkeys not implemented")
        return .empty
    }

    func unregisterHotkeys() async {
        reportIssue("SettingsRepository.unregisterHotkeys not implemented")
    }

    var hotkeyRegistration: HotkeyRegistration {
        get async {
            reportIssue("SettingsRepository.hotkeyRegistration not implemented")
            return .empty
        }
    }

    func hotkeyPresses() async -> AsyncStream<HotkeyAction> {
        reportIssue("SettingsRepository.hotkeyPresses not implemented")
        return AsyncStream { $0.finish() }
    }
}
