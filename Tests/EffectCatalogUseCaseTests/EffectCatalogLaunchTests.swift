import Domain
import TestSupport
import Testing

/// What the records of switched-off effects do at launch: the settings hold them from the last run, and the first listing
/// starts from them. A switched-off choice is never prepared, so the bundled effect stands in for it from the first `prepare`
/// on; the menu shows every switched-off effect with its reason; and a record of the bundled effect is read away. The runtime
/// fake never answers on its own, so each test answers the `prepare` it expects by hand, and stops its run after that.
@Suite("EffectCatalogUseCase disabled set at launch", .timeLimit(.minutes(1)))
struct EffectCatalogLaunchTests {
    private typealias Rig = EffectCatalogRig
    private let bundled = Rig.bundled
    private let glitch = Rig.glitch
    private let other = Rig.other

    @Test("a switched-off choice stays off at launch: the bundled effect is prepared first, and the menu shows the record's reason")
    func switchedOffChoiceStaysOffAtLaunch() async {
        let rig = Rig(persisted: glitch.id, disabled: [record(glitch.id, Rig.glitchSource, .failure(.timeout), retries: false)])
        let watcher = rig.watch()
        let run = rig.start()
        let request = await rig.answer(1)
        #expect(request.effect == Rig.bundledSource, "the bundled effect is prepared in place of the switched-off choice")
        await watcher.states.waitForCount(1)
        let first = watcher.states.values.first
        #expect(first?.selection == glitch.id, "the choice is still the user's")
        #expect(first?.disabled == [glitch.id: .failure(.timeout)], "the record's reason is shown")
        #expect(first?.outcome == nil, "nothing has been prepared for the choice")
        #expect(rig.settings.disabledWrites.count == 0, "the record is read, and never written back")
        #expect(rig.settings.writes.count == 0, "the choice is not remembered again")
        await rig.stop(run)
    }

    @Test("a record of another effect is shown at launch, while the persisted choice is prepared as it is")
    func otherEffectsRecordIsShownAtLaunch() async {
        let rig = Rig(persisted: glitch.id, disabled: [record(other.id, Rig.otherSource, .failure(.timeout), retries: false)])
        let watcher = rig.watch()
        let run = rig.start()
        let request = await rig.answer(1)
        #expect(request.effect == Rig.glitchSource, "the persisted choice is not switched off, so its source is prepared")
        await watcher.states.waitForCount(1)
        #expect(
            watcher.states.values.first?.disabled == [other.id: .failure(.timeout)], "a switched-off effect the menu does not choose is shown too")
        await rig.stop(run)
    }

    @Test("a record of the bundled effect is read away at launch, so no effect is shown switched off")
    func bundledRecordIsReadAway() async {
        let rig = Rig(persisted: glitch.id, disabled: [record(bundled.id, Rig.bundledSource, .failure(.timeout), retries: false)])
        let watcher = rig.watch()
        let run = rig.start()
        let request = await rig.answer(1)
        #expect(request.effect == Rig.glitchSource, "the persisted choice is not switched off, so its source is prepared")
        await watcher.states.waitForCount(1)
        #expect(watcher.states.values.first?.disabled == [:], "a record of the bundled effect says nothing about the launch")
        await rig.stop(run)
    }

    @Test("a switched-off choice the listing no longer has falls back to the bundled effect, and its record is kept as it is")
    func goneChoiceFallsBackAndKeepsItsRecord() async {
        let rig = Rig(
            entries: [bundled, other], persisted: glitch.id,
            disabled: [record(glitch.id, Rig.glitchSource, .failure(.timeout), retries: false)])
        let watcher = rig.watch()
        let run = rig.start()
        let request = await rig.answer(1)
        #expect(request.effect == Rig.bundledSource, "the listing has no choice to prepare, so the bundled effect stands in")
        await watcher.states.waitForCount(1)
        #expect(rig.settings.disabledWrites.count == 0, "a record of an effect the listing no longer has is kept as it is")
        await rig.stop(run)
    }

    @Test("two records of one effect do not trap the launch, and the later record is the one shown")
    func laterRecordOfTheSameEffectWins() async {
        let rig = Rig(
            persisted: glitch.id,
            disabled: [
                record(glitch.id, Rig.glitchSource, .failure(.timeout), retries: false),
                record(glitch.id, Rig.glitchSource, .overBudget, retries: true),
            ])
        let watcher = rig.watch()
        let run = rig.start()
        let request = await rig.answer(1)
        #expect(request.effect == Rig.bundledSource, "the switched-off choice is replaced by the bundled effect")
        await watcher.states.waitForCount(1)
        #expect(watcher.states.values.first?.disabled == [glitch.id: .overBudget], "the record that comes last is the one shown")
        await rig.stop(run)
    }

    // MARK: - Helpers

    private func record(_ id: EffectID, _ source: EffectSource, _ reason: EffectDisableReason, retries: Bool) -> DisabledEffectRecord {
        DisabledEffectRecord(id: id, fingerprint: .of(source), reason: reason, retriesAutomatically: retries)
    }
}
