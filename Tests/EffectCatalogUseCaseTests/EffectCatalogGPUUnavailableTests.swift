import Domain
import TestSupport
import Testing

/// The bundled effect that health switches off: nothing is recorded, written or prepared in its place, since no effect is left to
/// move frames; the menu says the GPU is unavailable instead. A pass of any effect that succeeds brings the flag down, and a new run
/// forgets it. The runtime fake never answers on its own, so each test answers every `prepare` by hand before its run stops; a
/// missed answer shows as the one-minute time limit.
@Suite("EffectCatalogUseCase GPU unavailable", .timeLimit(.minutes(1)))
struct EffectCatalogGPUUnavailableTests {
    private typealias Rig = EffectCatalogRig
    private let bundled = Rig.bundled
    private let other = Rig.other

    @Test("a bundled effect that health switches off raises the GPU-unavailable flag, and records, writes and prepares nothing more")
    func bundledSwitchOffRaisesTheFlag() async {
        let rig = Rig()
        let (run, watcher) = await rig.begin()
        rig.emit(.failure(.accessRevoked), of: Rig.bundledSource)
        let shown = await watcher.states.waitFor(predicate: { $0.isGPUUnavailable })
        #expect(shown?.isGPUUnavailable == true, "the menu says the GPU is unavailable")
        #expect(shown?.disabled == [:], "the bundled effect is never recorded as switched off")
        #expect(rig.settings.disabledWrites.count == 0, "nothing is written to the settings")
        #expect(rig.runtime.prepareRequests.count == 1, "the bundled effect is not prepared again in its place")
        await rig.stop(run)
    }

    @Test("a passing pass lowers the GPU-unavailable flag again, and the menu shows it at once")
    func passLowersTheFlag() async {
        let rig = Rig()
        let (run, watcher) = await rig.begin()
        rig.emit(.failure(.accessRevoked), of: Rig.bundledSource)
        _ = await watcher.states.waitFor(predicate: { $0.isGPUUnavailable })
        // The states published so far carry the flag, so the wait is by count: the state after the pass is the next one.
        let shownBefore = watcher.states.count
        rig.emit(.success(Rig.fast), of: Rig.bundledSource)
        await watcher.states.waitForCount(shownBefore + 1)
        #expect(watcher.states.last?.isGPUUnavailable == false, "the flag comes down with the first passing pass")
        #expect(watcher.states.last?.selection == bundled.id)
        await rig.stop(run)
    }

    @Test("a passing pass of any effect lowers the GPU-unavailable flag, not only one of the bundled effect")
    func passOfAnyEffectLowersTheFlag() async {
        let rig = Rig()
        let (run, watcher) = await rig.begin()
        rig.emit(.failure(.accessRevoked), of: Rig.bundledSource)
        _ = await watcher.states.waitFor(predicate: { $0.isGPUUnavailable })
        let choice = Task { await rig.subject.select(other.id) }
        await rig.answer(2)
        #expect(await choice.value == .prepared)
        // The observer appends each state after the actor has published it, so the choice's own state is awaited before the count is taken.
        _ = await watcher.states.waitFor(predicate: { $0.selection == other.id })
        let shownBefore = watcher.states.count
        rig.emit(.success(Rig.fast), of: Rig.otherSource)
        await watcher.states.waitForCount(shownBefore + 1)
        #expect(watcher.states.last?.isGPUUnavailable == false, "the chosen package effect's pass brings the flag down")
        #expect(watcher.states.last?.selection == other.id)
        await rig.stop(run)
    }

    @Test("a bundled effect switched off after a package effect keeps that effect's record, and prepares nothing more")
    func bundledSwitchOffKeepsThePackageRecord() async {
        let rig = Rig(persisted: Rig.glitch.id)
        let (run, watcher) = await rig.begin()
        rig.emit(.failure(.accessRevoked), of: Rig.glitchSource)
        await rig.answer(2)
        _ = await rig.firstDisabled(in: watcher)
        rig.emit(.failure(.accessRevoked), of: Rig.bundledSource)
        let shown = await watcher.states.waitFor(predicate: { $0.isGPUUnavailable })
        #expect(shown?.disabled == [Rig.glitch.id: .failure(.accessRevoked)], "the glitch's switch-off stays as it was")
        #expect(rig.settings.disabledWrites.count == 1, "only the glitch's record was written")
        #expect(rig.runtime.prepareRequests.count == 2, "the bundled effect, already prepared in place of the glitch, is not prepared again")
        await rig.stop(run)
    }

    @Test("a new run forgets the GPU-unavailable flag, and its first state says the GPU is available")
    func newRunForgetsTheFlag() async {
        let rig = Rig()
        let (run, watcher) = await rig.begin()
        rig.emit(.failure(.accessRevoked), of: Rig.bundledSource)
        _ = await watcher.states.waitFor(predicate: { $0.isGPUUnavailable })
        await rig.stop(run)

        // The new run has begun once its own prepare is out, so the stream opened after it waits for that run's first state.
        let again = rig.start()
        await rig.answer(2)
        let fresh = rig.watch()
        await fresh.states.waitForCount(1)
        #expect(fresh.states.values.first?.isGPUUnavailable == false, "the flag was not carried over from the run before")
        #expect(fresh.states.values.first == Rig.state(), "nothing is off, so the state says nothing about health")
        await rig.stop(again)
    }
}
