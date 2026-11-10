import Dependencies
import Domain

/// Stamps the store's schema version on the first launch and leaves a version it does not own
/// alone; the reset clears every stored value and stamps the current version again.
public struct SettingsUseCaseImpl: Sendable {
    @Dependency(\.settingsRepository) private var settingsRepository
    @Dependency(\.developerLog) private var developerLog

    public init() {}
}

extension SettingsUseCaseImpl: SettingsUseCase {
    public func prepareStore() async {
        let stored = await settingsRepository.storedSchemaVersion()
        switch storeSchemaStep(for: stored, current: currentStoreSchemaVersion) {
        case .stamp:
            await settingsRepository.stampSchemaVersion(currentStoreSchemaVersion)
            developerLog.record(.app, "store schema stamped: v\(currentStoreSchemaVersion)")
        case .leaveAlone:
            logLeftAlone(stored)
        }
    }

    public func resetAll() async {
        await settingsRepository.resetAll()
        await settingsRepository.stampSchemaVersion(currentStoreSchemaVersion)
        developerLog.record(.app, "settings reset")
    }
}

extension SettingsUseCaseImpl {
    /// Only a version from a newer build and an unreadable value are worth a line; a version that
    /// matches this build is quiet.
    private func logLeftAlone(_ stored: StoredSchemaVersion) {
        switch stored {
        case .version(let version) where version > currentStoreSchemaVersion:
            developerLog.record(
                .app, "store schema v\(version) is newer than this build (v\(currentStoreSchemaVersion)), left as it is")
        case .unreadable:
            developerLog.record(.app, "store schema is unreadable, left as it is")
        case .missing, .version:
            break
        }
    }
}
