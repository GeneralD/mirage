import Domain
import TestDoubles
import TestSupport
import Testing

/// What the runtime's pass outcomes do to the catalog: a package effect that keeps failing or runs over the budget is
/// switched off with its reason, and only the outcomes of the effect the runtime holds now count. The test reports each
/// outcome by hand, in the order it writes them. A sentinel that is final on its own (an access revocation) is reported
/// last, so once its reason is out, every outcome before it has been counted and "nothing happens" is proven without a sleep.
@Suite("EffectCatalogUseCase pass outcomes", .timeLimit(.minutes(1)))
struct EffectCatalogOutcomeTests {
    private typealias Rig = EffectCatalogRig
    private let bundled = Rig.bundled
    private let glitch = Rig.glitch
    private let other = Rig.other

    // MARK: - Counting a streak

    @Test("five timeouts in a row switch a package effect off, with the timeout as the reason")
    func fiveTimeoutsSwitchOff() async {
        let rig = Rig(persisted: glitch.id)
        let (run, watcher) = await rig.begin()
        rig.emit(.failure(.timeout), of: Rig.glitchSource, times: 5)
        #expect(await rig.firstDisabled(in: watcher) == [glitch.id: .failure(.timeout)])
        await rig.stop(run)
    }

    @Test("four timeouts in a row do not switch a package effect off")
    func fourTimeoutsDoNotSwitchOff() async {
        let rig = Rig(persisted: glitch.id)
        let (run, watcher) = await rig.begin()
        rig.emit(.failure(.timeout), of: Rig.glitchSource, times: 4)
        rig.emit(.failure(.accessRevoked), of: Rig.glitchSource)
        #expect(await rig.firstDisabled(in: watcher) == [glitch.id: .failure(.accessRevoked)], "the four timeouts counted for nothing")
        await rig.stop(run)
    }

    @Test("a pass that succeeds between failures starts the failure streak over")
    func successStartsTheFailureStreakOver() async {
        let rig = Rig(persisted: glitch.id)
        let (run, watcher) = await rig.begin()
        rig.emit(.failure(.timeout), of: Rig.glitchSource, times: 4)
        rig.emit(.success(Rig.fast), of: Rig.glitchSource)
        rig.emit(.failure(.timeout), of: Rig.glitchSource, times: 4)
        rig.emit(.failure(.accessRevoked), of: Rig.glitchSource)
        #expect(await rig.firstDisabled(in: watcher) == [glitch.id: .failure(.accessRevoked)], "no streak of five was ever in a row")
        await rig.stop(run)
    }

    @Test("thirty passes over the budget in a row switch a package effect off as over budget")
    func thirtySlowPassesSwitchOff() async {
        let rig = Rig(persisted: glitch.id)
        let (run, watcher) = await rig.begin()
        rig.emit(.success(Rig.slow), of: Rig.glitchSource, times: 30)
        #expect(await rig.firstDisabled(in: watcher) == [glitch.id: .overBudget])
        await rig.stop(run)
    }

    @Test("a pass within the budget starts the over-budget streak over")
    func withinBudgetStartsTheOverBudgetStreakOver() async {
        let rig = Rig(persisted: glitch.id)
        let (run, watcher) = await rig.begin()
        rig.emit(.success(Rig.slow), of: Rig.glitchSource, times: 29)
        rig.emit(.success(Rig.fast), of: Rig.glitchSource)
        rig.emit(.success(Rig.slow), of: Rig.glitchSource, times: 29)
        rig.emit(.failure(.accessRevoked), of: Rig.glitchSource)
        #expect(await rig.firstDisabled(in: watcher) == [glitch.id: .failure(.accessRevoked)], "58 slow passes, but never 30 in a row")
        await rig.stop(run)
    }

    // MARK: - Which pass counts

    @Test("a pass of an effect the runtime does not hold is not counted")
    func otherEffectsPassesAreNotCounted() async {
        let rig = Rig(persisted: glitch.id)
        let (run, watcher) = await rig.begin()
        rig.emit(.failure(.timeout), of: Rig.otherSource, times: 5)
        rig.emit(.failure(.accessRevoked), of: Rig.glitchSource)
        #expect(await rig.firstDisabled(in: watcher) == [glitch.id: .failure(.accessRevoked)])
        await rig.stop(run)
    }

    @Test("a pass of the effect a choice replaced is not counted, even when the runtime reports it after the choice")
    func replacedEffectsPassesAreNotCounted() async {
        let rig = Rig(persisted: glitch.id)
        let (run, watcher) = await rig.begin()
        let choice = Task { await rig.subject.select(other.id) }
        await rig.answer(2)
        _ = await choice.value
        rig.emit(.failure(.timeout), of: Rig.glitchSource, times: 5)
        rig.emit(.failure(.accessRevoked), of: Rig.otherSource)
        #expect(await rig.firstDisabled(in: watcher) == [other.id: .failure(.accessRevoked)], "only the chosen effect's passes count")
        await rig.stop(run)
    }

    @Test("a bundled effect that keeps failing is never switched off, and the package effect chosen after it is counted alone")
    func bundledEffectIsNeverSwitchedOff() async {
        let rig = Rig()
        let (run, watcher) = await rig.begin()
        rig.emit(.failure(.timeout), of: Rig.bundledSource, times: 5)
        let choice = Task { await rig.subject.select(glitch.id) }
        await rig.answer(2)
        _ = await choice.value
        rig.emit(.failure(.accessRevoked), of: Rig.glitchSource)
        #expect(await rig.firstDisabled(in: watcher) == [glitch.id: .failure(.accessRevoked)], "the bundled timeouts switched nothing off")
        await rig.stop(run)
    }

    // MARK: - Runs

    @Test("a run starts with nothing switched off, and the state of the new run does not carry the old one's")
    func newRunStartsWithNothingSwitchedOff() async {
        let rig = Rig(persisted: glitch.id)
        let (run, watcher) = await rig.begin()
        rig.emit(.failure(.timeout), of: Rig.glitchSource, times: 5)
        #expect(await rig.firstDisabled(in: watcher) == [glitch.id: .failure(.timeout)])
        await rig.stop(run)

        let again = rig.start()
        await rig.answer(2)  // the new run prepares the persisted choice for itself
        let fresh = rig.watch()
        await fresh.states.waitForCount(1)
        #expect(fresh.states.values == [Rig.state(selection: glitch)], "nothing is off, so the state says nothing about health")
        await rig.stop(again)
    }

    @Test("each run subscribes to the runtime's outcomes once, and a cancelled run returns although the outcomes were never finished")
    func oneSubscriptionPerRun() async {
        let rig = Rig(persisted: glitch.id)
        let (run, _) = await rig.begin()
        #expect(rig.runtime.outcomeStreams.count == 1)
        await rig.stop(run)

        let again = rig.start()
        await rig.runtime.outcomeStreams.waitForCount(2)
        await rig.answer(2)
        #expect(rig.runtime.outcomeStreams.count == 2, "one subscription for each run, not one for each listing")
        await rig.stop(again)
    }
}
