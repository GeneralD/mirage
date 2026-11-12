import Domain
import TestDoubles
import TestSupport
import Testing

@testable import EffectCatalogUseCase

/// The resend that follows a `prepare` (`docs/hackathon/mvp-cd/specs/parameters.md`): a write made while the prepare is out
/// reaches the runtime at once, but the runtime may drop it, since it can arrive before the `begin` of that prepare. So when
/// the prepare answers, the block the model holds is handed over again, once, and only when it differs from the block the
/// prepare carried. Each rule is one test, named as the spec sentence it checks. Every `prepare` is answered by the test,
/// and nothing waits on time.
@Suite("EffectCatalogUseCase parameter resend", .timeLimit(.minutes(1)))
struct EffectCatalogParameterResendTests {
    private typealias Rig = EffectCatalogRig
    private let glitch = Rig.glitch
    private let other = Rig.other

    /// The package `glitch` reads: an effect that declares the six example parameters.
    private static let declaring = EffectSource(name: "Glitch", source: "glitch v1", parameters: EffectParameterSpec.all)

    /// The sources of a rig in which `glitch` reads `declared` and the others read their usual sources.
    private static func glitchReads(_ declared: EffectSource) -> [EffectID: EffectSource] {
        [Rig.bundled.id: Rig.bundledSource, Rig.glitch.id: declared, Rig.other.id: Rig.otherSource]
    }

    /// The model with every declared parameter at its default.
    private static var defaults: ParameterModel { ParameterModel(specs: EffectParameterSpec.all, restoring: [:]) }

    /// Returns once the session has taken up every message sent before it.
    private func flushed(_ rig: Rig) async {
        _ = await rig.subject.select(.package("nobody"))
    }

    /// A rig whose bundled effect is prepared and answered, and whose `glitch` choice is out, as the second `prepare`.
    private func choosingGlitch(_ rig: Rig, _ watcher: Rig.Watcher) async -> Task<EffectSelectionOutcome, Never> {
        await rig.answer(1)
        await watcher.states.waitForCount(1)
        let choice = Task { await rig.subject.select(glitch.id) }
        await rig.runtime.prepareRequests.waitForCount(2)  // glitch's prepare is out, and stays out until the test answers it
        return choice
    }

    @Test("a write made while a prepare is out is handed to the runtime again once it answers, as the newest block")
    func writeMadeWhileOutIsResent() async throws {
        let rig = Rig(sources: Self.glitchReads(Self.declaring))
        let watcher = rig.watch()
        let run = rig.start()
        let choice = await choosingGlitch(rig, watcher)

        await rig.subject.setParameter("strength", to: .float(0.75))  // handed over at once, before the answer
        let moved = try #require(Self.defaults.setting("strength", to: .float(0.75))).block
        #expect(rig.runtime.parameterWrites.values.map(\.block) == [moved])

        await rig.answer(2)
        #expect(await choice.value == .prepared, "the outcome is the prepare's: the resend changes nothing the caller sees")
        await watcher.states.waitForCount(3)
        await flushed(rig)  // the turn that answered has ended, resend included

        #expect(rig.runtime.parameterWrites.values.map(\.block) == [moved, moved], "the newest block is handed over once more")
        #expect(rig.runtime.parameterWrites.values.allSatisfy { $0.source == Self.declaring })
        await rig.stop(run)
    }

    @Test("a write undone while a prepare is out is not sent again: the block the prepare carried is already the newest")
    func undoneWriteIsNotResent() async throws {
        let rig = Rig(sources: Self.glitchReads(Self.declaring))
        let watcher = rig.watch()
        let run = rig.start()
        let choice = await choosingGlitch(rig, watcher)

        await rig.subject.setParameter("strength", to: .float(0.75))
        await rig.subject.setParameter("strength", to: .float(0.5))  // back to the default the prepare carried
        #expect(rig.runtime.parameterWrites.count == 2)

        await rig.answer(2)
        #expect(await choice.value == .prepared)
        await watcher.states.waitForCount(4)
        await flushed(rig)
        #expect(rig.runtime.parameterWrites.count == 2, "the answer finds the block it carried: nothing is resent")
        await rig.stop(run)
    }

    @Test("a prepare that answers with no write made while it was out hands the runtime nothing more")
    func answerWithoutWritesSendsNothing() async {
        let rig = Rig(sources: Self.glitchReads(Self.declaring))
        let watcher = rig.watch()
        let run = rig.start()
        let choice = await choosingGlitch(rig, watcher)

        await rig.answer(2)
        #expect(await choice.value == .prepared)
        await watcher.states.waitForCount(2)
        await flushed(rig)
        #expect(rig.runtime.parameterWrites.count == 0, "nothing was written, so nothing is resent")
        await rig.stop(run)
    }

    @Test("an answer for the effect chosen before sends nothing, and the write made to that effect while it was out is not resent")
    func answerOfTheChoiceBeforeSendsNothing() async {
        let rig = Rig(sources: Self.glitchReads(Self.declaring))
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        let older = Task { await rig.subject.select(glitch.id) }
        await rig.runtime.prepareRequests.waitForCount(2)  // glitch's prepare is out...
        await rig.subject.setParameter("strength", to: .float(0.75))  // ...and is written to, handed over at once
        let newer = Task { await rig.subject.select(other.id) }
        await rig.runtime.prepareRequests.waitForCount(3)  // other is chosen, and prepared for itself

        await rig.answer(2)  // glitch's answer comes back now, older than other's prepare
        #expect(await older.value == .prepared, "the caller of the older choice is still told how it went")
        await rig.answer(3)
        #expect(await newer.value == .prepared)
        await watcher.states.waitForCount(3)
        await flushed(rig)

        #expect(rig.runtime.parameterWrites.count == 1, "only the write made at once: the stale answer resent nothing")
        #expect(rig.runtime.parameterWrites.values.map(\.source) == [Self.declaring])
        await rig.stop(run)
    }

    @Test("a write made after an answer's resend is sent once, as a write of its own: one answer resends at most once")
    func answerResendsAtMostOnce() async throws {
        let rig = Rig(sources: Self.glitchReads(Self.declaring))
        let watcher = rig.watch()
        let run = rig.start()
        let choice = await choosingGlitch(rig, watcher)

        await rig.subject.setParameter("strength", to: .float(0.75))  // handed over at once
        await rig.answer(2)
        #expect(await choice.value == .prepared)
        await watcher.states.waitForCount(3)
        await flushed(rig)
        #expect(rig.runtime.parameterWrites.count == 2, "the answer resent the newest block")

        await rig.subject.setParameter("strength", to: .float(0.25))  // after the answer: a write of its own, not a resend
        let moved = try #require(Self.defaults.setting("strength", to: .float(0.75))).block
        let quarter = try #require(Self.defaults.setting("strength", to: .float(0.25))).block
        #expect(rig.runtime.parameterWrites.values.map(\.block) == [moved, moved, quarter])
        await rig.stop(run)
    }
}
