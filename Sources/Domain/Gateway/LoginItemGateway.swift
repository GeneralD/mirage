import Dependencies

/// Thin pass-through to the login item of this app (live: `SMAppService.mainApp`).
///
/// `rawStatus()` is the raw value of `SMAppService.Status`: 0 notRegistered, 1 enabled,
/// 2 requiresApproval, 3 notFound. Turning it into a value the app reasons about is
/// `LoginItemDataSource`'s job. `register()` and `unregister()` throw what the system
/// throws, unmapped; whether to call them at all is decided above the gateway.
public protocol LoginItemGateway: Sendable {
    func rawStatus() -> Int
    func register() throws
    func unregister() throws
    /// Opens the Login Items pane of System Settings.
    func openSystemSettings()
}

public enum LoginItemGatewayKey: TestDependencyKey {
    public static let testValue: any LoginItemGateway = UnimplementedLoginItemGateway()
}

extension DependencyValues {
    public var loginItemGateway: any LoginItemGateway {
        get { self[LoginItemGatewayKey.self] }
        set { self[LoginItemGatewayKey.self] = newValue }
    }
}

private struct UnimplementedLoginItemGateway: LoginItemGateway {
    func rawStatus() -> Int {
        reportIssue("LoginItemGateway.rawStatus not implemented")
        return 3
    }

    func register() throws {
        reportIssue("LoginItemGateway.register not implemented")
    }

    func unregister() throws {
        reportIssue("LoginItemGateway.unregister not implemented")
    }

    func openSystemSettings() {
        reportIssue("LoginItemGateway.openSystemSettings not implemented")
    }
}
