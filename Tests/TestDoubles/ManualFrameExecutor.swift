import Domain

/// The test stand-in for the serial frame executor: `run` only enqueues, and
/// `drain()` executes everything queued — including work enqueued by the work
/// it runs — on the calling thread. Nothing happens between `drain()` calls, so
/// a test observes exactly one state transition at a time.
public final class ManualFrameExecutor: FrameExecutor, Sendable {
    private let queue = Locked<[@Sendable () -> Void]>([])

    public init() {}

    public var pendingCount: Int { queue.current.count }

    public func run(_ work: @escaping @Sendable () -> Void) {
        queue.withLock { $0.append(work) }
    }

    /// Runs queued work until the queue is empty. Returns how many items ran.
    @discardableResult
    public func drain() -> Int {
        drainStep(count: 0)
    }

    private func drainStep(count: Int) -> Int {
        guard let next = queue.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) else { return count }
        next()
        return drainStep(count: count + 1)
    }
}

/// The test stand-in for frame pacing: `tick()` fires the registered callback
/// once, synchronously. Pair with `ManualFrameExecutor.drain()` when the
/// subject hops the tick onto the executor.
public final class ManualFrameScheduler: FrameScheduler, Sendable {
    private struct State {
        var frameRate: FrameRate?
        var onTick: (@Sendable () -> Void)?
        var startCount = 0
        var stopCount = 0
    }

    private let state = Locked(State())

    public init() {}

    public var isRunning: Bool { state.current.onTick != nil }
    public var frameRate: FrameRate? { state.current.frameRate }
    public var startCount: Int { state.current.startCount }
    public var stopCount: Int { state.current.stopCount }

    public func start(frameRate: FrameRate, onTick: @escaping @Sendable () -> Void) {
        state.withLock {
            $0.frameRate = frameRate
            $0.onTick = onTick
            $0.startCount += 1
        }
    }

    public func stop() {
        state.withLock {
            $0.onTick = nil
            $0.stopCount += 1
        }
    }

    /// Fires one tick; a no-op when the scheduler is stopped.
    public func tick() {
        state.current.onTick?()
    }

    public func tick(times: Int) {
        for _ in 0..<times { tick() }
    }
}
