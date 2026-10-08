import Dependencies

/// `FrameReceiverDataSource`, extension side: registers the service name,
/// owns the receive loop (one `MachMessageGateway.receive` per message,
/// resolved through the IOSurface gateway) and detects host absence — a dead
/// name from the kernel, or no frame within the gap budget on the injected
/// clock. `onFrame` is delivered on the `FrameExecutor`.
public protocol FrameReceiver: Sendable {
    /// Runs until `stop()` or until the receive right dies. Throws when the
    /// service name cannot be registered (the Q2 failure modes).
    func start(
        onFrame: @escaping @Sendable (IncomingSurface) -> Void,
        onEvent: @escaping @Sendable (ReceiverEvent) -> Void
    ) async throws
    func stop()
}

public enum FrameReceiverKey: TestDependencyKey {
    public static let testValue: any FrameReceiver = UnimplementedFrameReceiver()
}

extension DependencyValues {
    public var frameReceiver: any FrameReceiver {
        get { self[FrameReceiverKey.self] }
        set { self[FrameReceiverKey.self] = newValue }
    }
}

private struct UnimplementedFrameReceiver: FrameReceiver {
    func start(
        onFrame: @escaping @Sendable (IncomingSurface) -> Void,
        onEvent: @escaping @Sendable (ReceiverEvent) -> Void
    ) async throws {
        reportIssue("FrameReceiver.start not implemented")
        throw MachError.checkInFailed(code: -1)
    }

    func stop() {
        reportIssue("FrameReceiver.stop not implemented")
    }
}
