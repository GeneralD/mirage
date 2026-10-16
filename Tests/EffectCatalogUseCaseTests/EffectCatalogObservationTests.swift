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

    // MARK: - A run that starts while the one before it is still finishing

    // The runtime never cancels a `prepare`, so a run whose task was cancelled can still be waiting for one when the
    // Interactor has started the next. The tests below park the old run in exactly that wait.

    @Test("a run that starts while the one before it still waits for the runtime is not cut short when that run ends")
    func restartWhileTheLastRunFinishes() async {
        let rig = Rig(persisted: glitch.id)
        let run = rig.start()
        await rig.answer(1)
        let edited = EffectSource(name: "Glitch", source: "glitch v2")
        rig.packages.script(.success(edited), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        await rig.runtime.prepareRequests.waitForCount(2)  // the reload is out
        run.cancel()

        let again = rig.start()
        await rig.runtime.prepareRequests.waitForCount(3)  // the new run restored the choice and prepared it for itself
        // Opened once the new run has begun, as the Interactor does: what the old run left current is gone by now.
        let watcher = rig.watch()
        await rig.answer(2)
        await run.value
        await rig.answer(3, with: .failure(.compileFailed))
        await watcher.states.waitForCount(1)

        #expect(
            watcher.states.values == [Rig.state(selection: glitch, outcome: .failed(.compileFailed))],
            "the old run's state was not replayed, and the old run's end did not drop the new run's answer")
        #expect(watcher.ended.count == 0, "the old run's end did not close the stream of an observer that opened after it was cancelled")
        #expect(
            rig.runtime.prepareRequests.values.map(\.effect) == [Rig.glitchSource, edited, edited],
            "the new run did not trust what the old run had prepared")
        #expect(rig.settings.reads.count == 2)
        await rig.stop(again)
        await watcher.ended.waitForCount(1)
    }

    @Test("an answer that comes back from the run before while the new run is still reading its first source publishes nothing")
    func lateAnswerWhileTheNewRunReads() async {
        let rig = Rig(persisted: glitch.id)
        let run = rig.start()
        await rig.answer(1)
        rig.packages.script(.success(EffectSource(name: "Glitch", source: "glitch v2")), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        await rig.runtime.prepareRequests.waitForCount(2)
        run.cancel()

        rig.packages.holdSources()
        let again = rig.start()
        await rig.packages.heldSources.waitForCount(1)  // the new run knows the choice and the rows, and has issued no prepare yet
        let watcher = rig.watch()
        // A failure, unlike the new run's own success: if it were published, the state below would not be the only one.
        await rig.answer(2, with: .failure(.compileFailed))
        await run.value
        rig.packages.holdSources(false)
        rig.packages.completeSource(rig.packages.heldSources.values[0])
        await rig.answer(3)
        await watcher.states.waitForCount(1)

        #expect(watcher.states.values == [Rig.state(selection: glitch)], "the first state of the new run is its own, not the old run's answer")
        await rig.stop(again)
    }

    @Test("a source read of the run before that ends once the new run has started prepares nothing")
    func oldRunsReadEndsInTheNewRun() async {
        let rig = Rig(persisted: glitch.id)
        let run = rig.start()
        await rig.answer(1)
        let edited = EffectSource(name: "Glitch", source: "glitch v2")
        rig.packages.script(.success(edited), for: glitch.id)
        rig.packages.holdSources()
        rig.packages.publish([bundled, glitch, other])
        await rig.packages.heldSources.waitForCount(1)  // the old run is reading the edited files
        run.cancel()

        let again = rig.start()
        await rig.packages.heldSources.waitForCount(2)  // and so is the new run
        let watcher = rig.watch()
        let reads = rig.packages.heldSources.values
        rig.packages.holdSources(false)
        rig.packages.completeSource(reads[0])
        await run.value
        rig.packages.completeSource(reads[1])
        await rig.answer(2)
        await watcher.states.waitForCount(1)

        #expect(rig.runtime.prepareRequests.values.map(\.effect) == [Rig.glitchSource, edited], "one prepare for the edit: the new run's")
        #expect(watcher.states.values == [Rig.state(selection: glitch)])
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

    @Test("a listing still reading the chosen effect's source when another effect is chosen prepares nothing for the old choice")
    func choiceOvertakesAListingsRead() async {
        let rig = Rig(persisted: glitch.id)
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        // The listing is reading glitch's files...
        let edited = EffectSource(name: "Glitch", source: "glitch v2")
        rig.packages.script(.success(edited), for: glitch.id)
        rig.packages.holdSources()
        rig.packages.publish([bundled, glitch, other])
        await rig.packages.heldSources.waitForCount(1)
        // ...when the user chooses another effect, whose own read goes first.
        let choice = Task { await rig.subject.select(other.id) }
        await rig.packages.heldSources.waitForCount(2)
        let reads = rig.packages.heldSources.values
        rig.packages.completeSource(reads[1])
        await rig.answer(2)
        #expect(await choice.value == .prepared)
        await watcher.states.waitForCount(2)
        // The listing's read ends now: glitch is no longer the choice. The run takes one listing at a
        // time, so the sentinel's state can only come after the held listing has been dealt with.
        rig.packages.holdSources(false)
        rig.packages.completeSource(reads[0])
        rig.packages.publish([bundled, glitch, other, EffectCatalogEntry.fixture(.package("later"))])
        await watcher.states.waitForCount(3)

        #expect(rig.runtime.prepareRequests.values.map(\.effect) == [Rig.glitchSource, Rig.otherSource], "nothing was prepared for the old choice")
        #expect(watcher.states.values.map(\.selection) == [glitch.id, other.id, other.id])
        #expect(watcher.states.values.map(\.outcome) == [.prepared, .prepared, .prepared])
        await rig.stop(run)
    }

    @Test(
        "a choice still reading its source when a newer choice completes prepares nothing: it answers unavailable, and the newer choice owns the effect"
    )
    func choiceOvertakenWhileReading() async {
        let rig = Rig()
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        rig.packages.holdSources()
        let older = Task { await rig.subject.select(glitch.id) }
        await rig.packages.heldSources.waitForCount(1)
        let newer = Task { await rig.subject.select(other.id) }
        await rig.packages.heldSources.waitForCount(2)
        let reads = rig.packages.heldSources.values
        rig.packages.completeSource(reads[1])
        await rig.answer(2)
        #expect(await newer.value == .prepared)
        await watcher.states.waitForCount(2)
        rig.packages.completeSource(reads[0])

        #expect(await older.value == .unavailable(nil), "it prepared nothing, and says so")
        #expect(rig.runtime.prepareRequests.values.map(\.effect) == [Rig.bundledSource, Rig.otherSource])
        #expect(rig.settings.writes.values == [glitch.id, other.id], "both were chosen, in that order; the newest is the persisted one")
        #expect(watcher.states.values.map(\.selection) == [bundled.id, other.id])
        await rig.stop(run)
    }

    @Test("a choice still reading its source when the catalog loses that package prepares nothing: the fallback owns the effect")
    func choiceOvertakenByAFallback() async {
        let rig = Rig()
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        rig.packages.holdSources()
        let choice = Task { await rig.subject.select(glitch.id) }
        await rig.packages.heldSources.waitForCount(1)
        rig.packages.publish([bundled, other])  // glitch went away: the listing falls back and reads the bundled effect
        await rig.packages.heldSources.waitForCount(2)
        let reads = rig.packages.heldSources.values
        rig.packages.completeSource(reads[1])
        await watcher.states.waitForCount(2)
        rig.packages.completeSource(reads[0])

        #expect(await choice.value == .unavailable(nil))
        #expect(rig.runtime.prepareRequests.count == 1, "the bundled effect was already the one prepared, and glitch never was")
        #expect(watcher.states.values.last == Rig.state([bundled, other], selection: bundled))
        #expect(rig.log.messages(in: .effect) == ["effect 'Chromatic Grain' selected", "effect 'glitch' is gone; back to 'Chromatic Grain'"])
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

    @Test("a choice still reading an effect's files when a listing reads newer files of the same effect prepares nothing for the old files")
    func listingOvertakesAChoicesReadOfTheSameEffect() async {
        let rig = Rig()
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        rig.packages.holdSources()
        let choice = Task { await rig.subject.select(glitch.id) }  // reads glitch's files as they are
        await rig.packages.heldSources.waitForCount(1)
        let edited = EffectSource(name: "Glitch", source: "glitch v2")
        rig.packages.script(.success(edited), for: glitch.id)  // a read that begins from now on finds the edit
        rig.packages.publish([bundled, glitch, other])  // and the listing reads the chosen effect again
        await rig.packages.heldSources.waitForCount(2)
        let reads = rig.packages.heldSources.values
        rig.packages.holdSources(false)
        rig.packages.completeSource(reads[1])
        await rig.answer(2)
        await watcher.states.waitForCount(2)
        rig.packages.completeSource(reads[0])

        #expect(await choice.value == .unavailable(nil), "it prepared nothing, and says so")
        #expect(rig.runtime.prepareRequests.values.map(\.effect) == [Rig.bundledSource, edited], "the old files never reached the runtime")
        #expect(watcher.states.values.map(\.selection) == [bundled.id, glitch.id])
        await rig.stop(run)
    }

    @Test("a source read of the run before that ends in a run that has nothing to read yet prepares nothing")
    func oldReadEndsInARunWithNothingToRead() async {
        let rig = Rig(persisted: glitch.id)
        let run = rig.start()
        await rig.answer(1)
        let edited = EffectSource(name: "Glitch", source: "glitch v2")
        rig.packages.script(.success(edited), for: glitch.id)
        rig.packages.holdSources()
        rig.packages.publish([bundled, glitch, other])
        await rig.packages.heldSources.waitForCount(1)  // the old run is reading the edited files
        run.cancel()
        rig.packages.publish([])  // the next run lists nothing, so the old read is still the newest one
        let again = rig.start()
        await rig.packages.catalogRequests.waitForCount(2)  // the new run has restored the choice and listens
        let newest = EffectSource(name: "Glitch", source: "glitch v3")
        rig.packages.script(.success(newest), for: glitch.id)  // what the new run's own read will find, unlike what the old read holds
        let read = rig.packages.heldSources.values[0]
        rig.packages.holdSources(false)
        rig.packages.completeSource(read)
        await run.value  // the old run took the empty listing it had queued and ended: it prepared nothing
        let watcher = rig.watch()
        rig.packages.publish([bundled, glitch, other])  // a listing the new run can act on
        await rig.answer(2)
        await watcher.states.waitForCount(1)

        #expect(
            rig.runtime.prepareRequests.values.map(\.effect) == [Rig.glitchSource, newest],
            "one prepare for the edit: the new run's, from its own read")
        await rig.stop(again)
    }

    @Test("a choice still reading its source when its run ends and the next one starts prepares nothing")
    func choiceReadingAcrossARestart() async {
        let rig = Rig()
        let run = rig.start()
        await rig.answer(1)
        rig.packages.holdSources()
        let choice = Task { await rig.subject.select(glitch.id) }
        await rig.packages.heldSources.waitForCount(1)
        await rig.stop(run)
        rig.packages.publish([])  // the next run lists nothing, so the choice's read is still the newest one
        let again = rig.start()
        await rig.settings.reads.waitForCount(2)  // the new run has restored the choice the old one remembered
        let read = rig.packages.heldSources.values[0]
        rig.packages.holdSources(false)
        rig.packages.completeSource(read)
        let watcher = rig.watch()
        rig.packages.publish([bundled, glitch, other])
        await rig.answer(2)
        await watcher.states.waitForCount(1)

        #expect(await choice.value == .unavailable(nil), "the choice belongs to the run before, which is over")
        #expect(
            rig.runtime.prepareRequests.values.map(\.effect) == [Rig.bundledSource, Rig.glitchSource],
            "the new run's own prepare is the only one after the first")
        await rig.stop(again)
    }
}
