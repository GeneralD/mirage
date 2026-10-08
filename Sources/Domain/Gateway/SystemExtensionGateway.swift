import Dependencies

/// Thin pass-through to `OSSystemExtensionManager`: submit one activation
/// request and relay its delegate callbacks. The stream finishes after the
/// terminal event; `.replace` is always chosen when an older build is present.
public protocol SystemExtensionGateway: Sendable {
    func activate(extensionBundleID: String) -> AsyncStream<SystemExtensionEvent>
}

public enum SystemExtensionGatewayKey: TestDependencyKey {
    public static let testValue: any SystemExtensionGateway = UnimplementedSystemExtensionGateway()
}

extension DependencyValues {
    public var systemExtensionGateway: any SystemExtensionGateway {
        get { self[SystemExtensionGatewayKey.self] }
        set { self[SystemExtensionGatewayKey.self] = newValue }
    }
}

private struct UnimplementedSystemExtensionGateway: SystemExtensionGateway {
    func activate(extensionBundleID: String) -> AsyncStream<SystemExtensionEvent> {
        reportIssue("SystemExtensionGateway.activate not implemented")
        return AsyncStream { $0.finish() }
    }
}
