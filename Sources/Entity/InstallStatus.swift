/// Where the Camera Extension stands with the system (`CameraExtensionInstaller`).
///
/// ```text
/// notInstalled → installing → needsApproval → installed
///                    │              │     └──▶ rebootRequired
///                    └── failed ◀───┘
/// ```
public enum InstallStatus: Sendable, Hashable {
    case notInstalled
    case installing
    /// The system is waiting for the user to allow the extension in System
    /// Settings; the activation request stays pending until they do.
    case needsApproval
    case installed
    /// The activation was accepted but takes effect only after the next restart;
    /// the extension is not active until then, so nothing may be started on it.
    case rebootRequired
    /// The request ended in an error; see `InstallFailure` for the classes.
    case failed(InstallFailure)
}

extension InstallStatus {
    /// `installed`, `rebootRequired` or `failed`: the activation request has finished.
    public var isTerminal: Bool {
        switch self {
        case .installed, .rebootRequired, .failed: true
        case .notInstalled, .installing, .needsApproval: false
        }
    }

    public var isInstalled: Bool { self == .installed }
}

/// Why an activation request failed, classified from the system's error code.
public enum InstallFailure: Sendable, Hashable {
    /// The user or system policy refused the extension (`forbiddenBySystemPolicy`).
    case denied
    /// The request was canceled or superseded by a newer one.
    case canceled
    /// The app bundle itself is wrong (entitlement, location, identifier, category, signature).
    case invalidBuild(code: Int)
    case other(code: Int, description: String)
}

/// What the system extension manager reports back for an activation request,
/// as the gateway hands it up (`SystemExtensionGateway`).
public enum SystemExtensionEvent: Sendable, Hashable {
    case needsApproval
    /// `.completed` from the request; the extension is active.
    case completed
    /// `.willCompleteAfterReboot` — the extension activates on next boot.
    case completesAfterReboot
    /// The system's raw error code and localized description; classified by the DataSource.
    case failed(code: Int, description: String)
    /// An older build of the extension is installed and is about to be replaced.
    case willReplaceExisting
}
