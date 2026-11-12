import Domain
import TestDoubles
import TestSupport
import Testing

@testable import EffectCatalogUseCase

/// The flush of the parameter writes at the end of a run (`EffectCatalogSession.run()`): a value still waiting for its quiet
/// period is persisted when the run that made it ends, at once, and the timer that would have written it is cancelled. A run
/// that a newer one took over writes nothing and leaves the waiting value to the timer. The time is stepped by the rig's
/// `GatedClock`, so nothing waits on the wall clock.
@Suite("EffectCatalogUseCase parameter flush", .timeLimit(.minutes(1)))
struct EffectCatalogParameterFlushTests {
    private typealias Rig = EffectCatalogRig
    private let bundled = Rig.bundled
    private let glitch = Rig.glitch
    private let other = Rig.other

    /// Every effect of the rig declares the six example parameters, so any of them can be set.
    private static let declaringBundled = EffectSource(
        name: "Chromatic Grain", source: "bundled v1", parameters: EffectParameterSpec.all)
    private static let declaringGlitch = EffectSource(name: "Glitch", source: "glitch v1", parameters: EffectParameterSpec.all)
    private static let declaringOther = EffectSource(name: "Other", source: "other v1", parameters: EffectParameterSpec.all)

    private static let sources: [EffectID: EffectSource] = [
        Rig.bundled.id: declaringBundled, Rig.glitch.id: declaringGlitch, Rig.other.id: declaringOther,
    ]

    /// The model with every declared parameter at its default.
    private static var defaults: ParameterModel { ParameterModel(specs: EffectParameterSpec.all, restoring: [:]) }

    /// The values the defaults hold once `id` is set to `value`: what a write of that effect persists.
    private static func values(setting id: String, to value: EffectParameterValue) throws -> [String: EffectParameterValue] {
        try #require(defaults.setting(id, to: value)).values
    }

    // MARK: - Ending the run

    @Test("a run that stops persists a value still waiting for its quiet period at once, and cancels the timer that would write it")
    func stopPersistsTheWaitingValueAtOnce() async throws {
        let rig = Rig(persisted: glitch.id, sources: Self.sources)
        let run = rig.start()
        await rig.answer(1)
        await rig.subject.setParameter("rings", to: .int(9))
        await rig.clock.sleepers.waitForCount(1)

        await rig.stop(run)
        await rig.clock.cancelledSleepers.waitForCount(1)
        #expect(
            rig.settings.parameterWrites.values == [
                FakeSettingsRepository.ParameterWrite(id: glitch.id, values: try Self.values(setting: "rings", to: .int(9)))
            ],
            "one write, of the glitch, with every declared value, before the quiet period is over")
        #expect(rig.clock.cancelledSleepers.values == [.milliseconds(500)], "the timer, due at 500 ms, is the one cancelled")

        rig.clock.advance(by: .milliseconds(500))
        #expect(rig.settings.parameterWrites.count == 1, "the cancelled timer writes nothing more")
    }

    @Test("a run that stops persists every waiting effect, the bundled one first, as the origin's raw value then the key order")
    func stopPersistsEveryWaitingEffectInOrder() async throws {
        let rig = Rig(persisted: glitch.id, sources: Self.sources)
        let run = rig.start()
        await rig.answer(1)

        await rig.subject.setParameter("rings", to: .int(9))  // the glitch, written first
        let choice = Task { await rig.subject.select(bundled.id) }
        await rig.answer(2)
        #expect(await choice.value == .prepared)
        await rig.subject.setParameter("strength", to: .float(0.25))  // the bundled effect, written last

        await rig.stop(run)
        #expect(
            rig.settings.parameterWrites.values == [
                FakeSettingsRepository.ParameterWrite(
                    id: bundled.id, values: try Self.values(setting: "strength", to: .float(0.25))),
                FakeSettingsRepository.ParameterWrite(id: glitch.id, values: try Self.values(setting: "rings", to: .int(9))),
            ],
            "the bundled effect sorts first by origin, and the glitch keeps its last value")
    }

    @Test("a run that stops with no value waiting writes nothing and cancels no timer")
    func stopWithNothingWaitingWritesNothing() async {
        let rig = Rig(persisted: glitch.id, sources: Self.sources)
        let run = rig.start()
        await rig.answer(1)

        await rig.stop(run)
        #expect(rig.settings.parameterWrites.count == 0)
        #expect(rig.clock.cancelledSleepers.count == 0)
    }

    @Test("a value the timer has already persisted is not written again when the run stops")
    func stopDoesNotWriteAgainWhatTheTimerWrote() async throws {
        let rig = Rig(persisted: glitch.id, sources: Self.sources)
        let run = rig.start()
        await rig.answer(1)
        await rig.subject.setParameter("rings", to: .int(9))
        await rig.clock.sleepers.waitForCount(1)
        rig.clock.advance(by: .milliseconds(500))
        await rig.settings.parameterWrites.waitForCount(1)

        await rig.stop(run)
        #expect(rig.settings.parameterWrites.count == 1, "the timer wrote it, so the stop has nothing left to write")
        #expect(rig.clock.cancelledSleepers.count == 0, "the timer had finished, so there is no sleep to cancel")
    }

    @Test("the waiting value is persisted before the run's observers see their streams end")
    func waitingValueIsPersistedBeforeTheStreamsEnd() async throws {
        let rig = Rig(persisted: glitch.id, sources: Self.sources)
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await rig.subject.setParameter("rings", to: .int(9))
        await rig.clock.sleepers.waitForCount(1)

        run.cancel()
        await watcher.ended.waitForCount(1)
        #expect(rig.settings.parameterWrites.count == 1, "the write is made before the run closes the streams")
        await run.value
    }

    // MARK: - A run taken over by a newer one

    @Test("a run that a newer one took over writes nothing when it stops, and the newer run's timer persists the waiting value")
    func takenOverRunLeavesTheWaitingValueToTheTimer() async throws {
        let rig = Rig(persisted: glitch.id, sources: Self.sources)
        let first = rig.start()
        await rig.answer(1)
        await rig.subject.setParameter("rings", to: .int(9))
        await rig.clock.sleepers.waitForCount(1)
        rig.packages.script(
            .success(EffectSource(name: "Glitch", source: "glitch v2", parameters: EffectParameterSpec.all)), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])  // the first run prepares the edited glitch, and waits for the runtime
        await rig.runtime.prepareRequests.waitForCount(2)
        first.cancel()

        let second = rig.start()
        await rig.runtime.prepareRequests.waitForCount(3)  // the second run prepares glitch for itself
        await rig.answer(3)
        await rig.answer(2)
        await first.value
        #expect(rig.settings.parameterWrites.count == 0, "the run taken over persists nothing")
        #expect(rig.clock.cancelledSleepers.count == 0, "its timer is left running")

        rig.clock.advance(by: .milliseconds(500))
        await rig.settings.parameterWrites.waitForCount(1)
        #expect(
            rig.settings.parameterWrites.values == [
                FakeSettingsRepository.ParameterWrite(id: glitch.id, values: try Self.values(setting: "rings", to: .int(9)))
            ],
            "the timer persists the value the taken-over run left waiting")
        await rig.stop(second)
    }
}
