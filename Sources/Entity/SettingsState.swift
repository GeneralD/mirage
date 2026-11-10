/// Whether the app launches at login, as the system reports it.
public enum LaunchAtLoginStatus: Sendable, Hashable, CaseIterable {
    case off
    case on
    /// The user has to approve the login item in System Settings before it takes effect.
    case needsApproval
    /// Launch at login cannot be registered for this way the app was started.
    case unavailable
}

/// What a stored settings value says about the schema version it was written with.
public enum StoredSchemaVersion: Sendable, Hashable {
    /// Nothing has ever been stored.
    case missing
    case version(Int)
    /// A value is stored, but it cannot be read.
    case unreadable
}

/// The state the settings window shows.
public struct SettingsState: Sendable, Hashable {
    public let launchAtLogin: LaunchAtLoginStatus
    public let hotkeysEnabled: Bool
    public let hotkeys: HotkeyStatus

    public init(launchAtLogin: LaunchAtLoginStatus = .off, hotkeysEnabled: Bool = true, hotkeys: HotkeyStatus = .off) {
        self.launchAtLogin = launchAtLogin
        self.hotkeysEnabled = hotkeysEnabled
        self.hotkeys = hotkeys
    }
}

/// One line of the settings window's hotkey list. `keys` is the display string, already composed
/// for showing; composing it is the Presenter's job.
public struct SettingsHotkeyRow: Sendable, Hashable, Identifiable {
    public let id: HotkeyAction
    public let title: String
    public let keys: String

    public init(id: HotkeyAction, title: String, keys: String) {
        self.id = id
        self.title = title
        self.keys = keys
    }
}
