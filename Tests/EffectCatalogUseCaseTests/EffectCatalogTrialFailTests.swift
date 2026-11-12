import Domain
import TestSupport
import Testing

/// A trial after a cool-down that fails. A pass that fails or runs over budget during the trial switches the effect off again
/// and doubles the next cool-down, unless a retry would hang (then nothing is tried again). A trial the runtime cannot prepare
/// at all counts no pass: the record and the policy stay as they were, the bundled effect stands in once more, and the next
/// trial waits the base cool-down. The waits are on the rig's `GatedClock`, whose sleepers hold absolute deadlines from the
/// start of the run.
@Suite("EffectCatalogUseCase failed trial", .timeLimit(.minutes(1)))
struct EffectCatalogTrialFailTests {
    private typealias Rig = EffectCatalogRig
    private let glitch = Rig.glitch

    /// Starts the run with `glitch` chosen, switches it off with five out-of-memory passes (which the bundled effect answers),
    /// and returns once its 300-second cool-down is waiting on the clock.
    private func switchedOff(_ rig: Rig) async -> (run: Task<Void, Never>, watcher: Rig.Watcher) {
        let (run, watcher) = await rig.begin()
        rig.emit(.failure(.outOfMemory), of: Rig.glitchSource, times: 5)
        await rig.answer(2)
        await rig.clock.sleepers.waitForCount(1)
        return (run, watcher)
    }

    @Test("a trial that cannot be prepared hands the bundled effect back in its place")
    func failedPrepareHandsBackBundled() async {
        let rig = Rig(persisted: glitch.id)
        let (run, _) = await switchedOff(rig)
        rig.clock.advance(by: .seconds(300))
        let refused = await rig.answer(3, with: .failure(.compileFailed))
        #expect(refused.effect == Rig.glitchSource, "the trial prepares the switched-off source")
        let fallback = await rig.answer(4)
        #expect(fallback.effect == Rig.bundledSource, "the bundled effect is prepared in place of the trial that was refused")
        await rig.clock.sleepers.waitForCount(2)
        await rig.stop(run)
    }

    @Test("a trial that cannot be prepared writes no record, and the menu keeps the switch-off reason")
    func failedPrepareWritesNoRecord() async {
        let rig = Rig(persisted: glitch.id)
        let (run, watcher) = await switchedOff(rig)
        rig.clock.advance(by: .seconds(300))
        await rig.answer(3, with: .failure(.unknown(code: 1)))
        await rig.answer(4)
        await rig.clock.sleepers.waitForCount(2)
        #expect(rig.settings.disabledWrites.count == 1, "only the switch-off wrote the record: a trial that is not prepared counts no pass")
        #expect(watcher.states.values.last?.disabled[glitch.id] == .failure(.outOfMemory), "the menu keeps the reason of the switch-off")
        await rig.stop(run)
    }

    @Test("a trial that cannot be prepared is tried again after the base 300-second cool-down, not a doubled one")
    func failedPrepareKeepsBaseCoolDown() async {
        let rig = Rig(persisted: glitch.id)
        let (run, _) = await switchedOff(rig)
        rig.clock.advance(by: .seconds(300))
        await rig.answer(3, with: .failure(.unknown(code: 1)))
        await rig.answer(4)
        await rig.clock.sleepers.waitForCount(2)
        #expect(rig.clock.sleepers.values == [.seconds(300), .seconds(600)], "the next wait is 300 seconds, from the refused trial at 300")
        rig.clock.advance(by: .seconds(299))
        #expect(rig.clock.parkedCount == 1, "the cool-down is still running at 599 seconds")
        #expect(rig.runtime.prepareRequests.count == 4, "nothing is prepared before the cool-down ends")
        rig.clock.advance(by: .seconds(1))
        let trial = await rig.answer(5)
        #expect(trial.effect == Rig.glitchSource, "the next trial prepares the switched-off source")
        // The policy counted nothing for the refused trial, so this failing pass is the first failed trial: its wait is 600 seconds.
        rig.emit(.failure(.outOfMemory), of: Rig.glitchSource)
        await rig.answer(6)
        await rig.clock.sleepers.waitForCount(3)
        #expect(rig.clock.sleepers.values == [.seconds(300), .seconds(600), .seconds(1200)], "the wait after the failed pass is 600 seconds")
        await rig.stop(run)
    }

