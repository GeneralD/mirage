import Dependencies

/// The serial context the frame path runs on. Capture callbacks, scheduler
/// ticks and transport events are all funnelled through `run`, so UseCase frame
/// state is a single-threaded state machine with no locks. Live: one serial
/// dispatch queue. Tests: `ManualFrameExecutor.drain()`.
public protocol FrameExecutor: Sendable {
    func run(_ work: @escaping @Sendable () -> Void)
}

/// Frame pacing. `onTick` fires once per frame interval **on the
/// `FrameExecutor`**. Live: a timer on the executor's queue. Tests:
/// `ManualFrameScheduler.tick()`.
public protocol FrameScheduler: Sendable {
    func start(frameRate: FrameRate, onTick: @escaping @Sendable () -> Void)
    func stop()
}

public enum FrameExecutorKey: TestDependencyKey {
    public static let testValue: any FrameExecutor = UnimplementedFrameExecutor()
}

public enum FrameSchedulerKey: TestDependencyKey {
    public static let testValue: any FrameScheduler = UnimplementedFrameScheduler()
}

extension DependencyValues {
    public var frameExecutor: any FrameExecutor {
        get { self[FrameExecutorKey.self] }
        set { self[FrameExecutorKey.self] = newValue }
    }

    public var frameScheduler: any FrameScheduler {
        get { self[FrameSchedulerKey.self] }
        set { self[FrameSchedulerKey.self] = newValue }
    }
}

private struct UnimplementedFrameExecutor: FrameExecutor {
    func run(_ work: @escaping @Sendable () -> Void) {
        reportIssue("FrameExecutor.run not implemented")
    }
}

private struct UnimplementedFrameScheduler: FrameScheduler {
    func start(frameRate: FrameRate, onTick: @escaping @Sendable () -> Void) {
        reportIssue("FrameScheduler.start not implemented")
    }

    func stop() {
        reportIssue("FrameScheduler.stop not implemented")
    }
}
