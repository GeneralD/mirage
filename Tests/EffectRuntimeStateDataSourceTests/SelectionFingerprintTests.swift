import Domain
import EffectRuntimeStateDataSource
import TestDoubles
import TestSupport
import Testing

/// The stamp a pass carries: the fingerprint of the effect whose library it runs, handed out with
/// the selection in the step that settles it, exactly as the parameter block is. A pass that ends
/// after the user picked another effect is therefore still the first effect's, and the health
/// judgement never charges one effect with another's failure. Where the stamp is *reported* is
/// `PassOutcomeTests`.
@Suite("EffectRuntimeState fingerprint", .timeLimit(.minutes(1)))
@MainActor
struct SelectionFingerprintTests {
    @Test("a settled selection is stamped with the fingerprint of the effect that was compiled")
    func stampOfTheCompiledEffect() async throws {
        let fixture = StateFixture()
        _ = try await fixture.prepared(.first)

        let admission = try await fixture.answer(fixture.admit())
        #expect(admission.fingerprint == .of(.first))
        #expect(EffectFingerprint.of(.first) != .of(.second), "the two fixtures are told apart by their stamps")
    }

    @Test("a cache hit is stamped with the effect it selects, not with the one it replaces")
    func cacheHitIsStampedWithItsOwnEffect() async throws {
        let fixture = StateFixture()
        _ = try await fixture.prepared(.first)
        _ = try await fixture.prepared(.second)
        #expect(try await fixture.answer(fixture.admit()).fingerprint == .of(.second))

        #expect(try await fixture.answer(fixture.begin(.first)) == .cached)
        #expect(try await fixture.answer(fixture.admit(Frame(index: 1))).fingerprint == .of(.first))
    }

    @Test("an edit of the source is another effect to stamp: the same name over another source has another fingerprint")
    func editedSourceIsStampedAnew() async throws {
        let fixture = StateFixture()
        let edited = EffectSource(name: "first", source: EffectSource.first.source + "\n")
        _ = try await fixture.prepared(.first)
        _ = try await fixture.prepared(edited)

        let admission = try await fixture.answer(fixture.admit())
        #expect(admission.fingerprint == .of(edited))
        #expect(admission.fingerprint != .of(.first))
    }

    @Test("an admit that waits is stamped with the effect that settles it when a newer begin overtakes the compile it waited for")
    func waitingAdmitIsStampedWithTheNewerEffect() async throws {
        let fixture = StateFixture()
        _ = try await fixture.prepared(.second)
        _ = try await fixture.startCompile(.first)
        let waiting = fixture.admit()
        #expect(await fixture.stillWaiting(waiting))

        #expect(try await fixture.answer(fixture.begin(.second)) == .cached)
        #expect(try await fixture.answer(waiting).fingerprint == .of(.second), "the library it runs is the second's, so is its stamp")
    }

    @Test("an apply that compiled the fallback itself is stamped by selected() with the effect the selection settles to")
    func selectedIsStampedWithTheSettledEffect() async throws {
        let fixture = StateFixture()
        _ = try #require(try await fixture.answer(fixture.admit()).compile)
        let waiting = fixture.selected()
        #expect(await fixture.stillWaiting(waiting))

        _ = try await fixture.prepared(.first)
        let selection = try await fixture.answer(waiting)
        #expect(selection.fingerprint == .of(.first))
        #expect(selection.fingerprint != .of(.bundled), "not the fallback it started to compile")
    }

    @Test("the fallback runs stamped with the bundled effect's fingerprint")
    func fallbackIsStampedWithTheBundledEffect() async throws {
        let fixture = StateFixture()
        let compile = try #require(try await fixture.answer(fixture.admit()).compile)
        _ = try await fixture.succeed(compile)

        #expect(try await fixture.answer(fixture.selected()).fingerprint == .of(.bundled))
        #expect(try await fixture.answer(fixture.admit(Frame(index: 1))).fingerprint == .of(.bundled))
    }

    @Test("a source that does not compile is stamped too: its failure is the failed effect's")
    func failedSelectionIsStamped() async throws {
        let fixture = StateFixture()
        let waiting = try await fixture.startCompile(.first)
        _ = try await fixture.fail(waiting)

        let admission = try await fixture.answer(fixture.admit())
        #expect(admission.failure == .compileFailed)
        #expect(admission.fingerprint == .of(.first))
    }

    @Test("a compile that failed for the environment's reasons releases a waiting admit stamped with the effect that will be retried")
    func retrySelectionIsStamped() async throws {
        let fixture = StateFixture()
        let compile = try await fixture.startCompile(.first)
        let waiting = fixture.admit()
        #expect(await fixture.stillWaiting(waiting))

        _ = try await fixture.fail(compile, cause: .environment)
        let admission = try await fixture.answer(waiting)
        #expect(admission.failure == .internalError)
        #expect(admission.fingerprint == .of(.first))
    }

    @Test("the stamp of an effect does not change while its selection is retried frame after frame")
    func retriedEffectKeepsItsStamp() async throws {
        let fixture = StateFixture()
        _ = try await fixture.fail(try await fixture.startCompile(.first), cause: .environment)

        for index in UInt32(1)...3 {
            let retry = try #require(try await fixture.answer(fixture.admit(Frame(index: index))).compile)
            #expect(retry.effect == .first)
            _ = try await fixture.fail(retry, cause: .environment)
        }
        let compile = try #require(try await fixture.answer(fixture.admit(Frame(index: 4))).compile)
        _ = try await fixture.succeed(compile)
        #expect(try await fixture.answer(fixture.admit(Frame(index: 5))).fingerprint == .of(.first))
    }
}
