import Dependencies
import Domain

/// Stamps the store's schema version on the first launch and leaves a version it does not own
/// alone; the reset clears every stored value, stamps the current version again, turns the
/// launch-at-login item off, and applies the hotkeys from their default.
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
        _ = setLaunchAtLogin(false)
        _ = await applyHotkeys()
        developerLog.record(.app, "settings reset")
    }

    public var launchAtLoginStatus: LaunchAtLoginStatus {
        settingsRepository.launchAtLoginStatus
    }

    /// A request that does not come back as the status it asked for is logged as missed, with the
    /// status that is actually in place, so a refusal or an approval still pending shows in the log.
    public func setLaunchAtLogin(_ on: Bool) -> LaunchAtLoginStatus {
        let status = settingsRepository.setLaunchAtLogin(on)
        let wanted: LaunchAtLoginStatus = on ? .on : .off
        if status == wanted {
            developerLog.record(.app, "launch at login now \(status)")
        } else {
            let requested = on ? "on" : "off"
            developerLog.record(.app, "launch at login requested \(requested), now \(status)")
        }
        return status
    }

    public func openLoginItemsSettings() {
        settingsRepository.openLoginItemsSettings()
    }

    public func settings() async -> SettingsState {
        let enabled = await settingsRepository.hotkeysEnabled()
        let registration = await settingsRepository.hotkeyRegistration
        return SettingsState(
            launchAtLogin: settingsRepository.launchAtLoginStatus,
            hotkeysEnabled: enabled,
            hotkeys: hotkeyStatus(enabled: enabled, registration: registration)
        )
    }

    public func applyHotkeys() async -> HotkeyStatus {
        let enabled = await settingsRepository.hotkeysEnabled()
        let registration = await applyHotkeyRegistration(enabled: enabled)
        let status = hotkeyStatus(enabled: enabled, registration: registration)
        if case .conflicted(let failed) = status {
            let actions = failed.map { String(describing: $0) }.joined(separator: ", ")
            developerLog.record(.app, "hotkeys not available: \(actions)")
        }
        return status
    }

    public func setHotkeysEnabled(_ on: Bool) async -> HotkeyStatus {
        await settingsRepository.setHotkeysEnabled(on)
        return await applyHotkeys()
    }

    public func hotkeyPresses() async -> AsyncStream<HotkeyAction> {
        await settingsRepository.hotkeyPresses()
    }
}

extension SettingsUseCaseImpl {
    /// Registers the default bindings when the flag is on; when it is off, releases them and answers
    /// the empty registration, which is what remains after a release.
    private func applyHotkeyRegistration(enabled: Bool) async -> HotkeyRegistration {
        guard enabled else {
            await settingsRepository.unregisterHotkeys()
            return .empty
        }
        return await settingsRepository.registerHotkeys(defaultHotkeyBindings)
    }

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
