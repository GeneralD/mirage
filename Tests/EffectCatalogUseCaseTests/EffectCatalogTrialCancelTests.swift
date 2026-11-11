import Domain
import TestSupport
import Testing

/// Cancelling the pending trial of a switched-off package effect: the wait for its cool-down ends when the choice moves to
/// another effect, when a listing falls back to the bundled effect, when its record is lifted by a re-enable, or when an edit
/// lifts it. A choice of the same effect again cancels nothing, and a trial that another effect's switch-off schedules
/// afterwards runs as usual. The cool-down is waited on the rig's `GatedClock`, so the test steps time by hand, and a cancelled
/// sleep is waited for on `cancelledSleepers` rather than on a fixed sleep.
@Suite("EffectCatalogUseCase trial cancel", .timeLimit(.minutes(1)))
struct EffectCatalogTrialCancelTests {
    private typealias Rig = EffectCatalogRig
    private let bundled = Rig.bundled
    private let glitch = Rig.glitch
    private let other = Rig.other
    private let glitchV2 = EffectSource(name: "Glitch", source: "glitch v2")

    /// Starts the run with `glitch` chosen, switches it off with five out-of-memory passes (which the bundled effect answers),
    /// and returns once its 300-second cool-down is waiting on the clock.
    private func switchedOff(_ rig: Rig) async -> Task<Void, Never> {
        let (run, _) = await rig.begin()
        rig.emit(.failure(.outOfMemory), of: Rig.glitchSource, times: 5)
        await rig.answer(2)
        await rig.clock.sleepers.waitForCount(1)
        return run
    }

    @Test("choosing another effect cancels the cool-down of the switched-off one, and that one is never tried again")
    func choosingAnotherEffectCancelsTheTrial() async {
        let rig = Rig(persisted: glitch.id)
        let run = await switchedOff(rig)
        let choice = Task { await rig.subject.select(other.id) }
        await rig.clock.cancelledSleepers.waitForCount(1)
        #expect(rig.clock.parkedCount == 0, "the sleep the cool-down was waiting on is cancelled")
        await rig.answer(3)
        #expect(await choice.value == .prepared, "the chosen effect is prepared")
        rig.clock.advance(by: .seconds(300))
        #expect(rig.runtime.prepareRequests.count == 3, "the cancelled cool-down prepares nothing for the effect no longer chosen")
        await rig.stop(run)
    }

    @Test("a listing that drops the switched-off effect cancels its cool-down as it falls back to the bundled effect")
    func fallbackCancelsTheTrial() async {
        let rig = Rig(persisted: glitch.id)
        let run = await switchedOff(rig)
        rig.packages.publish([bundled, other])
        await rig.clock.cancelledSleepers.waitForCount(1)
        _ = await rig.log.entries.waitFor(predicate: { $0.message.contains("is gone") })
        #expect(rig.clock.parkedCount == 0, "the sleep the cool-down was waiting on is cancelled")
        #expect(rig.runtime.prepareRequests.count == 2, "the bundled effect already stands in, so nothing is prepared")
        await rig.stop(run)
    }

    @Test("re-enabling the switched-off effect cancels its cool-down, and the choice runs it at once")
    func reenableCancelsTheTrial() async {
        let rig = Rig(persisted: glitch.id)
        let run = await switchedOff(rig)
        let reenabled = Task { await rig.subject.reenable(glitch.id) }
        await rig.clock.cancelledSleepers.waitForCount(1)
        #expect(rig.clock.parkedCount == 0, "the sleep the cool-down was waiting on is cancelled")
        await rig.answer(3)
        #expect(await reenabled.value == .prepared, "the re-enabled effect is prepared")
        rig.clock.advance(by: .seconds(300))
        #expect(rig.runtime.prepareRequests.count == 3, "the lifted cool-down prepares nothing more")
        await rig.stop(run)
    }

    @Test("an edit that lifts the switched-off chosen effect cancels its cool-down, and the edited source is prepared at once")
    func editCancelsTheTrial() async {
        let rig = Rig(persisted: glitch.id)
        let run = await switchedOff(rig)
        rig.packages.script(.success(glitchV2), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        await rig.clock.cancelledSleepers.waitForCount(1)
        #expect(rig.clock.parkedCount == 0, "the sleep the cool-down was waiting on is cancelled")
        let request = await rig.answer(3)
        #expect(request.effect == glitchV2, "the edited source is prepared, not the switched-off one")
        rig.clock.advance(by: .seconds(300))
        #expect(rig.runtime.prepareRequests.count == 3, "the lifted cool-down prepares nothing more")
        await rig.stop(run)
    }

    @Test("after a cancel, the switch-off of another effect schedules its own trial, which runs once its cool-down has run out")
    func trialAfterACancelIsScheduledAgain() async {
        let rig = Rig(persisted: glitch.id)
        let run = await switchedOff(rig)
        let choice = Task { await rig.subject.select(other.id) }
        await rig.clock.cancelledSleepers.waitForCount(1)
        await rig.answer(3)
        #expect(await choice.value == .prepared)
        rig.emit(.failure(.outOfMemory), of: Rig.otherSource, times: 5)
        await rig.answer(4)  // the bundled effect stands in for other
        await rig.clock.sleepers.waitForCount(2)
        #expect(rig.clock.parkedCount == 1, "only other's cool-down is waiting: glitch's was cancelled")
        rig.clock.advance(by: .seconds(300))
        let trial = await rig.answer(5)
        #expect(trial.effect == Rig.otherSource, "the trial that runs is other's own, from its switched-off source")
        await rig.stop(run)
    }

    @Test("choosing the switched-off effect again is refused and cancels nothing, so its cool-down still runs out into a trial")
    func choosingTheSameEffectCancelsNothing() async {
        let rig = Rig(persisted: glitch.id)
        let run = await switchedOff(rig)
        #expect(await rig.subject.select(glitch.id) == .unavailable(nil), "the switched-off effect is refused at the door")
        #expect(rig.clock.cancelledSleepers.count == 0, "the refused choice cancels no wait")
        #expect(rig.clock.parkedCount == 1, "the cool-down is still waiting")
        rig.clock.advance(by: .seconds(300))
        let trial = await rig.answer(3)
        #expect(trial.effect == Rig.glitchSource, "the trial prepares the switched-off source once the cool-down has run out")
        await rig.stop(run)
    }
}
