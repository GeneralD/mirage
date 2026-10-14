import Dependencies

/// Thin pass-through to the desktop (live: `NSWorkspace`): hands a path to the system
/// to open, which for a folder is Finder showing it. Nothing is reported back; whether
/// the folder exists is decided before this is called (`EffectPackageDataSource`).
public protocol WorkspaceGateway: Sendable {
    func open(_ path: String)
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
}
