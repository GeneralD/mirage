import Dependencies
import Domain

/// Maps the gateway's raw `SMAppService.Status` onto `LaunchAtLoginStatus`, and
/// decides whether `register` or `unregister` is called at all: a call is made
/// only when it would change the status, so a repeated toggle never reaches the
/// system. A throw from the gateway is logged once and never leaves this type;
/// the status is read back afterwards, so the caller sees what is in place.
public struct LoginItemDataSourceImpl: Sendable {
    @Dependency(\.loginItemGateway) private var loginItemGateway
    @Dependency(\.errorLog) private var errorLog

    public init() {}
}

extension LoginItemDataSourceImpl: LoginItem {
    public var status: LaunchAtLoginStatus {
        Self.launchAtLoginStatus(rawValue: loginItemGateway.rawStatus())
    }

    public func setEnabled(_ on: Bool) -> LaunchAtLoginStatus {
        do {
            switch (on, status) {
            case (true, .off):
                try loginItemGateway.register()
            case (false, .on), (false, .needsApproval):
                try loginItemGateway.unregister()
            default:
                break
            }
        } catch {
            errorLog.record(.app, "launch at login: \(error)")
        }
        return status
    }

    public func openSystemSettings() {
        loginItemGateway.openSystemSettings()
    }
}

extension LoginItemDataSourceImpl {
    /// The raw values of `SMAppService.Status`: 0 notRegistered, 1 enabled,
    /// 2 requiresApproval, 3 notFound. Anything else is not a status the app
    /// can act on, so it reads as unavailable.
    static func launchAtLoginStatus(rawValue: Int) -> LaunchAtLoginStatus {
        switch rawValue {
        case 0: return .off
        case 1: return .on
        case 2: return .needsApproval
        default: return .unavailable
        }
    }
}
