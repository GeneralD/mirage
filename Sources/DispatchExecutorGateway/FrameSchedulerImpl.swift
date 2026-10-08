import Dispatch
import Domain

/// Live `FrameScheduler`: a `DispatchSourceTimer` that fires on the executor's
/// own queue, so a tick is just another unit of frame-path work and needs no
/// extra hop or lock.
///
/// The timer handle is guarded by the queue itself: `start` / `stop` use
/// `queue.sync`, which also means that once `stop()` returns, no further tick
/// is delivered. Called from the queue itself (a `queue.sync` there would
/// deadlock), they run inline instead: a cancelled timer never fires again, so
/// the guarantee still holds.
public final class FrameSchedulerImpl: FrameScheduler, @unchecked Sendable {
    private let queue: DispatchQueue
    private let onQueueKey = DispatchSpecificKey<Void>()
    // Guarded by `queue`: only touched inside `queue.sync`.
    private var timer: DispatchSourceTimer?

    public init(queue: DispatchQueue) {
        self.queue = queue
        queue.setSpecific(key: onQueueKey, value: ())
    }

    deinit {
        timer?.cancel()
    }

    public func start(frameRate: FrameRate, onTick: @escaping @Sendable () -> Void) {
        onQueue {
            timer?.cancel()
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(
                deadline: .now(),
                repeating: .nanoseconds(Int(frameRate.frameDuration.totalNanoseconds)),
                leeway: .milliseconds(1)
            )
            source.setEventHandler(handler: onTick)
            source.resume()
            timer = source
        }
    }

    public func stop() {
        onQueue {
            timer?.cancel()
            timer = nil
        }
    }

    private func onQueue(_ body: () -> Void) {
        DispatchQueue.getSpecific(key: onQueueKey) == nil ? queue.sync(execute: body) : body()
    }
}
