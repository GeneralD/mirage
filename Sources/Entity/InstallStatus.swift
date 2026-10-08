/// Where the Camera Extension stands with the system (`CameraExtensionInstaller`).
///
/// ```text
/// notInstalled → installing → needsApproval → installed
///                    │              │
///                    └── failed ◀───┘
/// ```
public enum InstallStatus: Sendable, Hashable {
    case notInstalled
    case installing
    /// The system is waiting for the user to allow the extension in System
    /// Settings; the activation request stays pending until they do.
    case needsApproval
    case installed
    case failed(reason: String)
}

extension InstallStatus {
    /// `installed` or `failed`: the activation request has finished.
    public var isTerminal: Bool {
        switch self {
        case .installed, .failed: true
        case .notInstalled, .installing, .needsApproval: false
        }
    }

    public var isInstalled: Bool { self == .installed }
}

/// What the system extension manager reports back for an activation request,
/// as the gateway hands it up (`SystemExtensionGateway`).
public enum SystemExtensionEvent: Sendable, Hashable {
    case needsApproval
    /// `.completed` from the request; the extension is active.
    case completed
    /// `.willCompleteAfterReboot` — the extension activates on next boot.
    case completesAfterReboot
    case failed(reason: String)
}
