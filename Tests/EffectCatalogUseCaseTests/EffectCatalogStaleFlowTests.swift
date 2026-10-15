import Domain
import TestDoubles
import TestSupport
import Testing

/// A flow that was suspended (reading a source, remembering a choice, restoring the persisted one, waiting for the
/// runtime) resumes into a catalog that has moved on, and may act only if nothing newer owns what it came for. Each test
/// parks one flow at one `await`, moves the catalog on, lets the flow go, and checks that it left everything alone.
///
/// What the guards are against is what each test name says; the run number and the read number are what hold them
/// (`EffectCatalogSession`). The settings fake holds a call exactly as the package fake holds a read, because a choice
/// is remembered before its source is read and a run restores the persisted choice before it lists anything.
@Suite("EffectCatalogUseCase stale flows", .timeLimit(.minutes(1)))
struct EffectCatalogStaleFlowTests {
    private typealias Rig = EffectCatalogRig
    private let bundled = Rig.bundled
    private let glitch = Rig.glitch
    private let other = Rig.other
    private let later = EffectCatalogEntry.fixture(.package("later"))

    /// A call through the session that touches nothing. The session runs the jobs queued on it one after the other, so the
    /// call is answered after the flow that the step before it resumed has run to its next suspension (or to its end).
    private func flushed(_ rig: Rig) async {
        _ = await rig.subject.select(.package("nobody"))
    }

    @Test("a listing the run before had queued, taken up after the new run began, changes nothing of the new run")
    func queuedListingOfTheRunBefore() async {
        let rig = Rig(persisted: glitch.id)
        let queued = [bundled, glitch, other, later]
        let newest = queued + [EffectCatalogEntry.fixture(.package("latest"))]
        let run = rig.start()
        await rig.answer(1)
        rig.packages.script(.success(EffectSource(name: "Glitch", source: "glitch v2")), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        await rig.runtime.prepareRequests.waitForCount(2)  // the old run waits for the runtime
        run.cancel()
        rig.packages.publish(queued)  // its stream keeps the listing for when it is free again

        let again = rig.start()
        await rig.runtime.prepareRequests.waitForCount(3)  // the new run listed the same catalog and prepares for itself
        let watcher = rig.watch()
        rig.packages.script(.success(EffectSource(name: "Glitch", source: "glitch v3")), for: glitch.id)
        rig.packages.publish(newest)
        await rig.answer(3)
        await rig.runtime.prepareRequests.waitForCount(4)  // and the newest listing, whose files changed again, prepares once more
        await rig.answer(2)  // the old run is free: it takes up the listing it queued, which is older than the new run's
        await run.value
        await rig.answer(4)
        await watcher.states.waitForCount(2)

        #expect(
            watcher.states.values == [Rig.state(queued, selection: glitch), Rig.state(newest, selection: glitch)],
            "the rows are the newest listing's: the old run's listing did not put its older rows back")
        await rig.stop(again)
    }

    @Test("listings the run before had queued, older than where the new run began, neither put back their rows nor take the choice away")
    func queuedOlderListingsOfTheRunBefore() async {
        let rig = Rig(persisted: glitch.id)
        let gone = [bundled, other]  // glitch is not in it: settling it would fall back to the bundled effect
        let current = [bundled, glitch, other, later]
        let run = rig.start()
        await rig.answer(1)
        rig.packages.script(.success(EffectSource(name: "Glitch", source: "glitch v2")), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        await rig.runtime.prepareRequests.waitForCount(2)  // the old run waits for the runtime
        run.cancel()
        rig.packages.publish(gone)  // its stream keeps both listings for when it is free again
        rig.packages.publish(current)

        let again = rig.start()  // begins with the catalog as it stands now: it never saw `gone`
        await rig.runtime.prepareRequests.waitForCount(3)
        let watcher = rig.watch()
        await rig.answer(2)  // the old run is free: it takes up `gone`, then `current`
        await run.value
        await rig.answer(3)
        await watcher.states.waitForCount(1)

        #expect(
            watcher.states.values == [Rig.state(current, selection: glitch)],
            "the new run kept glitch chosen and the rows it listed: nothing of the old run's listings reached them")
        await rig.stop(again)
    }

    @Test("a listing still reading an effect's files when a choice of the same effect reads newer files prepares nothing for the old files")
    func choiceOvertakesAListingsReadOfTheSameEffect() async {
        let rig = Rig(persisted: glitch.id)
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        rig.packages.holdSources()
        rig.packages.script(.success(EffectSource(name: "Glitch", source: "glitch v2")), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])  // the listing reads glitch's files as they are
        await rig.packages.heldSources.waitForCount(1)
        let newer = EffectSource(name: "Glitch", source: "glitch v3")
        rig.packages.script(.success(newer), for: glitch.id)
        let choice = Task { await rig.subject.select(glitch.id) }  // and the choice, later, finds the edit
        await rig.packages.heldSources.waitForCount(2)
        let reads = rig.packages.heldSources.values
        rig.packages.holdSources(false)
        rig.packages.completeSource(reads[1])
        await rig.answer(2)
        #expect(await choice.value == .prepared)  // the state it publishes equals the first one, so the watcher sees nothing new
        rig.packages.completeSource(reads[0])  // the listing's read, the older one, ends last
        rig.packages.publish([bundled, glitch, other, later])  // the run takes one listing at a time, so this one is dealt with after it
        await watcher.states.waitForCount(2)

