import Domain
import TestDoubles
import TestSupport
import Testing

@testable import EffectCatalogUseCase

/// The debounce of the parameter writes (`docs/hackathon/mvp-cd/specs/parameters.md`, Persistence): a write is persisted
/// once, 500 ms after the last write of its effect, with every declared value; a write to another effect within that time
/// is persisted by the same timer; a choice back within it starts from the waiting values, not from the settings. The time
/// is stepped by the rig's `GatedClock`, so nothing waits on the wall clock.
@Suite("EffectCatalogUseCase parameter persistence", .timeLimit(.minutes(1)))
struct EffectCatalogParameterPersistTests {
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

    /// The value the state shows for the parameter `id`, or nil when the state lists no such parameter.
    private static func value(of id: String, in state: EffectCatalogState?) -> EffectParameterValue? {
        state?.parameters.first(where: { $0.spec.id == id })?.value
    }

    // MARK: - The quiet period

    @Test("a write is persisted once, 500 ms after it: at 499 ms nothing is persisted yet")
    func persistsOnceAfterTheQuietPeriod() async throws {
        let rig = Rig(persisted: glitch.id, sources: Self.sources)
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        await rig.subject.setParameter("rings", to: .int(9))
        await rig.clock.sleepers.waitForCount(1)
        rig.clock.advance(by: .milliseconds(499))
        #expect(rig.settings.parameterWrites.count == 0, "nothing is persisted before 500 ms")

        rig.clock.advance(by: .milliseconds(1))
        await rig.settings.parameterWrites.waitForCount(1)
        #expect(
            rig.settings.parameterWrites.values == [
                FakeSettingsRepository.ParameterWrite(id: glitch.id, values: try Self.values(setting: "rings", to: .int(9)))
            ],
            "one write, of the effect, with every declared value")
        await rig.stop(run)
    }

    @Test("two writes 300 ms apart are persisted once, with the second value, 800 ms after the first")
    func laterWriteRestartsTheQuietPeriod() async throws {
        let rig = Rig(persisted: glitch.id, sources: Self.sources)
        let run = rig.start()
        await rig.answer(1)

        await rig.subject.setParameter("rings", to: .int(9))
        await rig.clock.sleepers.waitForCount(1)
        rig.clock.advance(by: .milliseconds(300))
        await rig.subject.setParameter("rings", to: .int(2))
        await rig.clock.cancelledSleepers.waitForCount(1)
        await rig.clock.sleepers.waitForCount(2)
        #expect(rig.clock.cancelledSleepers.values == [.milliseconds(500)], "the first sleep, due at 500 ms, is cancelled")

        rig.clock.advance(by: .milliseconds(499))  // 799 ms after the first write
        #expect(rig.settings.parameterWrites.count == 0, "the first write's timer does not persist the second value early")
        rig.clock.advance(by: .milliseconds(1))
        await rig.settings.parameterWrites.waitForCount(1)
        #expect(
            rig.settings.parameterWrites.values == [
                FakeSettingsRepository.ParameterWrite(id: glitch.id, values: try Self.values(setting: "rings", to: .int(2)))
            ],
            "one write, with the second value")
        await rig.stop(run)
    }

    @Test("a write to another effect within the quiet period is persisted by the same timer, both effects in origin and key order")
    func writesOfTwoEffectsShareOneTimer() async throws {
        let rig = Rig(persisted: glitch.id, sources: Self.sources)
        let run = rig.start()
        await rig.answer(1)

        await rig.subject.setParameter("rings", to: .int(9))  // the package glitch
        let choice = Task { await rig.subject.select(bundled.id) }
        await rig.answer(2)
        #expect(await choice.value == .prepared)
        await rig.subject.setParameter("strength", to: .float(0.25))  // the bundled effect, within the quiet period
        await rig.clock.cancelledSleepers.waitForCount(1)  // the timer of the glitch's write is replaced
        await rig.clock.sleepers.waitForCount(2)

        rig.clock.advance(by: .milliseconds(500))
        await rig.settings.parameterWrites.waitForCount(2)
        #expect(
            rig.settings.parameterWrites.values == [
                FakeSettingsRepository.ParameterWrite(
                    id: bundled.id, values: try Self.values(setting: "strength", to: .float(0.25))),
                FakeSettingsRepository.ParameterWrite(id: glitch.id, values: try Self.values(setting: "rings", to: .int(9))),
            ],
            "the bundled effect sorts first by origin, and the glitch keeps its last value")
        await rig.stop(run)
    }

    @Test("a choice back to an effect within the quiet period starts from its waiting values, and reads its settings only once")
    func choiceBackStartsFromWaitingValues() async throws {
        let rig = Rig(persisted: glitch.id, sources: Self.sources)
        let run = rig.start()
        await rig.answer(1)

        await rig.subject.setParameter("rings", to: .int(9))
        let away = Task { await rig.subject.select(other.id) }
        await rig.answer(2)
        #expect(await away.value == .prepared)

        let back = Task { await rig.subject.select(glitch.id) }
        let returned = await rig.answer(3)
        #expect(await back.value == .prepared)
        let expected = try #require(Self.defaults.setting("rings", to: .int(9))).block
        #expect(returned.parameters == expected, "the glitch is prepared with the value still waiting, not the stored one")
        #expect(rig.settings.parameterReads.values == [glitch.id, other.id], "the choice back reads nothing for the glitch")

        await rig.clock.sleepers.waitForCount(1)
        rig.clock.advance(by: .milliseconds(500))
        await rig.settings.parameterWrites.waitForCount(1)
        #expect(
            rig.settings.parameterWrites.values == [
                FakeSettingsRepository.ParameterWrite(id: glitch.id, values: try Self.values(setting: "rings", to: .int(9)))
            ],
            "the timer of the write made before the choice still persists it")
        await rig.stop(run)
    }

    // MARK: - What is written, and when a timer starts

    @Test("each write holds every declared value, and a write after a persisted one starts a new timer, a reset included")
    func writeHoldsEveryDeclaredValue() async throws {
        let rig = Rig(persisted: glitch.id, sources: Self.sources)
        let run = rig.start()
        await rig.answer(1)

        await rig.subject.setParameter("rings", to: .int(9))
        await rig.clock.sleepers.waitForCount(1)
        rig.clock.advance(by: .milliseconds(500))
        await rig.settings.parameterWrites.waitForCount(1)
        let first = try #require(rig.settings.parameterWrites.values.first)
        #expect(first.values.count == EffectParameterSpec.all.count, "the parameters that were not touched are written at their defaults too")

        await rig.subject.resetParameters()
        await rig.clock.sleepers.waitForCount(2)
        rig.clock.advance(by: .milliseconds(500))
        await rig.settings.parameterWrites.waitForCount(2)
        #expect(
            rig.settings.parameterWrites.values.last == FakeSettingsRepository.ParameterWrite(id: glitch.id, values: Self.defaults.values),
            "a reset is persisted as the defaults")
        #expect(rig.clock.cancelledSleepers.count == 0, "the first timer had already fired, so no sleep was cancelled")
        await rig.stop(run)
    }

    @Test("a restore alone writes nothing: no timer starts, so nothing is persisted after 500 ms")
    func restoreWritesNothing() async {
        let rig = Rig(persisted: glitch.id, sources: Self.sources, parameters: [glitch.id: ["rings": .int(9)]])
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)
        #expect(Self.value(of: "rings", in: watcher.states.values.last) == .int(9), "the stored value is restored")

        rig.clock.advance(by: .milliseconds(500))
        #expect(rig.clock.sleepers.count == 0, "restoring starts no timer")
        #expect(rig.settings.parameterWrites.count == 0, "restoring writes nothing back")
        await rig.stop(run)
    }

    @Test("a set that changes nothing, or is rejected, starts no timer")
    func unchangedSetStartsNoTimer() async {
        let rig = Rig(persisted: glitch.id, sources: Self.sources)
        let run = rig.start()
        await rig.answer(1)

        await rig.subject.setParameter("strength", to: .float(0.5))  // the default already
        await rig.subject.setParameter("nope", to: .float(0.5))  // not declared
        rig.clock.advance(by: .milliseconds(500))
        #expect(rig.clock.sleepers.count == 0, "nothing changed, so nothing waits to be persisted")
        #expect(rig.settings.parameterWrites.count == 0)

        await rig.subject.setParameter("rings", to: .int(9))  // a change, which does start the timer
        await rig.clock.sleepers.waitForCount(1)
        #expect(rig.clock.sleepers.count == 1)
        await rig.stop(run)
    }

    @Test("a run that ends keeps a write waiting for its quiet period, and that write is still persisted")
    func endingTheRunKeepsTheWaitingWrite() async throws {
        let rig = Rig(persisted: glitch.id, sources: Self.sources)
        let run = rig.start()
        await rig.answer(1)
        await rig.subject.setParameter("rings", to: .int(9))
        await rig.clock.sleepers.waitForCount(1)

        await rig.stop(run)
        rig.clock.advance(by: .milliseconds(500))
        await rig.settings.parameterWrites.waitForCount(1)
        #expect(
            rig.settings.parameterWrites.values == [
                FakeSettingsRepository.ParameterWrite(id: glitch.id, values: try Self.values(setting: "rings", to: .int(9)))
            ])
    }
}
