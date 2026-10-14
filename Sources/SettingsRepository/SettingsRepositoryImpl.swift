import Dependencies
import Domain

/// The chosen effect as the UseCases see it, over `PreferencesDataStore` (epic #42, D6): a
/// pass-through, which keeps the UseCase → Repository → DataStore chain adjacent as
/// `ExtensionInstallRepositoryImpl` does for the installer. Caching or policy would belong
/// here, and one setting needs neither. There is no `SettingsUseCase`: no settings UI exists
/// yet, and the only reader is the effect catalog.
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
}
