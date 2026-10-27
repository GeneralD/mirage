import Domain
import EffectWatchDataSource
import Foundation
import TestDoubles
import TestSupport
import Testing

/// `EffectWatchDataSourceImpl` over `FakeFileWatchGateway` and a hand-stepped clock. The test
/// is the file system (`gateway.fire(path)`) and time (`clock.advance(by:)`); it advances only
/// once the subject's sleep is registered (`clock.sleepers.waitForCount`), so nothing here
/// waits on a timer, and "no element yet" is read off the clock (the one sleep that could yield
/// one is still parked), never off a window of ticks.
@MainActor
@Suite("EffectWatchDataSourceImpl", .timeLimit(.minutes(1)))
struct EffectWatchDataSourceImplTests {
    private let rig = WatchRig()
    private let heard = Collector<Duration>()

    // MARK: Arming

    @Test("every directory and file of the set is armed before changes(of:) returns, directories as directories and files as files")
    func armsTheWholeSet() {
        let stream = rig.subject.changes(of: WatchRig.onePackage)

        withExtendedLifetime(stream) {
            #expect(
                rig.gateway.watches.values == [
                    .init(kind: .directory, path: "/effects"),
                    .init(kind: .directory, path: "/effects/a.lens"),
                    .init(kind: .file, path: WatchRig.manifest),
                    .init(kind: .file, path: WatchRig.shader),
                ])
        }
    }

    @Test("a change made right after the call is not lost, even before anyone iterates the stream")
    func armedBeforeItReturns() async {
        let stream = rig.subject.changes(of: WatchRig.onePackage)
        #expect(rig.gateway.fire(WatchRig.shader) == 1, "the shader's file watch is live as soon as the call returns")

        let consumer = rig.listen(to: stream, into: heard)
        await rig.clock.sleepers.waitForCount(1)
        rig.clock.advance(by: .milliseconds(200))
        await heard.waitForCount(1)
        await rig.end(consumer)

        #expect(heard.count == 1)
    }

    @Test("a path that cannot be armed is logged and skipped, and the rest of the set still works")
    func unarmablePathIsSkipped() async {
        let gone = "/effects/gone.lens"
        rig.gateway.failWatch(of: gone, with: CocoaError(.fileNoSuchFile))
        let set = EffectWatchSet(directories: ["/effects", gone], files: [WatchRig.shader])

        let stream = rig.subject.changes(of: set)
        let consumer = rig.listen(to: stream, into: heard)

        #expect(rig.gateway.watches.values.map(\.path) == ["/effects", WatchRig.shader], "the watch that threw was not armed")
        #expect(
            rig.log.messages(in: .effect).contains { $0.contains("directory \(gone)") },
            "the developer log says which kind of watch and which path could not be armed")

        rig.gateway.fire(WatchRig.shader)
        await rig.clock.sleepers.waitForCount(1)
        rig.clock.advance(by: .milliseconds(200))
        await heard.waitForCount(1)
        await rig.end(consumer)
        #expect(rig.gateway.isBalanced, "only the watches that were armed are stopped")
    }

    // MARK: One element per burst

    @Test("one event is one element, and only once the 200 ms quiet period has run out")
    func oneEventWaitsForTheQuietPeriod() async {
        let consumer = rig.listen(to: rig.subject.changes(of: WatchRig.onePackage), into: heard)

        rig.gateway.fire(WatchRig.shader)
        await rig.clock.sleepers.waitForCount(1)
        #expect(heard.count == 0, "the only sleep that could yield an element is still parked")

        rig.clock.advance(by: .milliseconds(199))
        #expect(rig.clock.parkedCount == 1, "one millisecond short: the period is still running")
        #expect(heard.count == 0, "the only sleep that could yield an element has not been woken")

        rig.clock.advance(by: .milliseconds(1))
        #expect(rig.clock.parkedCount == 0, "the period ran out")
        await heard.waitForCount(1)
        await rig.end(consumer)

        #expect(heard.values == [.milliseconds(200)])
    }

    @Test("events inside the period restart it, so a burst is one element, and the next burst is one more")
    func aBurstIsOneElement() async {
        let consumer = rig.listen(to: rig.subject.changes(of: WatchRig.onePackage), into: heard)

        // t = 0, 150, 300: each event comes before the period the one before it started has run out.
        rig.gateway.fire(WatchRig.shader)
        await rig.clock.sleepers.waitForCount(1)
        rig.clock.advance(by: .milliseconds(150))
        rig.gateway.fire(WatchRig.manifest)
        await rig.clock.sleepers.waitForCount(2)
        rig.clock.advance(by: .milliseconds(150))
        #expect(rig.clock.parkedCount == 1, "the first event's sleep ended at 200 ms; the second's, due at 350 ms, is the one still running")
        rig.gateway.fire("/effects")
        await rig.clock.sleepers.waitForCount(3)

        rig.clock.advance(by: .milliseconds(199))
        #expect(rig.clock.parkedCount == 1, "199 ms after the last event of the burst: only its sleep (due at 500 ms) is still running")
        rig.clock.advance(by: .milliseconds(1))
        await heard.waitForCount(1)

        // A second burst, far enough from the first.
        rig.gateway.fire(WatchRig.shader)
        await rig.clock.sleepers.waitForCount(4)
        rig.clock.advance(by: .milliseconds(200))
        await heard.waitForCount(2)
        await rig.end(consumer)

        #expect(
            heard.values == [.milliseconds(500), .milliseconds(700)],
            "one element per burst, stamped when its period ran out: the periods of the first two events ended at 200 and 350 ms and yielded nothing")
    }

    @Test("two events a quiet period apart are two elements")
    func eventsApartAreSeparateBursts() async {
        let consumer = rig.listen(to: rig.subject.changes(of: WatchRig.onePackage), into: heard)

        rig.gateway.fire(WatchRig.shader)
        await rig.clock.sleepers.waitForCount(1)
        rig.clock.advance(by: .milliseconds(200))
        await heard.waitForCount(1)

        rig.gateway.fire(WatchRig.shader)
        await rig.clock.sleepers.waitForCount(2)
        rig.clock.advance(by: .milliseconds(200))
        await heard.waitForCount(2)
        await rig.end(consumer)

        #expect(heard.values == [.milliseconds(200), .milliseconds(400)])
    }

    @Test("a directory watch and a file watch on one path both report, and it is still one burst")
    func bothKindsOnOnePathFoldTogether() async {
        let both = EffectWatchSet(directories: ["/effects/a.lens"], files: ["/effects/a.lens"])
        let consumer = rig.listen(to: rig.subject.changes(of: both), into: heard)

        #expect(rig.gateway.fire("/effects/a.lens") == 2)
        await rig.clock.sleepers.waitForCount(2)
        rig.clock.advance(by: .milliseconds(200))
        await heard.waitForCount(1)

        // The element after it proves the first burst did not leave a second one behind.
        rig.gateway.fire("/effects/a.lens")
        await rig.clock.sleepers.waitForCount(4)
        rig.clock.advance(by: .milliseconds(200))
        await heard.waitForCount(2)
        await rig.end(consumer)

        #expect(heard.values == [.milliseconds(200), .milliseconds(400)])
    }

    // MARK: Ending

    @Test("the stream stays open until its consumer lets go, for an empty set and for one nothing could be armed from")
    func staysOpenWithNothingToWatch() async {
        // Nothing is armed, so no event can reach the stream and there is no sentinel to send through
        // it: a bounded run of ticks, each moving the clock a second, is the check that it neither
        // ends by itself nor ends on a timer (the budget is the proof, as `tickUntil` documents). A
        // stream that ended at once would end within the first ticks, each of which gives the
        // consumer's task a millisecond to run.
        for set in [EffectWatchSet.empty, EffectWatchSet(directories: ["/effects"], files: [WatchRig.shader])] {
            let rig = WatchRig()
            rig.gateway.failWatch(of: "/effects", with: CocoaError(.fileNoSuchFile))
            rig.gateway.failWatch(of: WatchRig.shader, with: CocoaError(.fileNoSuchFile))
            let ended = Collector<Void>()
            let stream = rig.subject.changes(of: set)
            let consumer = Task {
                for await _ in stream {}
                ended.append(())
            }

            let endedByItself = await tickUntil(50, tick: { rig.clock.advance(by: .seconds(1)) }, until: { ended.count > 0 })
            #expect(!endedByItself, "an end the consumer did not cause reads as the watch being gone")

            consumer.cancel()
            await ended.waitForCount(1)
            #expect(rig.gateway.watchCount == 0)
            #expect(rig.gateway.isBalanced)
        }
    }

    @Test("when the consumer is cancelled every watch is stopped, exactly once")
    func cancellingStopsEveryWatch() async {
        let consumer = rig.listen(to: rig.subject.changes(of: WatchRig.onePackage), into: heard)
        #expect(rig.gateway.activeWatches.count == 4)

        await rig.end(consumer)

        #expect(rig.gateway.stopCount == 4)
        #expect(rig.gateway.activeWatches.isEmpty)
        #expect(rig.gateway.isBalanced, "no watch was stopped twice")
    }

    @Test("when the consumer stops iterating every watch is stopped, exactly once")
    func leavingTheLoopStopsEveryWatch() async {
        let consumer = Task {
            for await _ in rig.subject.changes(of: WatchRig.onePackage) { break }
        }
        await rig.gateway.watches.waitForCount(4)

        rig.gateway.fire(WatchRig.shader)
        await rig.clock.sleepers.waitForCount(1)
        rig.clock.advance(by: .milliseconds(200))
        await consumer.value

        #expect(rig.gateway.stopCount == 4)
        #expect(rig.gateway.isBalanced)
    }

    @Test("the quiet period in progress is dropped when the consumer lets go, and every watch is stopped")
    func endingDropsTheSleepAndStopsTheWatches() async {
        let consumer = rig.listen(to: rig.subject.changes(of: WatchRig.onePackage), into: heard)
        rig.gateway.fire(WatchRig.shader)
        await rig.clock.sleepers.waitForCount(1)

        await rig.end(consumer)

        await rig.clock.cancelledSleepers.waitForCount(1)
        #expect(rig.clock.parkedCount == 0, "the sleep the period was waiting on is cancelled with the stream")
        #expect(rig.gateway.fire(WatchRig.shader) == 0, "every watch was stopped: the gateway has nobody to tell about a later event")
    }

    @Test("an event that arrives after the stream ended starts no period, and the other stream is unaffected")
    func lateEventsOfAnEndedStreamStartNothing() async {
        let ended = rig.listen(to: rig.subject.changes(of: WatchRig.onePackage), into: Collector())
        // What the ended stream's watches were armed with, taken before the second stream adds its own.
        let late = rig.keeper.callbacks
        #expect(late.count == 4, "one callback per watch of the set")
        let live = rig.listen(to: rig.subject.changes(of: WatchRig.onePackage), into: heard)
        await rig.end(ended)

        // The fake does not fire a stopped watch, so the callbacks are delivered directly, as a dispatch
        // source's handler that was already running when its watch was stopped would.
        for callback in late { callback() }

        // The second stream is the sentinel: its burst goes through the same clock, and an element
        // for it is heard only after the late events had their chance to start a period of their own.
        #expect(rig.gateway.fire(WatchRig.shader) == 1, "only the second stream's watch on the shader is still live")
        await rig.clock.sleepers.waitForCount(1)
        rig.clock.advance(by: .milliseconds(200))
        await heard.waitForCount(1)
        await rig.end(live)

        #expect(rig.clock.sleepers.count == 1, "the second stream's period is the only sleep ever registered: the late events started none")
        #expect(heard.values == [.milliseconds(200)])
        #expect(rig.gateway.isBalanced)
    }
}
