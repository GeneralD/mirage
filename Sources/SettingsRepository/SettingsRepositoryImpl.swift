import Dependencies
import Domain

/// The chosen effect, the disabled-effect records and the global hotkeys flag as the UseCases see
/// them, over `PreferencesDataStore` (epic #42, D6): a pass-through, which keeps the UseCase →
/// Repository → DataStore chain adjacent as `ExtensionInstallRepositoryImpl` does for the
/// installer. The records go through unsorted and undeduplicated: what the UseCase hands over is
/// what is stored. The schema version and the reset go to `StoreMaintenance` unchanged, so the
/// flag and the version never share a store. Caching or policy would belong here, and these
/// settings need neither. The readers are the effect catalog and `SettingsUseCase`, which serves
/// the settings window and the global hotkeys.
///
/// The system integrations go the same way (hackathon #183): the launch-at-login status and its
/// toggle to `LoginItem`, and the global hotkeys registration, presses and release to `Hotkeys`,
/// each call forwarded once and its answer returned as it came.
public struct SettingsRepositoryImpl: Sendable {
    @Dependency(\.preferences) private var preferences
    @Dependency(\.storeMaintenance) private var storeMaintenance
    @Dependency(\.loginItem) private var loginItem
    @Dependency(\.hotkeys) private var hotkeys

    public init() {}
}

extension SettingsRepositoryImpl: SettingsRepository {
    public func selectedEffect() async -> EffectID? {
        await preferences.selectedEffect()
    }

    public func setSelectedEffect(_ id: EffectID) async {
        await preferences.setSelectedEffect(id)
    }

    public func disabledEffects() async -> [DisabledEffectRecord] {
        await preferences.disabledEffects()
    }

    public func setDisabledEffects(_ records: [DisabledEffectRecord]) async {
        await preferences.setDisabledEffects(records)
    }

    public func hotkeysEnabled() async -> Bool {
        await preferences.hotkeysEnabled()
    }

    public func setHotkeysEnabled(_ on: Bool) async {
        await preferences.setHotkeysEnabled(on)
    }

    public func storedSchemaVersion() async -> StoredSchemaVersion {
        await storeMaintenance.schemaVersion()
    }

    public func stampSchemaVersion(_ version: Int) async {
        await storeMaintenance.stampSchemaVersion(version)
    }

    public func resetAll() async {
        await storeMaintenance.resetAll()
    }

    public var launchAtLoginStatus: LaunchAtLoginStatus {
        loginItem.status
    }

    public func setLaunchAtLogin(_ on: Bool) -> LaunchAtLoginStatus {
        loginItem.setEnabled(on)
    }

    public func openLoginItemsSettings() {
        loginItem.openSystemSettings()
    }

    public func registerHotkeys(_ bindings: [HotkeyBinding]) async -> HotkeyRegistration {
        await hotkeys.register(bindings)
    }

    public func unregisterHotkeys() async {
        await hotkeys.unregisterAll()
    }

    public var hotkeyRegistration: HotkeyRegistration {
        get async {
            await hotkeys.registration
        }
    }

    public func hotkeyPresses() async -> AsyncStream<HotkeyAction> {
        await hotkeys.presses()
    }
}
