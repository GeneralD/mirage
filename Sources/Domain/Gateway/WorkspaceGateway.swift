import Dependencies

/// Thin pass-through to the desktop (live: `NSWorkspace`): hands a path to the system
/// to open, which for a folder is Finder showing it. Nothing is reported back; whether
/// the folder exists is decided before this is called (`EffectPackageDataSource`).
///
/// `openURL` hands a URL string to the system, which opens it with the app registered
/// for its scheme. It returns what the system accepted: `false` for a string that is not
/// a URL, and `false` when the system refuses it. Which URL to open is decided above.
public protocol WorkspaceGateway: Sendable {
    func open(_ path: String)
    func openURL(_ url: String) -> Bool
}

public enum WorkspaceGatewayKey: TestDependencyKey {
    public static let testValue: any WorkspaceGateway = UnimplementedWorkspaceGateway()
}

extension DependencyValues {
    public var workspaceGateway: any WorkspaceGateway {
        get { self[WorkspaceGatewayKey.self] }
        set { self[WorkspaceGatewayKey.self] = newValue }
    }
}

private struct UnimplementedWorkspaceGateway: WorkspaceGateway {
    func open(_ path: String) {
        reportIssue("WorkspaceGateway.open not implemented")
    }

    func openURL(_ url: String) -> Bool {
        reportIssue("WorkspaceGateway.openURL not implemented")
        return false
    }
}
