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
///
/// The hotkeys answer what `script(settings:)` and `script(hotkeyStatus:)` set, from then on. Until
/// then `settings()` answers `SettingsState(launchAtLogin:)` with the current status, and
/// `applyHotkeys()` and `setHotkeysEnabled(_:)` answer `.off`. `applications` records every
/// `applyHotkeys()` and `hotkeyFlagRequests` every `setHotkeysEnabled(_:)`; `streamRequests` records
/// every `hotkeyPresses()`. The methods each take their name into `calls`. `press(_:)` delivers an
/// action to the stream `hotkeyPresses()` returned last, and a press with no stream open is dropped.
public final class FakeSettingsUseCase: SettingsUseCase, Sendable {
    /// What the fake remembers and what the hotkey answers are read from.
    private struct State {
        var launchAtLogin: LaunchAtLoginStatus
        var settings: SettingsState?
        var hotkeyStatus: HotkeyStatus = .off
        var pressContinuation: AsyncStream<HotkeyAction>.Continuation?
    }

    public let prepares = Collector<Void>()
    public let resets = Collector<Void>()
    public let calls = Collector<String>()
    /// The values `setLaunchAtLogin` was called with, in call order, including a call that changed nothing.
    public let launchRequests = Collector<Bool>()
    /// One entry per `openLoginItemsSettings()` call, in call order.
    public let settingsOpens = Collector<Void>()
    /// One entry per `applyHotkeys()` call, in call order.
    public let applications = Collector<Void>()
    /// The values `setHotkeysEnabled` was called with, in call order.
    public let hotkeyFlagRequests = Collector<Bool>()
    /// One entry per `hotkeyPresses()` call, in call order.
    public let streamRequests = Collector<Void>()
    private let state: Locked<State>

    public init(launchAtLogin: LaunchAtLoginStatus = .off) {
        state = Locked(State(launchAtLogin: launchAtLogin))
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
        state.current.launchAtLogin
    }

    public func setLaunchAtLogin(_ on: Bool) -> LaunchAtLoginStatus {
        launchRequests.append(on)
        calls.append("setLaunchAtLogin")
        return state.withLock { state in
            guard state.launchAtLogin != .unavailable else { return state.launchAtLogin }
            state.launchAtLogin = on ? .on : .off
            return state.launchAtLogin
        }
    }

    public func openLoginItemsSettings() {
        settingsOpens.append(())
        calls.append("openLoginItemsSettings")
    }

    public func settings() async -> SettingsState {
        calls.append("settings")
        return state.current.settings ?? SettingsState(launchAtLogin: state.current.launchAtLogin)
    }

    public func applyHotkeys() async -> HotkeyStatus {
        applications.append(())
        calls.append("applyHotkeys")
        return state.current.hotkeyStatus
    }

    public func setHotkeysEnabled(_ on: Bool) async -> HotkeyStatus {
        hotkeyFlagRequests.append(on)
        calls.append("setHotkeysEnabled")
        return state.current.hotkeyStatus
    }

    public func hotkeyPresses() async -> AsyncStream<HotkeyAction> {
        streamRequests.append(())
        calls.append("hotkeyPresses")
        let (stream, next) = AsyncStream<HotkeyAction>.makeStream()
        state.withLock { state in
            state.pressContinuation?.finish()
            state.pressContinuation = next
        }
        return stream
    }

    /// Sets the status directly, as when the user approves or removes the item in System Settings.
    public func set(launchAtLogin status: LaunchAtLoginStatus) {
        state.withLock { $0.launchAtLogin = status }
    }

    /// Makes `settings()` answer `settings` from now on.
    public func script(settings: SettingsState) {
        state.withLock { $0.settings = settings }
    }

    /// Makes `applyHotkeys()` and `setHotkeysEnabled(_:)` answer `status` from now on.
    public func script(hotkeyStatus status: HotkeyStatus) {
        state.withLock { $0.hotkeyStatus = status }
    }

    /// Delivers `action` to the stream `hotkeyPresses()` returned last. Nothing happens when no stream is open.
    public func press(_ action: HotkeyAction) {
        state.withLock { $0.pressContinuation }?.yield(action)
    }
}
