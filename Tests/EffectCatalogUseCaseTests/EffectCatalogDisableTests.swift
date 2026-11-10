import Domain
import TestSupport
import Testing

/// What a switched-off package effect does: its record is written to the settings before anything else, the bundled effect
/// is prepared in its place, the menu shows the switched-off choice with its reason once that has answered, and a choice made
/// meanwhile wins over the fallback. The runtime fake never answers on its own, so each test answers the bundled `prepare` by
/// hand (and completes any parked write) before its run stops; a missed answer shows as the one-minute time limit.
@Suite("EffectCatalogUseCase disables a failing effect", .timeLimit(.minutes(1)))
struct EffectCatalogDisableTests {
    private typealias Rig = EffectCatalogRig
    private let bundled = Rig.bundled
    private let glitch = Rig.glitch
    private let other = Rig.other

    // MARK: - The record

    @Test(
        "a failing package effect is written to the settings as disabled, with its failure kind, and retries on its own only when a retry cannot hang",
        arguments: [
            (EffectFailure.accessRevoked, 1, EffectFailureKind.accessRevoked, false),
            (.timeout, 5, .timeout, false),
            (.pageFault, 5, .pageFault, false),
            (.outOfMemory, 5, .outOfMemory, true),
            (.unknown(code: 7), 5, .unknown, true),
        ])
    func failureRecordIsWritten(failure: EffectFailure, times: Int, kind: EffectFailureKind, retries: Bool) async {
        let rig = Rig(persisted: glitch.id)
        let (run, _) = await rig.begin()
        rig.emit(.failure(failure), of: Rig.glitchSource, times: times)
        await rig.answer(2)
        await rig.settings.disabledWrites.waitForCount(1)
        #expect(rig.settings.disabledWrites.values == [[record(glitch.id, Rig.glitchSource, .failure(kind), retries: retries)]])
        await rig.stop(run)
    }

    @Test("thirty passes over the budget switch a package effect off, and the record says it retries on its own")
    func overBudgetRecordRetries() async {
        let rig = Rig(persisted: glitch.id)
        let (run, _) = await rig.begin()
        rig.emit(.success(Rig.slow), of: Rig.glitchSource, times: 30)
        await rig.answer(2)
        await rig.settings.disabledWrites.waitForCount(1)
        #expect(rig.settings.disabledWrites.values == [[record(glitch.id, Rig.glitchSource, .overBudget, retries: true)]])
        await rig.stop(run)
    }

    // MARK: - The order of the switch-off

    @Test("a switched-off effect is written to the settings before the bundled effect is prepared")
    func recordIsWrittenBeforeTheFallback() async {
        let rig = Rig(persisted: glitch.id)
        let (run, _) = await rig.begin()
        rig.settings.holdDisabledWrites()
        rig.emit(.failure(.accessRevoked), of: Rig.glitchSource)
        await rig.settings.heldRequests.waitForCount(1)
        #expect(rig.runtime.prepareRequests.count == 1, "the bundled effect waits until the record is written")
        #expect(rig.settings.complete(rig.settings.heldRequests.values[0]))
        let request = await rig.answer(2)
        #expect(request.effect == Rig.bundledSource)
        await rig.stop(run)
    }

    // MARK: - The state and the log

    @Test("once the bundled effect has answered, the menu shows the switched-off effect as chosen, with its reason and no outcome")
    func fallbackStateShowsTheSwitchedOffChoice() async {
        let rig = Rig(persisted: glitch.id)
        let (run, watcher) = await rig.begin()
        rig.emit(.failure(.accessRevoked), of: Rig.glitchSource)
        await rig.answer(2)
        let state = await watcher.states.waitFor(predicate: { !$0.disabled.isEmpty })
        #expect(state?.selection == glitch.id, "the choice is not moved to the bundled effect")
        #expect(state?.disabled == [glitch.id: .failure(.accessRevoked)])
        #expect(state?.outcome == nil, "the bundled effect's answer is not the chosen effect's outcome")
        await rig.stop(run)
    }

    @Test("a switched-off effect is logged once, with its reason and the bundled effect it falls back to")
    func switchOffIsLoggedOnce() async {
        let rig = Rig(persisted: glitch.id)
        let (run, watcher) = await rig.begin()
        rig.emit(.failure(.accessRevoked), of: Rig.glitchSource)
        await rig.answer(2)
        _ = await watcher.states.waitFor(predicate: { !$0.disabled.isEmpty })
        let lines = rig.log.messages(in: .effect).filter { $0.contains("disabled") }
        #expect(lines == ["effect 'Glitch' disabled (accessRevoked); back to 'Chromatic Grain'"])
        await rig.stop(run)
    }

    // MARK: - A choice made meanwhile

    @Test("a choice made while the switch-off record is being written wins, and the bundled effect is not prepared over it")
    func choiceMadeMeanwhileWins() async {
        let rig = Rig(persisted: glitch.id)
        let (run, _) = await rig.begin()
        rig.settings.holdDisabledWrites()
        rig.emit(.failure(.accessRevoked), of: Rig.glitchSource)
        await rig.settings.heldRequests.waitForCount(1)
        let parked = rig.settings.heldRequests.values[0]
        let choice = Task { await rig.subject.select(other.id) }
        await rig.answer(2)
        _ = await choice.value
        #expect(rig.settings.complete(parked))
        // A sentinel: the other effect is the one held now, so its final failure is written after the first record has returned.
        rig.emit(.failure(.accessRevoked), of: Rig.otherSource)
        await rig.settings.heldRequests.waitForCount(2)
        #expect(rig.runtime.prepareRequests.count == 2, "the first switch-off prepared nothing: the choice had moved on")
        // Cleanup: the sentinel's record is parked, and the fallback it causes answers before the run stops.
        #expect(rig.settings.complete(rig.settings.heldRequests.values[1]))
        await rig.answer(3)
        await rig.stop(run)
    }

    // MARK: - Helpers

    private func record(_ id: EffectID, _ source: EffectSource, _ reason: EffectDisableReason, retries: Bool) -> DisabledEffectRecord {
        DisabledEffectRecord(id: id, fingerprint: .of(source), reason: reason, retriesAutomatically: retries)
    }
}
