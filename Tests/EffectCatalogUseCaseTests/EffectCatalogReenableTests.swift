import Domain
import TestSupport
import Testing

/// Re-enabling a package effect that health switched off: its record is forgotten and written to the settings before the
/// effect is chosen again, so the choice runs; another switched-off effect's record is written back as it is; an effect with
/// no record is only chosen; a failing prepare answers as `select` does, and the record stays lifted. The runtime fake never
/// answers on its own, so each test answers every `prepare` by hand before its run stops; a missed answer shows as the
/// one-minute time limit.
@Suite("EffectCatalogUseCase re-enable", .timeLimit(.minutes(1)))
struct EffectCatalogReenableTests {
    private typealias Rig = EffectCatalogRig
    private let glitch = Rig.glitch
    private let other = Rig.other

    @Test("re-enabling a switched-off effect writes the settings without its record, then runs it again and answers prepared")
    func reenableLiftsTheRecordAndRunsTheEffect() async {
        let rig = Rig(persisted: glitch.id)
        let (run, watcher) = await rig.begin()
        rig.emit(.failure(.accessRevoked), of: Rig.glitchSource)
        await rig.answer(2)
        _ = await rig.firstDisabled(in: watcher)

        // The states published before the re-enable still list the switch-off, so the state after it is awaited by count.
        let shownBefore = watcher.states.count
        let reenabled = Task { await rig.subject.reenable(glitch.id) }
        await rig.settings.disabledWrites.waitForCount(2)
        #expect(rig.settings.disabledWrites.last == [], "the record is gone from the settings before the effect runs again")

        let request = await rig.answer(3)
        #expect(request.effect == Rig.glitchSource, "the choice is prepared from the glitch's source")
        #expect(await reenabled.value == .prepared)

        await watcher.states.waitForCount(shownBefore + 1)
        let shown = watcher.states.last
        #expect(shown?.disabled == [:], "the menu no longer shows the switch-off")
        #expect(shown?.selection == glitch.id)
        #expect(shown?.outcome == .prepared)
        await rig.stop(run)
    }

    @Test("re-enabling one effect writes back the record of the other switched-off effect as it is")
    func reenableKeepsTheOtherRecord() async {
        let rig = Rig(persisted: glitch.id)
        let (run, watcher) = await rig.begin()
        rig.emit(.failure(.accessRevoked), of: Rig.glitchSource)
        await rig.answer(2)
        _ = await rig.firstDisabled(in: watcher)

        let choice = Task { await rig.subject.select(other.id) }
        await rig.answer(3)
        #expect(await choice.value == .prepared)
        rig.emit(.failure(.accessRevoked), of: Rig.otherSource)
        await rig.answer(4)
        // The bundled effect answered in place of the other one: the state that shows both switch-offs is out once it is published.
        _ = await watcher.states.waitFor(predicate: { $0.disabled.count == 2 })

        let reenabled = Task { await rig.subject.reenable(glitch.id) }
        await rig.settings.disabledWrites.waitForCount(3)
        #expect(
            rig.settings.disabledWrites.last == [record(other.id, Rig.otherSource, .failure(.accessRevoked), retries: false)],
            "only the glitch's record is lifted; the other's stays written")
        await rig.answer(5)
        #expect(await reenabled.value == .prepared)
        await rig.stop(run)
    }

    @Test("re-enabling an effect with no record writes nothing and chooses it, as select does")
    func reenableWithoutARecordIsASelect() async {
        let rig = Rig(persisted: glitch.id)
        let (run, _) = await rig.begin()
        let reenabled = Task { await rig.subject.reenable(other.id) }
        let request = await rig.answer(2)
        #expect(request.effect == Rig.otherSource, "the other effect is prepared from its source")
        #expect(await reenabled.value == .prepared)
        #expect(rig.settings.disabledWrites.count == 0, "no record was lifted, so the settings are not written")
        await rig.stop(run)
    }

    @Test("a re-enabled effect that fails to prepare answers the failure as select does, and its record stays lifted")
    func reenableAnswersAFailureLikeSelect() async {
        let rig = Rig(persisted: glitch.id)
        let (run, watcher) = await rig.begin()
        rig.emit(.failure(.accessRevoked), of: Rig.glitchSource)
        await rig.answer(2)
        _ = await rig.firstDisabled(in: watcher)

        let reenabled = Task { await rig.subject.reenable(glitch.id) }
        await rig.settings.disabledWrites.waitForCount(2)
        await rig.answer(3, with: .failure(.timeout))
        #expect(await reenabled.value == .failed(.timeout))
        #expect(rig.settings.disabledWrites.last == [], "the failure is shown, and the record is not written back")
        let shown = await watcher.states.waitFor(predicate: { $0.outcome == .failed(.timeout) })
        #expect(shown?.disabled == [:], "the menu shows the failure, not the switch-off")
        await rig.stop(run)
    }

    // MARK: - Helpers

    private func record(_ id: EffectID, _ source: EffectSource, _ reason: EffectDisableReason, retries: Bool) -> DisabledEffectRecord {
        DisabledEffectRecord(id: id, fingerprint: .of(source), reason: reason, retriesAutomatically: retries)
    }
}
