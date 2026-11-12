import Dependencies

/// `LoginItemDataSource`: whether the app launches at login, as the system
/// reports it, and the one toggle the settings window drives. The raw gateway
/// status becomes a `LaunchAtLoginStatus` here, and the gateway is called only
/// when a call would change the status.
public protocol LoginItem: Sendable {
    /// The status as the system reports it now.
    var status: LaunchAtLoginStatus { get }
    /// Turns the login item on or off, and returns the status read back after
    /// the attempt. Never throws: a failure is logged and the status says what
    /// is actually in place.
    func setEnabled(_ on: Bool) -> LaunchAtLoginStatus
    /// Opens the Login Items pane of System Settings.
    func openSystemSettings()
}

public enum LoginItemKey: TestDependencyKey {
    public static let testValue: any LoginItem = UnimplementedLoginItem()
}

extension DependencyValues {
    public var loginItem: any LoginItem {
        get { self[LoginItemKey.self] }
        set { self[LoginItemKey.self] = newValue }
    }
}

private struct UnimplementedLoginItem: LoginItem {
    var status: LaunchAtLoginStatus {
        reportIssue("LoginItem.status not implemented")
        return .unavailable
    }

    func setEnabled(_ on: Bool) -> LaunchAtLoginStatus {
        reportIssue("LoginItem.setEnabled not implemented")
        return .unavailable
    }

    func openSystemSettings() {
        reportIssue("LoginItem.openSystemSettings not implemented")
    }
}
