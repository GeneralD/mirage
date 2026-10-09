import Foundation
import TestSupport

/// A clock a test steps by hand, whose `sleepers` collector fires only *after* a
/// sleep is registered. Waiting on it therefore proves the subject is parked, which
/// no other observable (a log line, a call count) does: those happen before the
/// subject reaches `sleep`, and advancing time in that gap is lost.
///
/// Sleeps honour task cancellation the way `ContinuousClock` does, so a test can
/// prove that cancelling a parked task ends the sleep with `CancellationError`.
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
        let continuation: CheckedContinuation<Void, any Error>
    }

    private enum Registration { case due, parked }

    /// One entry per registered sleep, holding the deadline it asked for.
    public let sleepers = Collector<Duration>()

    private let lock = NSLock()
    private var current = Instant(offset: .zero)
    private var parked: [UInt64: Sleeper] = [:]
    private var nextID: UInt64 = 0

    public init() {}

    public var now: Instant { lock.withLock { current } }
    public var minimumResolution: Duration { .zero }

    /// How many sleeps are parked right now: registered, neither woken nor cancelled.
    public var parkedCount: Int { lock.withLock { parked.count } }

    /// A sleep that is already cancelled on entry throws before parking; cancelling a
    /// parked sleep removes it and throws `CancellationError`. Whoever removes the
    /// sleeper from `parked` under the lock is the only one to resume it, so a
    /// cancellation racing `advance` resumes it exactly once.
    public func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        let id = lock.withLock {
            defer { nextID += 1 }
            return nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let registration = lock.withLock { () -> Registration in
                    guard deadline > current else { return .due }
                    parked[id] = Sleeper(deadline: deadline, continuation: continuation)
                    return .parked
                }
                switch registration {
                case .due:
                    continuation.resume()
                case .parked:
                    sleepers.append(deadline.offset)
                    // A cancellation that ran before the sleeper was registered found
                    // nothing to remove; the flag it set is still visible here.
                    if Task.isCancelled { cancel(id) }
                }
            }
        } onCancel: {
            cancel(id)
        }
    }

    /// Moves time forward and wakes every sleeper whose deadline has been reached.
    public func advance(by duration: Duration) {
        let woken = lock.withLock {
            current = current.advanced(by: duration)
            let due = parked.filter { $0.value.deadline <= current }
            for id in due.keys { parked.removeValue(forKey: id) }
            return Array(due.values)
        }
        for sleeper in woken { sleeper.continuation.resume() }
    }

    private func cancel(_ id: UInt64) {
        let sleeper = lock.withLock { parked.removeValue(forKey: id) }
        sleeper?.continuation.resume(throwing: CancellationError())
    }
}