        #expect(rig.runtime.prepareRequests.values.map(\.effect) == [Rig.glitchSource, newer], "the old files never reached the runtime")
        #expect(watcher.states.values == [Rig.state(selection: glitch), Rig.state([bundled, glitch, other, later], selection: glitch)])
        await rig.stop(run)
    }

    @Test("a listing that read the chosen effect's files while another effect was being remembered as the choice prepares nothing for the old choice")
    func listingOvertakenByAChoiceBeingRemembered() async throws {
        let rig = Rig(persisted: glitch.id)
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        rig.packages.holdSources()
        rig.packages.script(.success(EffectSource(name: "Glitch", source: "glitch v2")), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])  // the listing is reading glitch's files...
        await rig.packages.heldSources.waitForCount(1)
        rig.settings.holdWrites()
        let choice = Task { await rig.subject.select(other.id) }  // ...when other is chosen, and is still being remembered
        await rig.settings.heldRequests.waitForCount(1)
        rig.packages.holdSources(false)
        rig.packages.completeSource(rig.packages.heldSources.values[0])  // no read was issued after the listing's, but the choice has moved on
        await flushed(rig)
        try #require(rig.runtime.prepareRequests.count == 1, "the listing prepared the old choice")

        rig.settings.holdWrites(false)
        rig.settings.complete(rig.settings.heldRequests.values[0])
        await rig.answer(2)
        #expect(await choice.value == .prepared)
        await watcher.states.waitForCount(2)

        #expect(rig.runtime.prepareRequests.values.map(\.effect) == [Rig.glitchSource, Rig.otherSource])
        #expect(watcher.states.values.map(\.selection) == [glitch.id, other.id])
        await rig.stop(run)
    }

    @Test("a choice whose files were read while another effect was being remembered as the choice prepares nothing")
    func choiceOvertakenByAChoiceBeingRemembered() async throws {
        let rig = Rig()
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        rig.packages.holdSources()
        let older = Task { await rig.subject.select(glitch.id) }
        await rig.packages.heldSources.waitForCount(1)  // reading glitch's files...
        rig.settings.holdWrites()
        let newer = Task { await rig.subject.select(other.id) }  // ...when other is chosen, and is still being remembered
        await rig.settings.heldRequests.waitForCount(1)
        // No read was issued after the older choice's, but the newer choice has moved on.
        rig.packages.completeSource(rig.packages.heldSources.values[0])
        await flushed(rig)
        try #require(rig.runtime.prepareRequests.count == 1, "the older choice prepared glitch")
        #expect(await older.value == .unavailable(nil))

        rig.packages.holdSources(false)
        rig.settings.holdWrites(false)
        rig.settings.complete(rig.settings.heldRequests.values[0])
        await rig.answer(2)
        #expect(await newer.value == .prepared)
        await watcher.states.waitForCount(2)

        #expect(rig.runtime.prepareRequests.values.map(\.effect) == [Rig.bundledSource, Rig.otherSource])
        #expect(watcher.states.values.map(\.selection) == [bundled.id, other.id])
        await rig.stop(run)
    }

    @Test("a choice still being remembered when its run ends and the next one starts reads and prepares nothing")
    func choiceBeingRememberedAcrossARestart() async {
        let rig = Rig()
        let first = rig.start()
        await rig.answer(1)
        rig.settings.holdWrites()
        let choice = Task { await rig.subject.select(glitch.id) }  // remembered by the settings, though the call has not returned
        await rig.settings.heldRequests.waitForCount(1)
        await rig.stop(first)

        let second = rig.start()  // restores what the first run's choice left in the settings: glitch
        await rig.answer(2)  // and prepares it for itself
        rig.settings.complete(rig.settings.heldRequests.values[0])

        #expect(await choice.value == .unavailable(nil), "the choice belongs to the run before, which is over")
        #expect(
            rig.packages.sourceRequests.values == [bundled.id, glitch.id],
            "the choice read nothing: the second run's own read of glitch is the only one after the first run's")
        await rig.stop(second)
    }

    @Test("a run that was still restoring the persisted choice when the next one started leaves the choice to the next one")
    func restoreOfTheRunBefore() async throws {
        let rig = Rig(persisted: other.id)
        rig.settings.holdReads()
        let first = rig.start()
        await rig.settings.heldRequests.waitForCount(1)  // the first run asked for the choice, and was told: other
        await rig.settings.setSelectedEffect(glitch.id)  // then the user chose glitch
        first.cancel()
        let second = rig.start()
        await rig.settings.heldRequests.waitForCount(2)  // the second run asked after that, and will be told: glitch
        let watcher = rig.watch()
        rig.settings.complete(rig.settings.heldRequests.values[1])
        await rig.answer(1)
        await watcher.states.waitForCount(1)
        rig.settings.complete(rig.settings.heldRequests.values[0])  // the first run's answer comes late
        await first.value

        rig.packages.publish([bundled, glitch, other, later])
        await rig.packages.sourceRequests.waitForCount(2)
        try #require(rig.packages.sourceRequests.values == [glitch.id, glitch.id], "the first run's late answer made other the choice again")
        await watcher.states.waitForCount(2)

        #expect(watcher.states.values.map(\.selection) == [glitch.id, glitch.id])
        #expect(rig.runtime.prepareRequests.count == 1, "nothing was prepared again: the second run's source is the one the runtime has")
        await rig.stop(second)
    }
}
