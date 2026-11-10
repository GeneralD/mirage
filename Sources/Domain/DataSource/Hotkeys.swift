import Dependencies

/// `HotkeyDataSource`: the global hotkeys the app has registered (hackathon #177). It asks
/// `HotkeyGateway` for each binding, keeps what the OS accepted in `registration`, and reports
/// the presses of the registered hotkeys as the `HotkeyAction` they were bound to.
public protocol Hotkeys: Sendable {
    /// The presses of the registered hotkeys, from now until the next `presses()` call.
    ///
    /// - Each call returns a new stream and ends the one returned before it, so one subscriber
    ///   is served at a time.
    /// - A press with no stream open is dropped.
    @MainActor func presses() -> AsyncStream<HotkeyAction>

    /// Registers `bindings` in place of the previous registration and returns what the OS accepted.
    ///
    /// - The hotkeys of the previous call are released first.
    /// - The press observer is installed by the first call, and kept for the life of the process.
    /// - A binding the OS refuses is reported in `failed`, and the others still register.
    @MainActor func register(_ bindings: [HotkeyBinding]) -> HotkeyRegistration

    /// Releases every hotkey and sets `registration` back to `.empty`. The press observer stays.
    @MainActor func unregisterAll()

    /// What the last `register` returned, and `.empty` after `unregisterAll()` or before any `register`.
    @MainActor var registration: HotkeyRegistration { get }
}

public enum HotkeysKey: TestDependencyKey {
    public static let testValue: any Hotkeys = UnimplementedHotkeys()
}

extension DependencyValues {
    public var hotkeys: any Hotkeys {
        get { self[HotkeysKey.self] }
        set { self[HotkeysKey.self] = newValue }
    }
}

private struct UnimplementedHotkeys: Hotkeys {
    @MainActor
    func presses() -> AsyncStream<HotkeyAction> {
        reportIssue("Hotkeys.presses not implemented")
        return AsyncStream { $0.finish() }
    }

    @MainActor
    func register(_ bindings: [HotkeyBinding]) -> HotkeyRegistration {
        reportIssue("Hotkeys.register not implemented")
        return .empty
    }

    @MainActor
    func unregisterAll() {
        reportIssue("Hotkeys.unregisterAll not implemented")
    }

    @MainActor
    var registration: HotkeyRegistration { .empty }
}
