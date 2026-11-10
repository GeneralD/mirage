import Domain
import TestSupport

/// `SettingsUseCase` answering at once. `prepares` and `resets` count the calls to `prepareStore()`
/// and `resetAll()`, and `calls` takes the bare method name of each, in call order, so a sequence
/// that shares it with other fakes can be checked for order.
///
/// The launch-at-login status starts at `launchAtLogin` and moves the way `SettingsUseCaseImpl`
/// does for a request: `setLaunchAtLogin` answers `on ? .on : .off` and leaves `.unavailable` alone.
/// `launchRequests` records every `setLaunchAtLogin` and `settingsOpens` every
/// `openLoginItemsSettings`; both methods also take their name into `calls`. `set(launchAtLogin:)`
/// changes the status from outside, as when the user approves the item in System Settings.
public final class FakeSettingsUseCase: SettingsUseCase, Sendable {
    public let prepares = Collector<Void>()
    public let resets = Collector<Void>()
    public let calls = Collector<String>()
    /// The values `setLaunchAtLogin` was called with, in call order, including a call that changed nothing.
    public let launchRequests = Collector<Bool>()
    /// One entry per `openLoginItemsSettings()` call, in call order.
    public let settingsOpens = Collector<Void>()
    private let state: Locked<LaunchAtLoginStatus>

    public init(launchAtLogin: LaunchAtLoginStatus = .off) {
        state = Locked(launchAtLogin)
    }

    public func prepareStore() async {
        prepares.append(())
        calls.append("prepareStore")
    }

    public func resetAll() async {
        resets.append(())
        calls.append("resetAll")
    }

    public var launchAtLoginStatus: LaunchAtLoginStatus {
        state.current
    }

    public func setLaunchAtLogin(_ on: Bool) -> LaunchAtLoginStatus {
        launchRequests.append(on)
        calls.append("setLaunchAtLogin")
        return state.withLock { current in
            guard current != .unavailable else { return current }
            current = on ? .on : .off
            return current
        }
    }

    public func openLoginItemsSettings() {
        settingsOpens.append(())
        calls.append("openLoginItemsSettings")
    }

    /// Sets the status directly, as when the user approves or removes the item in System Settings.
    public func set(launchAtLogin status: LaunchAtLoginStatus) {
        state.set(status)
    }
}
