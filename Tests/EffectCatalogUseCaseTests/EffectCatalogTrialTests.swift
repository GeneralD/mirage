import Domain
import TestSupport
import Testing

/// The one-pass trial after a cool-down: a switched-off package effect that asked to retry is prepared again once its cool-down
/// has run out, a trial pass within budget lifts the switch-off, a trial that fails doubles the next cool-down, and a run that
/// ends cancels the wait. The cool-down is waited on the rig's `GatedClock`, so the test steps time by hand. The runtime fake
/// answers each `prepare` by hand; a missed answer shows as the one-minute time limit.
@Suite("EffectCatalogUseCase trial after cool-down", .timeLimit(.minutes(1)))
struct EffectCatalogTrialTests {
    private typealias Rig = EffectCatalogRig
    private let glitch = Rig.glitch

    /// Starts the run with `glitch` chosen, switches it off with five out-of-memory passes (which the bundled effect answers),
    /// and returns once its 300-second cool-down is waiting on the clock.
    private func switchedOff(_ rig: Rig) async -> Task<Void, Never> {
        let (run, _) = await rig.begin()
        rig.emit(.failure(.outOfMemory), of: Rig.glitchSource, times: 5)
        await rig.answer(2)
        await rig.clock.sleepers.waitForCount(1)
        return run
    }

    @Test("a package effect switched off for out-of-memory is prepared again once its 300-second cool-down has run out")
    func coolDownLastsFiveMinutes() async {
        let rig = Rig(persisted: glitch.id)
        let run = await switchedOff(rig)
        rig.clock.advance(by: .seconds(299))
        #expect(rig.clock.parkedCount == 1, "the cool-down is still running at 299 seconds")
        #expect(rig.runtime.prepareRequests.count == 2, "nothing is prepared before the cool-down ends")
        rig.clock.advance(by: .seconds(1))
        let trial = await rig.answer(3)
        #expect(trial.effect == Rig.glitchSource, "the trial prepares the switched-off source")
        #expect(rig.log.messages(in: .effect).last == "effect 'Glitch' retrying")
        await rig.stop(run)
    }

    @Test("a trial pass within budget lifts the switch-off and writes the settings without the record")
    func passingTrialLiftsSwitchOff() async {
        let rig = Rig(persisted: glitch.id)
        let run = await switchedOff(rig)
        rig.clock.advance(by: .seconds(300))
        await rig.answer(3)
        rig.emit(.success(Rig.fast), of: Rig.glitchSource)
        await rig.settings.disabledWrites.waitForCount(2)
        #expect(rig.settings.disabledWrites.values.last == [], "the record is forgotten once the trial has passed")
        #expect(rig.runtime.prepareRequests.count == 3, "a passing trial prepares nothing more")
        await rig.stop(run)
    }

    @Test("a trial that fails again doubles the cool-down before the next trial")
    func failedTrialDoublesCoolDown() async {
        let rig = Rig(persisted: glitch.id)
        let run = await switchedOff(rig)
        rig.clock.advance(by: .seconds(300))
        await rig.answer(3)
        rig.emit(.failure(.outOfMemory), of: Rig.glitchSource)
        let fallback = await rig.answer(4)
        #expect(fallback.effect == Rig.bundledSource, "the bundled effect stands in for the trial that failed")
        await rig.clock.sleepers.waitForCount(2)
        #expect(rig.clock.sleepers.values == [.seconds(300), .seconds(900)], "the second wait is 600 seconds, from the failure at 300 seconds")
        rig.clock.advance(by: .seconds(599))
        #expect(rig.clock.parkedCount == 1, "the doubled cool-down is still running at 899 seconds")
        #expect(rig.runtime.prepareRequests.count == 4)
        rig.clock.advance(by: .seconds(1))
        let trial = await rig.answer(5)
        #expect(trial.effect == Rig.glitchSource)
        await rig.stop(run)
    }

    @Test("a trial of an effect that timed out is never scheduled, and neither is one that faulted")
    func hangingEffectGetsNoTrial() async {
        let rig = Rig(persisted: glitch.id)
        let (run, watcher) = await rig.begin()
        rig.emit(.failure(.timeout), of: Rig.glitchSource, times: 5)
        await rig.answer(2)
        // A sentinel: the bundled effect's access revocation is counted after the glitch's switch-off, and it raises the GPU flag.
        rig.emit(.failure(.accessRevoked), of: Rig.bundledSource)
        _ = await watcher.states.waitFor(predicate: { $0.isGPUUnavailable })
        #expect(rig.clock.sleepers.count == 0, "a timeout is not retried on its own")
        #expect(rig.clock.parkedCount == 0)
        await rig.stop(run)
    }

    @Test("a choice of a switched-off effect is refused while its cool-down runs")
    func choiceIsRefusedDuringCoolDown() async {
        let rig = Rig(persisted: glitch.id)
        let run = await switchedOff(rig)
        #expect(await rig.subject.select(glitch.id) == .unavailable(nil))
        await rig.stop(run)
    }

    @Test("a listing that still has a trial's effect ready does not move the choice back to the bundled effect")
    func listingKeepsTrialingEffectChosen() async {
        let rig = Rig(persisted: glitch.id)
        let run = await switchedOff(rig)
        rig.clock.advance(by: .seconds(300))
        await rig.runtime.prepareRequests.waitForCount(3)
        // The reads of the listing below: one that checks the switched-off source, and one that reads the chosen one.
        let looked = rig.packages.sourceRequests.count
        rig.packages.publish([Rig.bundled, Rig.glitch, Rig.other])
        await rig.packages.sourceRequests.waitForCount(looked + 2)
        #expect(rig.runtime.prepareRequests.count == 3, "the listing prepares nothing: the trial's effect is still chosen")
        // Once the listing drops the effect, the chosen package falls back to the bundled one, as any gone package does.
        rig.packages.publish([Rig.bundled, Rig.other])
        let fallback = await rig.answer(4)
        #expect(fallback.effect == Rig.bundledSource, "a trial's effect that goes away falls back to the bundled effect")
        #expect(rig.log.messages(in: .effect).contains("effect 'Glitch' is gone; back to 'Chromatic Grain'"))
        await rig.answer(3)
        await rig.stop(run)
    }

    @Test("stopping the run cancels the cool-down that is waiting, and no trial is prepared after it")
    func stopCancelsCoolDown() async {
        let rig = Rig(persisted: glitch.id)
        let run = await switchedOff(rig)
        await rig.stop(run)
        await rig.clock.cancelledSleepers.waitForCount(1)
        #expect(rig.clock.parkedCount == 0, "the sleep the cool-down was waiting on is cancelled")
        rig.clock.advance(by: .seconds(300))
        #expect(rig.runtime.prepareRequests.count == 2, "no trial is prepared after the run has ended")
    }
}
