import Dispatch
import Domain

/// Live `FrameExecutor`: one serial dispatch queue that every frame-path
/// callback is funnelled through.
///
/// A serial queue gives UseCase frame state its single-threaded guarantee with
/// no locks. `userInteractive` QoS keeps capture-to-send latency low. The queue
/// is public so `FrameSchedulerImpl` can fire its ticks on the same context.
public final class FrameExecutorImpl: FrameExecutor {
    public let queue = DispatchQueue(label: "frame-executor", qos: .userInteractive)

    public init() {}

    public func run(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }
}
