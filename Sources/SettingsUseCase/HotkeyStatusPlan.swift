import Domain

/// The status the settings window shows for the hotkeys, from the stored flag and what the system
/// registered. A failed action comes before the empty check, so a registration that refused every
/// binding is a conflict, not off. Pure, so the policy is tested as a table.
func hotkeyStatus(enabled: Bool, registration: HotkeyRegistration) -> HotkeyStatus {
    guard enabled else { return .off }
    guard registration.failed.isEmpty else { return .conflicted(registration.failed) }
    return registration.registered.isEmpty ? .off : .active
}
