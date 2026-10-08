import Dependencies

/// `VirtualCameraRepository`: where host frames go to become the virtual
/// camera. Gated on the extension being installed — it never sends otherwise —
/// and resolves each `FrameRef` to its surface before handing it to the
/// transport. The caller still owns the lease and releases it afterwards.
public protocol VirtualCameraSink: Sendable {
    func connect() async throws
    func disconnect()
    func send(_ frame: FrameRef) -> SendOutcome
    func observe(_ onEvent: @escaping @Sendable (FrameTransportEvent) -> Void)
}

public enum VirtualCameraSinkKey: TestDependencyKey {
    public static let testValue: any VirtualCameraSink = UnimplementedVirtualCameraSink()
}

extension DependencyValues {
    public var virtualCameraSink: any VirtualCameraSink {
        get { self[VirtualCameraSinkKey.self] }
        set { self[VirtualCameraSinkKey.self] = newValue }
    }
}

private struct UnimplementedVirtualCameraSink: VirtualCameraSink {
    func connect() async throws {
        reportIssue("VirtualCameraSink.connect not implemented")
        throw MachError.lookupFailed(code: -1)
    }

    func disconnect() {
        reportIssue("VirtualCameraSink.disconnect not implemented")
    }

    func send(_ frame: FrameRef) -> SendOutcome {
        reportIssue("VirtualCameraSink.send not implemented")
        return .dropped(.notConnected)
    }

    func observe(_ onEvent: @escaping @Sendable (FrameTransportEvent) -> Void) {
        reportIssue("VirtualCameraSink.observe not implemented")
    }
}
