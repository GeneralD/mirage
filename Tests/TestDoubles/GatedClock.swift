import Foundation
import TestSupport

/// A clock a test steps by hand, whose `sleepers` collector fires only *after* a
/// sleep is registered. Waiting on it therefore proves the subject is parked, which
/// no other observable (a log line, a call count) does: those happen before the
/// subject reaches `sleep`, and advancing time in that gap is lost.
public final class GatedClock: Clock, @unchecked Sendable {
    public struct Instant: InstantProtocol {
        public let offset: Duration

        public init(offset: Duration) { self.offset = offset }

        public func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        public func duration(to other: Instant) -> Duration { other.offset - offset }
        public static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        let deadline: Instant
        let continuation: CheckedContinuation<Void, Never>
    }

    /// One entry per registered sleep, holding the deadline it asked for.
    public let sleepers = Collector<Duration>()

    private let lock = NSLock()
    private var current = Instant(offset: .zero)
    private var parked: [Sleeper] = []

    public init() {}

    public var now: Instant { lock.withLock { current } }
    public var minimumResolution: Duration { .zero }

    public func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        await withCheckedContinuation { continuation in
            let due = lock.withLock {
                let due = deadline <= current
                parked += due ? [] : [Sleeper(deadline: deadline, continuation: continuation)]
                return due
            }
            _ = due ? continuation.resume() : sleepers.append(deadline.offset)
        }
    }

    /// Moves time forward and wakes every sleeper whose deadline has been reached.
    public func advance(by duration: Duration) {
        let woken = lock.withLock {
            current = current.advanced(by: duration)
            let split = parked.partition { $0.deadline <= current }
            let woken = Array(parked[split...])
            parked.removeSubrange(split...)
            return woken
        }
        for sleeper in woken { sleeper.continuation.resume() }
    }
}
