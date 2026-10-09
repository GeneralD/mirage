import Domain
import ExtensionRelayUseCase
import TestSupport
import Testing

@Suite("SlateSchedule")
struct SlateScheduleTests {
    /// 10 fps: a frame is 100 ms, so expectations read as plain numbers.
    private static let rate = FrameRate(framesPerSecond: 10)
    private static let frame: UInt64 = 100_000_000

    private func time(_ milliseconds: UInt64) -> HostTimestamp { HostTimestamp(nanoseconds: milliseconds * 1_000_000) }
    private func schedule() -> SlateSchedule { SlateSchedule(frameRate: Self.rate) }

    @Test("a fresh schedule is live with nothing emitted")
    func initialState() {
        let schedule = schedule()
        #expect(schedule.phase == .live(lastEmitted: nil))
        #expect(!schedule.isSlate)
        #expect(schedule.lastEmitted == nil)
    }

    @Test("the slate base is the host time when nothing was emitted, and never behind the last PTS plus a frame")
    func base() {
        var schedule = schedule()
        #expect(schedule.slateBase(hostNow: time(500)) == time(500))

        #expect(schedule.admit(time(1_000)) == .relay)
        #expect(schedule.slateBase(hostNow: time(5_000)) == time(5_000), "host time ahead of the last PTS wins")
        #expect(schedule.slateBase(hostNow: time(100)) == time(1_100), "a lagging host time is lifted to last + frame")
        #expect(schedule.slateBase(hostNow: time(1_050)) == time(1_100))
    }

    @Test("entering slate starts at the base; ticks advance by one frame and count as emitted")
    func ticks() {
        var schedule = schedule()
        schedule.enterSlate(base: time(500))

        #expect(schedule.isSlate)
        #expect(schedule.lastEmitted == time(500))
        #expect(schedule.nextSlateTime() == time(500))
        #expect(schedule.nextSlateTime() == time(600))
        #expect(schedule.nextSlateTime() == time(700))
        #expect(schedule.phase == .slate(base: time(500), next: 3, lastEmitted: time(700)))
    }

    @Test("a tick while live yields nothing and changes nothing")
    func tickWhileLive() {
        var schedule = schedule()
        #expect(schedule.admit(time(10)) == .relay)
        let before = schedule

        #expect(schedule.nextSlateTime() == nil)
        #expect(schedule == before)
    }

    @Test("entering slate twice keeps the first episode; the base is unavailable while in slate")
    func enterTwice() {
        var schedule = schedule()
        schedule.enterSlate(base: time(500))
        _ = schedule.nextSlateTime()

        #expect(schedule.slateBase(hostNow: time(9_000)) == nil)
        schedule.enterSlate(base: time(9_000))
        #expect(schedule.phase == .slate(base: time(500), next: 1, lastEmitted: time(500)))
    }

    @Test("live admits only strictly newer PTS")
    func liveAdmission() {
        var schedule = schedule()
        #expect(schedule.admit(time(100)) == .relay)
        #expect(schedule.admit(time(100)) == .dropNonMonotonic, "equal is not newer")
        #expect(schedule.admit(time(99)) == .dropNonMonotonic)
        #expect(schedule.lastEmitted == time(100), "a dropped frame does not move the mark")
        #expect(schedule.admit(time(101)) == .relay)
    }

    @Test("slate resumes on a PTS beyond the last emitted slate PTS; older and equal are dropped")
    func slateAdmission() {
        var schedule = schedule()
        schedule.enterSlate(base: time(500))
        _ = schedule.nextSlateTime()
        _ = schedule.nextSlateTime()

        #expect(schedule.admit(time(600)) == .dropNonMonotonic, "equal to the last slate frame")
        #expect(schedule.admit(time(100)) == .dropNonMonotonic)
        #expect(schedule.isSlate)

        #expect(schedule.admit(time(601)) == .resume)
        #expect(schedule.phase == .live(lastEmitted: time(601)))
    }

    @Test("after resuming, a new episode starts above everything emitted")
    func secondEpisode() {
        var schedule = schedule()
        schedule.enterSlate(base: time(500))
        _ = schedule.nextSlateTime()
        #expect(schedule.admit(time(2_000)) == .resume)

        #expect(schedule.slateBase(hostNow: time(0)) == time(2_100))
    }

    @Test("reset forgets the episode and the last PTS")
    func reset() {
        var schedule = schedule()
        schedule.enterSlate(base: time(500))
        schedule.reset()

        #expect(schedule.phase == .live(lastEmitted: nil))
        #expect(schedule.admit(time(1)) == .relay)
    }

    @Test("over random event sequences every emitted PTS is strictly greater than the one before", arguments: Seeds.range(0..<50))
    func strictlyIncreasing(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        var schedule = schedule()
        var emitted: [HostTimestamp] = []

        for _ in 0..<200 {
            switch Int.random(in: 0..<4, using: &generator) {
            case 0:
                let candidate = time(UInt64.random(in: 0..<5_000, using: &generator))
                switch schedule.admit(candidate) {
                case .relay, .resume: emitted.append(candidate)
                case .dropNonMonotonic: break
                }
            case 1, 2:
                if let tick = schedule.nextSlateTime() { emitted.append(tick) }
            default:
                let now = time(UInt64.random(in: 0..<5_000, using: &generator))
                if let base = schedule.slateBase(hostNow: now) { schedule.enterSlate(base: base) }
            }
        }

        #expect(zip(emitted, emitted.dropFirst()).allSatisfy { $0 < $1 }, "seed \(seed): \(emitted)")
        #expect(emitted.last == schedule.lastEmitted || emitted.isEmpty)
    }
}
