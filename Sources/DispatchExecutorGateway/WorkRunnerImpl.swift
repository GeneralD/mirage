import Domain

/// Live `WorkRunner`: one unstructured `Task` per work item. The task is the only
/// place the frame path's async work gets a lifetime; the handle cancels it.
public struct WorkRunnerImpl: WorkRunner {
    public init() {}

    public func run(_ work: @escaping @Sendable () async -> Void) -> any WorkHandle {
        TaskWorkHandle(task: Task(operation: work))
    }
}

private struct TaskWorkHandle: WorkHandle {
    let task: Task<Void, Never>

    func cancel() {
        task.cancel()
    }
}
