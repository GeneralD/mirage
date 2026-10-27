import Domain
import EffectWatchDataSource
import TestDoubles
import TestSupport
import Testing

/// Debounce coalescing (`docs/ARCHITECTURE.md` → *Seeded property tests*): for any spacing of
/// the events, the number of elements is the number of bursts, a burst being a run of events
/// each less than the quiet period after the one before.
///
/// The model keeps its own 200 ms, written out below instead of read from
/// `EffectWatchDataSourceImpl.quietPeriod`: a test that read the subject's constant would move
/// with it and stay green. The gaps are drawn from a table that straddles the boundary (199,
/// 200 and 201 ms), so a period that is 1 ms too short or too long is seen by most seeds.
@Suite("EffectWatchDataSourceImpl debounce coalescing", .timeLimit(.minutes(1)))
struct EffectWatchDebouncePropertyTests {
    private static let quiet = Duration.milliseconds(200)
    /// The gaps after an event: inside the period, one short of it, exactly it, one past it, and well past it.
    private static let gapMilliseconds: [Int] = [0, 1, 25, 100, 199, 200, 201, 350, 600]
    private static let gaps: [Duration] = gapMilliseconds.map { Duration.milliseconds($0) }
    private static let paths = [
        "/effects", "/effects/a.lens", WatchRig.manifest, WatchRig.shader,
    ]

    @Test("the elements are the bursts, whatever the spacing of the events (seeded)", arguments: Seeds.range(0..<50))
    func oneElementPerBurst(seed: UInt64) async {
        var generator = SeededGenerator(seed: seed)
        let rig = WatchRig()
        let heard = Collector<Duration>()
        let consumer = rig.listen(to: rig.subject.changes(of: WatchRig.onePackage), into: heard)
        defer { consumer.cancel() }

        // Every path of the set has exactly one watch, so a fire that reaches another number is a watch that was
        // not armed (or armed twice), and the wait for its sleep below would hang: fail here, with the seed.
        func fire(_ path: String, as description: String) -> Bool {
            let reached = rig.gateway.fire(path)
            guard reached == 1 else {
                Issue.record("seed \(seed), \(description): \(path) reached \(reached) watches, the set arms it once")
                return false
            }
            return true
        }

        let events = (0..<Int.random(in: 1...12, using: &generator)).map { _ in
            (
                path: Self.paths[Int.random(in: 0..<Self.paths.count, using: &generator)],
                gap: Self.gaps[Int.random(in: 0..<Self.gaps.count, using: &generator)]
            )
        }

        // The model: when each event's sleep is due, and the elements it says there will be.
        var due: [Duration] = []
        var now = Duration.zero
        var expected: [Duration] = []
        for (index, event) in events.enumerated() {
            guard fire(event.path, as: "event \(index)") else { return }
            await rig.clock.sleepers.waitForCount(index + 1)
            due.append(now + Self.quiet)

            rig.clock.advance(by: event.gap)
            now += event.gap
            let stillParked = due.filter { $0 > now }.count
            guard rig.clock.parkedCount == stillParked else {
                Issue.record("seed \(seed), event \(index): \(rig.clock.parkedCount) sleeps parked at \(now), the model says \(stillParked)")
                return
            }
            // The newest event's period is over exactly when the gap reached it.
            guard event.gap >= Self.quiet else { continue }
            expected.append(now)
            await heard.waitForCount(expected.count)
        }

        // A last burst after all of them: an element a burst too many would show up in front of it.
        guard fire(Self.paths[0], as: "the last burst") else { return }
        await rig.clock.sleepers.waitForCount(events.count + 1)
        rig.clock.advance(by: Self.quiet)
        now += Self.quiet
        expected.append(now)
        await heard.waitForCount(expected.count)
        await rig.end(consumer)

        #expect(heard.values == expected, "seed \(seed): gaps \(events.map(\.gap))")
        #expect(rig.clock.parkedCount == 0)
        #expect(rig.gateway.isBalanced)
    }
}
