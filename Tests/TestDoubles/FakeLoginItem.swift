import Domain
import TestSupport

/// `LoginItem` that registers nothing. It holds a `LaunchAtLoginStatus` and moves it the way
/// `LoginItemDataSourceImpl` does for the same request: `setEnabled(true)` turns `.off` into `.on`,
/// `setEnabled(false)` turns `.on` and `.needsApproval` into `.off`, and `.unavailable` never moves.
///
/// `requests` records every `setEnabled` call in order, including one that changes nothing, so a
/// test can tell a request that was made from one that was not. `settingsOpens` records every
/// `openSystemSettings` call. `set(status:)` changes the status from outside, as when the user
/// approves or removes the item in System Settings.
public final class FakeLoginItem: LoginItem, Sendable {
    private let state: Locked<LaunchAtLoginStatus>
    /// One entry per `setEnabled` call, in call order.
    public let requests = Collector<Bool>()
    /// One entry per `openSystemSettings` call, in call order.
    public let settingsOpens = Collector<Void>()

    public init(status: LaunchAtLoginStatus = .off) {
        state = Locked(status)
    }

    public var status: LaunchAtLoginStatus {
        state.current
    }

    public func setEnabled(_ on: Bool) -> LaunchAtLoginStatus {
        requests.append(on)
        return state.withLock { current in
            switch (on, current) {
            case (true, .off):
                current = .on
            case (false, .on), (false, .needsApproval):
                current = .off
            default:
                break
            }
            return current
        }
    }

    public func openSystemSettings() {
        settingsOpens.append(())
    }

    /// Sets the status directly, as when the user approves or removes the item in System Settings.
    public func set(status: LaunchAtLoginStatus) {
        state.set(status)
    }
}
