import Dependencies

/// Thin pass-through to the OS's global hotkeys (live: Carbon's `InstallEventHandler` and
/// `RegisterEventHotKey`, on the application event target). Both calls run on the main thread,
/// which is why each requirement is `@MainActor`. The gateway reports the OS status and the
/// presses and decides nothing: the registry, the conflicts and the id-to-action mapping are
/// `HotkeyDataSource`'s.
public protocol HotkeyGateway: Sendable {
    /// Receives the id of every hotkey the OS reports pressed, until the returned handle is released.
    @MainActor func observePresses(_ onPress: @escaping @Sendable (UInt32) -> Void) -> any HotkeyHandle

    /// Asks the OS for a global hotkey of `keyCode` with `modifiers`, reported under `id`. A refused
    /// registration still returns a handle, with a non-zero status, and is released like any other.
    @MainActor func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> any HotkeyHandle
}

/// One armed press observer or hotkey. Its owner releases it exactly once; after `release()` the
/// observer never runs again and the hotkey no longer fires. `status` is the OS status of the call
/// that made the handle, `0` on success.
public protocol HotkeyHandle: Sendable {
    var status: Int32 { get }
    @MainActor func release()
}

public enum HotkeyGatewayKey: TestDependencyKey {
    public static let testValue: any HotkeyGateway = UnimplementedHotkeyGateway()
}

extension DependencyValues {
    public var hotkeyGateway: any HotkeyGateway {
        get { self[HotkeyGatewayKey.self] }
        set { self[HotkeyGatewayKey.self] = newValue }
    }
}

private struct UnimplementedHotkeyGateway: HotkeyGateway {
    @MainActor
    func observePresses(_ onPress: @escaping @Sendable (UInt32) -> Void) -> any HotkeyHandle {
        reportIssue("HotkeyGateway.observePresses not implemented")
        return UnimplementedHotkeyHandle()
    }

    @MainActor
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> any HotkeyHandle {
        reportIssue("HotkeyGateway.register not implemented")
        return UnimplementedHotkeyHandle()
    }
}

private struct UnimplementedHotkeyHandle: HotkeyHandle {
    var status: Int32 { -1 }

    @MainActor
    func release() {}
}
