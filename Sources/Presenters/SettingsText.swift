import Domain

// The words of the settings window (#197): the notes under launch at login and under the hotkeys,
// the names of the hotkey actions and the glyphs of their keys, as pure functions of the settings
// state, so that `SettingsPresenter` only moves them into its `@Published` values and the View only
// draws them.

/// The note under launch at login for `status`; `nil` when there is nothing to say.
func launchAtLoginNote(of status: LaunchAtLoginStatus) -> String? {
    switch status {
    case .needsApproval:
        "Waiting for approval in System Settings → General → Login Items."
    case .unavailable:
        "Available when the app is installed in /Applications."
    case .off, .on:
        nil
    }
}

/// The note under the hotkeys for `status`: the actions the system refused, named in the order of
/// `HotkeyAction.allCases`; `nil` when the hotkeys are off or all of them work.
func hotkeyNote(of status: HotkeyStatus) -> String? {
    switch status {
    case .conflicted(let actions):
        let titles = HotkeyAction.allCases
            .filter { actions.contains($0) }
            .map(hotkeyTitle(of:))
            .joined(separator: ", ")
        return "Could not register \(titles). Another app may be using the same keys."
    case .off, .active:
        return nil
    }
}

/// The name of `action` in the hotkey list.
func hotkeyTitle(of action: HotkeyAction) -> String {
    switch action {
    case .toggleBypass:
        "Toggle Bypass"
    case .nextEffect:
        "Next Effect"
    case .previousEffect:
        "Previous Effect"
    }
}

/// The rows of the hotkey list for `bindings`: one per action that has a binding, in
/// `HotkeyAction.allCases` order whatever order the bindings come in.
func settingsHotkeyRows(for bindings: [HotkeyBinding]) -> [SettingsHotkeyRow] {
    HotkeyAction.allCases.compactMap { action in
        bindings.first { $0.action == action }.map { binding in
            SettingsHotkeyRow(id: action, title: hotkeyTitle(of: action), keys: keyGlyphs(of: binding))
        }
    }
}

/// The keys of `binding` as the list shows them: the modifiers in the order control, option,
/// shift, command, then the name of the key. `⌃⌥⌘B` is the bypass's default.
func keyGlyphs(of binding: HotkeyBinding) -> String {
    let modifiers: [(mask: UInt32, glyph: String)] = [(4096, "⌃"), (2048, "⌥"), (512, "⇧"), (256, "⌘")]
    let glyphs =
        modifiers
        .filter { (binding.modifiers & $0.mask) != 0 }
        .map(\.glyph)
    return (glyphs + [keyName(of: binding.keyCode)]).joined()
}

/// The name of a Carbon virtual key code: B and the two arrows the default bindings use, and
/// `Key <code>` for any other code.
private func keyName(of keyCode: UInt32) -> String {
    switch keyCode {
    case 11: "B"
    case 123: "←"
    case 124: "→"
    default: "Key \(keyCode)"
    }
}
