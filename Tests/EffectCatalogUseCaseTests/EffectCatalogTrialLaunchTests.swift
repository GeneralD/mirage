import Domain
import TestSupport
import Testing

/// A switched-off choice that asked to retry is not left switched off for good across a restart: the cool-down it was
/// switched off with starts again at the launch, and its one trial runs once that wait has run out. The records that do not
/// retry, and the records of effects the menu does not choose, reserve no trial at launch. The cool-down is waited on the
/// rig's `GatedClock`, so the test steps time by hand; the runtime fake answers each `prepare` by hand.
@Suite("EffectCatalogUseCase trial at launch", .timeLimit(.minutes(1)))
struct EffectCatalogTrialLaunchTests {
    private typealias Rig = EffectCatalogRig
    private let glitch = Rig.glitch
    private let other = Rig.other

    @Test("a switched-off choice that retries is prepared again 300 seconds after the launch, and not before")
    func retryingChoiceIsTrialedAfterTheLaunchCoolDown() async {
        let rig = Rig(persisted: glitch.id, disabled: [record(glitch.id, Rig.glitchSource, .failure(.outOfMemory), retries: true)])
        let (run, _) = await rig.begin()
        await rig.clock.sleepers.waitForCount(1)
        #expect(rig.clock.sleepers.values == [.seconds(300)], "the cool-down is waited from the launch, at the base length")
        rig.clock.advance(by: .seconds(299))
        #expect(rig.clock.parkedCount == 1, "the cool-down is still running at 299 seconds")
        #expect(rig.runtime.prepareRequests.count == 1, "nothing is prepared before the cool-down ends")
        rig.clock.advance(by: .seconds(1))
        let trial = await rig.answer(2)
        #expect(trial.effect == Rig.glitchSource, "the trial prepares the switched-off source")
        #expect(rig.log.messages(in: .effect).last == "effect 'Glitch' retrying")
        await rig.stop(run)
    }

    @Test("a trial that passes after the launch lifts the switch-off and writes the settings without the record")
    func passingTrialAfterTheLaunchLiftsTheSwitchOff() async {
        let rig = Rig(persisted: glitch.id, disabled: [record(glitch.id, Rig.glitchSource, .failure(.outOfMemory), retries: true)])
        let (run, watcher) = await rig.begin()
        await rig.clock.sleepers.waitForCount(1)
        rig.clock.advance(by: .seconds(300))
        await rig.answer(2)
        rig.emit(.success(Rig.fast), of: Rig.glitchSource)
        await rig.settings.disabledWrites.waitForCount(1)
        #expect(rig.settings.disabledWrites.last == [], "the record is forgotten once the launch trial has passed")
        let cleared = await watcher.states.waitFor(predicate: { $0.disabled.isEmpty })
        #expect(cleared?.disabled == [:], "the menu no longer shows the switch-off")
        await rig.stop(run)
    }

    @Test("a switched-off choice whose record does not retry reserves no trial at the launch")
    func nonRetryingChoiceReservesNoTrialAtLaunch() async {
        let rig = Rig(persisted: glitch.id, disabled: [record(glitch.id, Rig.glitchSource, .failure(.timeout), retries: false)])
        let (run, _) = await rig.begin()
        #expect(rig.clock.sleepers.count == 0, "a timed-out effect is never retried on its own, so nothing is waited for")
        #expect(rig.clock.parkedCount == 0)
        await rig.stop(run)
    }

    @Test("a retrying record of an effect the menu does not choose reserves no trial at the launch")
    func unchosenRetryingRecordReservesNoTrialAtLaunch() async {
        let rig = Rig(persisted: other.id, disabled: [record(glitch.id, Rig.glitchSource, .failure(.outOfMemory), retries: true)])
        let (run, _) = await rig.begin()
        #expect(rig.clock.sleepers.count == 0, "the glitch is not the chosen effect, so no trial of it is waited for")
        #expect(rig.runtime.prepareRequests.values.first?.effect == Rig.otherSource, "the chosen effect is prepared as it is")
        await rig.stop(run)
    }

    // MARK: - Helpers

    private func record(_ id: EffectID, _ source: EffectSource, _ reason: EffectDisableReason, retries: Bool) -> DisabledEffectRecord {
        DisabledEffectRecord(id: id, fingerprint: .of(source), reason: reason, retriesAutomatically: retries)
    }
}
