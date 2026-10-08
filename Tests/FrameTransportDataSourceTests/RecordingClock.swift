import TestSupport

/// A clock whose sleeps return at once and are recorded, so a test asserts the
/// exact back-off sequence without racing a timer. (`TestClock` is used where
/// the behaviour under test is *waiting* for the clock.)
final class RecordingClock: Clock, Sendable {
    struct Instant: InstantProtocol {
        let offset: Duration

        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    let sleeps = Collector<Duration>()

    var now: Instant { Instant(offset: .zero) }
    var minimumResolution: Duration { .zero }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        sleeps.append(now.duration(to: deadline))
    }
}