    @Test("each trial that fails by a pass doubles the cool-down before the next one: 600 seconds, then 1200")
    func failedTrialsDoubleCoolDown() async {
        let rig = Rig(persisted: glitch.id)
        let (run, _) = await switchedOff(rig)
        rig.clock.advance(by: .seconds(300))
        await rig.answer(3)
        rig.emit(.failure(.outOfMemory), of: Rig.glitchSource)
        await rig.answer(4)
        await rig.clock.sleepers.waitForCount(2)
        rig.clock.advance(by: .seconds(599))
        #expect(rig.clock.parkedCount == 1, "the doubled cool-down is still running at 899 seconds")
        #expect(rig.runtime.prepareRequests.count == 4, "nothing is prepared before the doubled cool-down ends")
        rig.clock.advance(by: .seconds(1))
        await rig.answer(5)
        rig.emit(.failure(.outOfMemory), of: Rig.glitchSource)
        await rig.answer(6)
        await rig.clock.sleepers.waitForCount(3)
        #expect(
            rig.clock.sleepers.values == [.seconds(300), .seconds(900), .seconds(2100)],
            "the third wait is 1200 seconds, from the failure at 900 seconds")
        rig.clock.advance(by: .seconds(1199))
        #expect(rig.clock.parkedCount == 1, "the 1200-second cool-down is still running at 2099 seconds")
        #expect(rig.runtime.prepareRequests.count == 6)
        rig.clock.advance(by: .seconds(1))
        let trial = await rig.answer(7)
        #expect(trial.effect == Rig.glitchSource, "the fourth trial prepares the switched-off source")
        await rig.stop(run)
    }

    @Test("a trial that times out is never scheduled again, and the record says it does not retry on its own")
    func timedOutTrialGetsNoNextTrial() async {
        let rig = Rig(persisted: glitch.id)
        let (run, watcher) = await switchedOff(rig)
        rig.clock.advance(by: .seconds(300))
        await rig.answer(3)
        rig.emit(.failure(.timeout), of: Rig.glitchSource)
        await rig.settings.disabledWrites.waitForCount(2)
        #expect(rig.settings.disabledWrites.values.last?.first?.reason == .failure(.timeout))
        #expect(rig.settings.disabledWrites.values.last?.first?.retriesAutomatically == false, "a retried hang would stall the call again")
        await rig.answer(4)
        // A sentinel: the bundled effect's access revocation is counted after the glitch's switch-off, and it raises the GPU flag.
        rig.emit(.failure(.accessRevoked), of: Rig.bundledSource)
        _ = await watcher.states.waitFor(predicate: { $0.isGPUUnavailable })
        #expect(rig.clock.sleepers.count == 1, "only the switch-off's 300-second wait was ever registered")
        #expect(rig.clock.parkedCount == 0, "no wait is parked after the timed-out trial")
        await rig.stop(run)
    }

    @Test("a trial that is over budget again after its one pass is disabled for 600 seconds before the next trial")
    func overBudgetTrialDoublesCoolDown() async {
        let rig = Rig(persisted: glitch.id)
        let (run, _) = await rig.begin()
        rig.emit(.success(Rig.slow), of: Rig.glitchSource, times: 30)
        await rig.answer(2)
        await rig.clock.sleepers.waitForCount(1)
        #expect(rig.clock.sleepers.values == [.seconds(300)], "the first switch-off waits 300 seconds")
        rig.clock.advance(by: .seconds(300))
        await rig.answer(3)
        rig.emit(.success(Rig.slow), of: Rig.glitchSource)
        await rig.answer(4)
        await rig.clock.sleepers.waitForCount(2)
        #expect(rig.clock.sleepers.values == [.seconds(300), .seconds(900)], "the second wait is 600 seconds, from the failure at 300 seconds")
        rig.clock.advance(by: .seconds(599))
        #expect(rig.clock.parkedCount == 1, "the doubled cool-down is still running at 899 seconds")
        #expect(rig.runtime.prepareRequests.count == 4)
        rig.clock.advance(by: .seconds(1))
        let trial = await rig.answer(5)
        #expect(trial.effect == Rig.glitchSource, "the trial after the doubled cool-down prepares the switched-off source")
        await rig.stop(run)
    }
}
