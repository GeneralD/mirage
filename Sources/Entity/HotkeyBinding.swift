/// What a global hotkey does. The raw value is the Carbon hotkey id the system returns on a key
/// press, so it is never 0 and a case is never renumbered.
public enum HotkeyAction: Int, Sendable, Hashable, CaseIterable {
    case toggleBypass = 1
    case nextEffect = 2
    case previousEffect = 3
}

/// One global hotkey: an action bound to a key and its modifiers. Entity does not import Carbon,
/// so both values are plain numbers in Carbon's encoding.
public struct HotkeyBinding: Sendable, Hashable {
    /// A Carbon virtual key code.
    public let action: HotkeyAction
    public let keyCode: UInt32
    /// A Carbon modifier mask: command 256, shift 512, option 2048, control 4096.
    public let modifiers: UInt32

    public init(action: HotkeyAction, keyCode: UInt32, modifiers: UInt32) {
        self.action = action
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

/// The bindings the app starts with: control, option and command with B toggles the bypass,
/// with the right and left arrows it steps to the next and the previous effect.
public let defaultHotkeyBindings: [HotkeyBinding] = [
    HotkeyBinding(action: .toggleBypass, keyCode: 11, modifiers: 4096 + 2048 + 256),
    HotkeyBinding(action: .nextEffect, keyCode: 124, modifiers: 4096 + 2048 + 256),
    HotkeyBinding(action: .previousEffect, keyCode: 123, modifiers: 4096 + 2048 + 256),
]

/// The hotkeys the system accepted and the actions it refused.
public struct HotkeyRegistration: Sendable, Hashable {
    public let registered: [HotkeyAction]
    public let failed: [HotkeyAction]

    public init(registered: [HotkeyAction] = [], failed: [HotkeyAction] = []) {
        self.registered = registered
        self.failed = failed
    }

    public static let empty = HotkeyRegistration()
}

/// Whether the global hotkeys work: not registered, all active, or some refused (`conflicted`,
/// carrying the actions that could not be registered).
public enum HotkeyStatus: Sendable, Hashable {
    case off
    case active
    case conflicted([HotkeyAction])
}
