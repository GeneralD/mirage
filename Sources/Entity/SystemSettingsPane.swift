/// The System Settings panes the Camera Extension approval can be sent to. Which one to
/// open first is decided above the DataSource, since the approval pane differs by macOS version.
public enum SystemSettingsPane: Sendable, Hashable, CaseIterable {
    case loginItemsAndExtensions
    case privacyAndSecurity
}
