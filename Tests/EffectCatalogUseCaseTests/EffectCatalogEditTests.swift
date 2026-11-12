import Domain
import TestSupport
import Testing

/// Editing a package effect that health switched off: the listing that shows the edit lifts the switch-off, so the next choice
/// runs the edited source. An unchanged source keeps its record and writes nothing, an effect nobody chose is lifted without a
/// prepare, a peek of its files leaves a choice that waits for its own read current, and choosing the switched-off effect reads
/// nothing. The runtime fake never answers on its own, and the fakes ignore cancellation: each test answers every `prepare` and
/// completes every parked read before its run stops.
@Suite("EffectCatalogUseCase edit re-enables", .timeLimit(.minutes(1)))
struct EffectCatalogEditTests {
    private typealias Rig = EffectCatalogRig
    private let bundled = Rig.bundled
    private let glitch = Rig.glitch
    private let other = Rig.other
    private let glitchV2 = EffectSource(name: "Glitch", source: "glitch v2")
    private let otherV2 = EffectSource(name: "Other", source: "other v2")

    @Test("a listing that shows a switched-off effect's edited source lifts its switch-off, and the next choice runs the edited source")
    func editedEffectIsLiftedAndRuns() async {
        let rig = Rig(persisted: glitch.id)
        let (run, watcher) = await rig.begin()
        rig.emit(.failure(.accessRevoked), of: Rig.glitchSource)
        await rig.answer(2)  // the bundled effect stands in for glitch
        _ = await rig.firstDisabled(in: watcher)

        rig.packages.script(.success(glitchV2), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        await rig.settings.disabledWrites.waitForCount(2)
        #expect(rig.settings.disabledWrites.last == [], "the record of the switched-off source is gone from the settings")

        let request = await rig.answer(3)
        #expect(request.effect == glitchV2, "the runtime is prepared with the edited source")
        let shown = await watcher.states.waitFor(predicate: { $0.disabled.isEmpty && $0.outcome == .prepared })
        #expect(shown?.selection == glitch.id, "the menu shows the edited effect as chosen and prepared")
        await rig.stop(run)
    }

    @Test("a listing that shows a switched-off effect's unchanged source keeps its record and writes nothing")
    func unchangedSourceKeepsItsRecord() async {
        let rig = Rig(persisted: glitch.id)
        let (run, watcher) = await rig.begin()
        rig.emit(.failure(.accessRevoked), of: Rig.glitchSource)
        await rig.answer(2)
        _ = await rig.firstDisabled(in: watcher)

        rig.packages.publish([bundled, glitch, other])  // the same files: the record stays
        rig.packages.publish([bundled, other])  // a listing without glitch is reconciled only after the first one has returned
        _ = await rig.log.entries.waitFor(predicate: { $0.message.contains("is gone") })
        #expect(rig.settings.disabledWrites.count == 1, "the unchanged record was neither lifted nor written again")
        await rig.stop(run)
    }

    @Test("a listing that shows an unchosen switched-off effect edited lifts it without preparing anything for it")
    func uncheckedEditedEffectIsLiftedWithoutAPrepare() async {
        let rig = Rig(persisted: glitch.id)
        let (run, watcher) = await rig.begin()
        rig.emit(.failure(.accessRevoked), of: Rig.glitchSource)
        await rig.answer(2)
        _ = await rig.firstDisabled(in: watcher)
        let choice = Task { await rig.subject.select(other.id) }
        await rig.answer(3)
        #expect(await choice.value == .prepared)

        rig.packages.script(.success(glitchV2), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        await rig.settings.disabledWrites.waitForCount(2)
        #expect(rig.settings.disabledWrites.last == [], "the edited, unchosen effect is lifted")
        #expect(rig.runtime.prepareRequests.count == 3, "nothing was prepared for the effect that was not chosen")

        rig.packages.script(.success(otherV2), for: other.id)
        rig.packages.publish([bundled, glitch, other])
        let request = await rig.answer(4)
        #expect(request.effect == otherV2, "the chosen effect is the one prepared next, from its own source")
        await rig.stop(run)
    }

    @Test("a peek at a switched-off effect's files does not make a choice that waits for its own read stale")
    func peekDoesNotStaleAWaitingChoice() async {
        let rig = Rig(persisted: glitch.id)
        let (run, watcher) = await rig.begin()
        rig.emit(.failure(.accessRevoked), of: Rig.glitchSource)
        await rig.answer(2)
        _ = await rig.firstDisabled(in: watcher)

        rig.packages.holdSources()
        let choice = Task { await rig.subject.select(other.id) }
        await rig.packages.heldSources.waitForCount(1)  // the choice reads other's files
        rig.packages.publish([bundled, glitch, other])  // the listing peeks at glitch's files, which are unchanged
        await rig.packages.heldSources.waitForCount(2)
        let reads = rig.packages.heldSources.values
        #expect(reads[1].effect == glitch.id, "the listing peeked at the switched-off glitch")

        rig.packages.completeSource(reads[0])
        await rig.answer(3)
        #expect(await choice.value == .prepared, "the choice was not made stale by the peek")

        rig.packages.completeSource(reads[1])  // unchanged: nothing is lifted
        await rig.packages.heldSources.waitForCount(3)  // the listing then reads other's files as the chosen effect
        rig.packages.completeSource(rig.packages.heldSources.values[2])
        rig.packages.holdSources(false)
        await rig.stop(run)

        #expect(rig.runtime.prepareRequests.values.map(\.effect) == [Rig.glitchSource, Rig.bundledSource, Rig.otherSource])
        #expect(rig.settings.disabledWrites.count == 1, "the peek lifted nothing")
    }

    @Test("choosing a switched-off effect is refused and reads nothing, so an edit of its files lifts nothing before a listing shows it")
    func choosingASwitchedOffEffectReleasesNothing() async {
        let rig = Rig(persisted: glitch.id)
        let (run, watcher) = await rig.begin()
        rig.emit(.failure(.accessRevoked), of: Rig.glitchSource)
        await rig.answer(2)
        _ = await rig.firstDisabled(in: watcher)

        rig.packages.script(.success(glitchV2), for: glitch.id)
        let reads = rig.packages.sourceRequests.count
        let outcome = await rig.subject.select(glitch.id)
        #expect(outcome == .unavailable(nil), "the switched-off effect is refused at the door")
        #expect(rig.packages.sourceRequests.count == reads, "the choice read no files")
        #expect(rig.settings.disabledWrites.count == 1, "the choice lifted nothing")
        await rig.stop(run)
    }
}
