import Dependencies

/// Runs long, suspending frame-path work (a reconnect parked in a back-off sleep, a
/// connect waiting on the service) off the `FrameExecutor` and hands back a handle to
/// cancel it. State transitions stay on the executor; this port owns only the lifetime
/// of the async work, so the frame path never starts an unstructured `Task` itself.
/// Live: a Swift `Task`. Tests: `RecordingWorkRunner`, which records starts, finishes
/// and cancels so a test can await "the work has finished" instead of polling.
public protocol WorkRunner: Sendable {
    /// Starts `work` at once and returns the handle that cancels it.
    func run(_ work: @escaping @Sendable () async -> Void) -> any WorkHandle
}

/// Opaque handle to work started through a `WorkRunner`. Its owner cancels it once,
/// through `cancel()`; cancelling work that has already finished does nothing.
public protocol WorkHandle: Sendable {
    func cancel()
}

public enum WorkRunnerKey: TestDependencyKey {
    public static let testValue: any WorkRunner = UnimplementedWorkRunner()
}

extension DependencyValues {
    public var workRunner: any WorkRunner {
        get { self[WorkRunnerKey.self] }
        set { self[WorkRunnerKey.self] = newValue }
    }
}

private struct UnimplementedWorkRunner: WorkRunner {
    func run(_ work: @escaping @Sendable () async -> Void) -> any WorkHandle {
        reportIssue("WorkRunner.run not implemented")
        return UnimplementedWorkHandle()
    }
}

private struct UnimplementedWorkHandle: WorkHandle {
    func cancel() {}
}
