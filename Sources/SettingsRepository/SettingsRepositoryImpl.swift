import Dependencies
import Domain

/// The chosen effect and the disabled-effect records as the UseCases see them, over
/// `PreferencesDataStore` (epic #42, D6): a pass-through, which keeps the UseCase → Repository
/// → DataStore chain adjacent as `ExtensionInstallRepositoryImpl` does for the installer. The
/// records go through unsorted and undeduplicated: what the UseCase hands over is what is
/// stored. Caching or policy would belong here, and these settings need neither. There is no
/// `SettingsUseCase`: no settings UI exists yet, and the only reader is the effect catalog.
public struct SettingsRepositoryImpl: Sendable {
    @Dependency(\.preferences) private var preferences

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
}
