import Domain
import TestSupport

/// A `WorkRunner` that starts each work item as a real `Task` at once (the fake sink
/// and `GatedClock` park it deterministically) and records what happened, so a test
/// awaits "the reconnect has finished" on a collector instead of polling the subject.
/// Each item is numbered from 0 in start order; the collectors hold those numbers.
public final class RecordingWorkRunner: WorkRunner, Sendable {
    /// An item whose work was started.
    public let started = Collector<Int>()
    /// An item whose work returned, however it ended.
    public let finished = Collector<Int>()
    /// An item whose handle was cancelled by its owner.
    public let cancelled = Collector<Int>()
    private let next = Locked(0)

    public init() {}

    public func run(_ work: @escaping @Sendable () async -> Void) -> any WorkHandle {
        let item = next.withLock { count -> Int in
            defer { count += 1 }
            return count
        }
        started.append(item)
        let finished = finished
        let task = Task {
            await work()
            finished.append(item)
        }
        return Handle(item: item, task: task, cancelled: cancelled)
    }

    private struct Handle: WorkHandle {
        let item: Int
        let task: Task<Void, Never>
        let cancelled: Collector<Int>

        func cancel() {
            cancelled.append(item)
            task.cancel()
        }
    }
}
