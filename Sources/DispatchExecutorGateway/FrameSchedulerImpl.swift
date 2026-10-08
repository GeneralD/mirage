import Dispatch
import Domain

/// Live `FrameScheduler`: a `DispatchSourceTimer` that fires on the executor's
/// own queue, so a tick is just another unit of frame-path work and needs no
/// extra hop or lock.
///
/// The timer handle is guarded by the queue itself: `start` / `stop` use
/// `queue.sync`, which also means that once `stop()` returns, no further tick
/// is delivered. They must therefore never be called from that queue.
public final class FrameSchedulerImpl: FrameScheduler, @unchecked Sendable {
    private let queue: DispatchQueue
    // Guarded by `queue`: only touched inside `queue.sync`.
    private var timer: DispatchSourceTimer?

    public init(queue: DispatchQueue) {
        self.queue = queue
    }

    deinit {
        timer?.cancel()
    }

    public func start(frameRate: FrameRate, onTick: @escaping @Sendable () -> Void) {
        queue.sync {
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
        queue.sync {
            timer?.cancel()
            timer = nil
        }
    }
}
