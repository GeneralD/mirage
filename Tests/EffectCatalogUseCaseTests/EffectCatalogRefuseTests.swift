import Domain
import TestDoubles
import TestSupport
import Testing

/// A switched-off package effect is refused where it is chosen and where a listing still finds it: nothing is remembered,
/// read or prepared for it again, and the bundled effect answers in its place. Each test switches glitch off by a failing
/// pass, makes the attempt, and checks what the runtime was handed. A run is finished by `finish`, which answers every
/// prepare still out, because the runtime fake ignores cancellation.
@Suite("EffectCatalogUseCase refuses a disabled effect", .timeLimit(.minutes(1)))
struct EffectCatalogRefuseTests {
    private typealias Rig = EffectCatalogRig
    private let bundled = Rig.bundled
    private let glitch = Rig.glitch
    private let other = Rig.other

    /// A run with glitch chosen and switched off by a failing pass, with the bundled effect answered in its place.
    private func switchedOff() async -> (rig: Rig, run: Task<Void, Never>) {
        let rig = Rig(persisted: glitch.id)
        let (run, _) = await rig.begin()
        rig.emit(.failure(.accessRevoked), of: Rig.glitchSource)
        await rig.answer(2)
        await rig.settings.disabledWrites.waitForCount(1)
        return (rig, run)
    }

    /// Stops the run. The runtime fake ignores cancellation, so every prepare still out is answered first.
    private func finish(_ run: Task<Void, Never>, _ rig: Rig) async {
        run.cancel()
        for request in rig.runtime.prepareRequests.values {
            rig.runtime.completePrepare(request, with: .success(()))
        }
        await run.value
    }

    @Test("choosing a switched-off effect is refused, and remembers and prepares nothing for it")
    func choiceOfASwitchedOffEffectIsRefused() async {
        let (rig, run) = await switchedOff()
        let writes = rig.settings.writes.count
        let prepares = rig.runtime.prepareRequests.count
        let outcome = await rig.subject.select(glitch.id)
        #expect(outcome == .unavailable(nil), "the refused choice reports neither an outcome nor a problem")
        #expect(rig.settings.writes.count == writes, "the refused choice was not remembered")
        #expect(rig.runtime.prepareRequests.count == prepares, "the refused choice prepared nothing")
        await finish(run, rig)
    }

    @Test("a choice still waiting for its source prepares nothing once its effect is switched off in the meantime")
    func choiceWaitingForItsSourceWhenSwitchedOff() async {
        let rig = Rig(persisted: glitch.id)
        let (run, _) = await rig.begin()
        rig.packages.holdSources()
        let choice = Task { await rig.subject.select(glitch.id) }  // glitch is still on, so the choice reads its files
        await rig.packages.heldSources.waitForCount(1)
        rig.emit(.failure(.accessRevoked), of: Rig.glitchSource)  // switched off while the choice waits
        await rig.packages.heldSources.waitForCount(2)  // the bundled effect's files are read in its place
        rig.packages.completeSource(rig.packages.heldSources.values[0])
        #expect(await choice.value == .unavailable(nil), "a choice that finds its effect switched off after its read is refused")
        rig.packages.completeSource(rig.packages.heldSources.values[1])
        await rig.answer(2)
        #expect(rig.runtime.prepareRequests.count == 2, "nothing was prepared for the refused choice")
        #expect(rig.runtime.prepareRequests.values[1].effect == Rig.bundledSource, "the bundled effect is the one prepared in its place")
        await finish(run, rig)
    }

    @Test("a listing that still lists a switched-off effect as ready prepares nothing for it")
    func listingStillListingASwitchedOffEffect() async {
        let (rig, run) = await switchedOff()
        rig.packages.publish([bundled, glitch, other])  // glitch is still listed as ready
        rig.packages.publish([bundled, other])  // glitch is gone: this listing is taken up only once the one before has returned
        _ = await rig.log.entries.waitFor(predicate: { $0.message.contains("is gone") })
        #expect(rig.runtime.prepareRequests.count == 2, "the listing prepared nothing for the switched-off effect")
        await finish(run, rig)
    }
}
