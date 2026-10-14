import Domain
import TestDoubles
import TestSupport
import Testing

/// Who sees which state, and the runtime answering out of order. The runtime fake completes a
/// `prepare` only when the test says so, in any order, so "the newest request wins" is a
/// sequence written down here, not a race provoked.
@Suite("EffectCatalogUseCase observation and newest wins", .timeLimit(.minutes(1)))
struct EffectCatalogObservationTests {
    private typealias Rig = EffectCatalogRig
    private let bundled = Rig.bundled
    private let glitch = Rig.glitch
    private let other = Rig.other

    // MARK: - Observers

    @Test("there is no state before the run has settled one: an observer waits for the runtime's first answer")
    func nothingBeforeTheFirstState() async {
        let rig = Rig()
        let watcher = rig.watch()
        let run = rig.start()
        await rig.runtime.prepareRequests.waitForCount(1)

        #expect(watcher.states.values.isEmpty, "the prepare is still out: the outcome is not known, so there is nothing to show")
        await rig.answer(1)
        await watcher.states.waitForCount(1)
        await rig.stop(run)
    }

    @Test("every observer gets the same states in the same order, and one opened later starts from the current one")
    func severalObservers() async {
        let rig = Rig(persisted: glitch.id)
        let first = rig.watch()
        let second = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        for watcher in [first, second] { await watcher.states.waitForCount(1) }

        rig.packages.script(.success(EffectSource(name: "Glitch", source: "glitch v2")), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        await rig.answer(2, with: .failure(.compileFailed))
        for watcher in [first, second] { await watcher.states.waitForCount(2) }
        let late = rig.watch()
        await late.states.waitForCount(1)

        let initial = Rig.state(selection: glitch)
        let failed = Rig.state(selection: glitch, outcome: .failed(.compileFailed))
        #expect(first.states.values == [initial, failed])
        #expect(second.states.values == [initial, failed])
        #expect(late.states.values == [failed])
        await rig.stop(run)
    }

    @Test("an observer that lets go stops receiving; the others are not affected")
    func observerLeaves() async {
        let rig = Rig(persisted: glitch.id)
        let leaving = rig.watch()
        let staying = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await leaving.states.waitForCount(1)
        await staying.states.waitForCount(1)

        leaving.consumer.cancel()
        await leaving.ended.waitForCount(1)
        rig.packages.script(.success(EffectSource(name: "Glitch", source: "glitch v2")), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        await rig.answer(2, with: .failure(.compileFailed))
        await staying.states.waitForCount(2)

        #expect(leaving.states.count == 1)
        #expect(staying.states.count == 2)
        await rig.stop(run)
    }

    @Test("cancelling the run ends every observer's stream and lets go of the catalog")
    func cancelEndsTheStreams() async {
        let rig = Rig()
        let watchers = [rig.watch(), rig.watch()]
        let run = rig.start()
        await rig.answer(1)
        for watcher in watchers { await watcher.states.waitForCount(1) }

        await rig.stop(run)
        for watcher in watchers { await watcher.ended.waitForCount(1) }
        await rig.packages.terminations.waitForCount(1)
    }

    @Test("a run that ends leaves nothing current: an observer opened after it starts from the next run's first state")
    func restartForgetsTheLastRun() async {
        let rig = Rig()
        let first = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await first.states.waitForCount(1)
        await rig.stop(run)
        await first.ended.waitForCount(1)

        await rig.settings.setSelectedEffect(glitch.id)
        let second = rig.watch()
        let again = rig.start()
        await rig.answer(2)
        await second.states.waitForCount(1)

        #expect(second.states.values == [Rig.state(selection: glitch)], "the first run's state was not replayed")
        #expect(rig.settings.reads.count == 2, "the choice is restored again by the new run")
        await rig.stop(again)
    }

    @Test("an answer that reaches a run that has ended publishes nothing into the next one")
    func lateAnswerFromAnEndedRun() async {
        let rig = Rig()
        let run = rig.start()
        await rig.answer(1)
        let selection = Task { await rig.subject.select(glitch.id) }
        await rig.runtime.prepareRequests.waitForCount(2)
        await rig.stop(run)

        let watcher = rig.watch()
        let again = rig.start()
        await rig.runtime.prepareRequests.waitForCount(3)
        rig.runtime.completePrepare(rig.runtime.prepareRequests.values[1], with: .success(()))
        #expect(await selection.value == .prepared, "it still answers its own caller")
        await rig.answer(3, with: .failure(.compileFailed))
        await watcher.states.waitForCount(1)

        #expect(watcher.states.values == [Rig.state(selection: glitch, outcome: .failed(.compileFailed))])
        await rig.stop(again)
    }

    // MARK: - Newest wins

    @Test("two choices answered newest first: the state shows the newest, and the older answer, failing later, publishes nothing")
    func newestAnsweredFirst() async {
        let rig = Rig()
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        let older = Task { await rig.subject.select(glitch.id) }
        await rig.runtime.prepareRequests.waitForCount(2)
        let newer = Task { await rig.subject.select(other.id) }
        await rig.runtime.prepareRequests.waitForCount(3)
        await rig.answer(3, with: .success(()))
        await watcher.states.waitForCount(2)
        await rig.answer(2, with: .failure(.compileFailed))

        #expect(await newer.value == .prepared)
        #expect(await older.value == .failed(.compileFailed), "an overtaken choice still hears its own answer")
        // A sentinel through the same pipeline: the next state is the next one in line.
        rig.packages.publish([bundled, glitch, other, EffectCatalogEntry.fixture(.package("later"))])
        await watcher.states.waitForCount(3)

        #expect(watcher.states.values.map(\.selection) == [bundled.id, other.id, other.id])
        #expect(watcher.states.values.map(\.outcome) == [.prepared, .prepared, .prepared], "the older failure never became the outcome")
        await rig.stop(run)
    }

    @Test("two choices answered oldest first: the older answer publishes nothing, so the state never shows an outcome that is not the newest's")
    func newestAnsweredLast() async {
        let rig = Rig()
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        let older = Task { await rig.subject.select(glitch.id) }
        await rig.runtime.prepareRequests.waitForCount(2)
        let newer = Task { await rig.subject.select(other.id) }
        await rig.runtime.prepareRequests.waitForCount(3)
        await rig.answer(2, with: .success(()))
        #expect(await older.value == .prepared)
        // A listing now publishes the rows with the newest choice and no outcome yet: the older answer is not it.
        rig.packages.publish([bundled, glitch, other, EffectCatalogEntry.fixture(.package("later"))])
        await watcher.states.waitForCount(2)
        await rig.answer(3, with: .failure(.compileFailed))
        #expect(await newer.value == .failed(.compileFailed))
        await watcher.states.waitForCount(3)

        #expect(watcher.states.values.map(\.selection) == [bundled.id, other.id, other.id])
        #expect(watcher.states.values.map(\.outcome) == [.prepared, nil, .failed(.compileFailed)])
        await rig.stop(run)
    }

    @Test("a hot reload overtaken by a choice publishes nothing, and the runtime was handed the choice last")
    func reloadOvertakenByChoice() async {
        let rig = Rig(persisted: glitch.id)
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        let edited = EffectSource(name: "Glitch", source: "glitch v2")
        rig.packages.script(.success(edited), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        await rig.runtime.prepareRequests.waitForCount(2)  // the reload is out
        let choice = Task { await rig.subject.select(other.id) }
        await rig.runtime.prepareRequests.waitForCount(3)
        await rig.answer(3)
        await watcher.states.waitForCount(2)
        await rig.answer(2, with: .failure(.compileFailed))
        #expect(await choice.value == .prepared)
        // The run loop was held by the reload; it takes this listing only after the reload's answer was dropped.
        rig.packages.publish([bundled, glitch, other, EffectCatalogEntry.fixture(.package("later"))])
        await watcher.states.waitForCount(3)

        #expect(rig.runtime.prepareRequests.values.map(\.effect) == [Rig.glitchSource, edited, Rig.otherSource])
        #expect(watcher.states.values.map(\.selection) == [glitch.id, other.id, other.id])
        #expect(watcher.states.values.map(\.outcome) == [.prepared, .prepared, .prepared], "the reload's failure never became the outcome")
        await rig.stop(run)
    }
}
