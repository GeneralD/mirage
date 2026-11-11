import Domain
import EffectRuntimeStateDataSource
import TestDoubles
import TestSupport
import Testing

/// The seed of an effect session: drawn once from `RandomSource` when the session starts, carried by
/// every later frame of it, and handed to the pass in its uniforms. The state draws it on the executor
/// in the `admit` step, so a frame that continues a session draws nothing and a restart draws again.
@Suite("EffectRuntimeState seed", .timeLimit(.minutes(1)))
@MainActor
struct EffectSeedTests {
    // MARK: - The session value

    @Test("a session built without a seed has seed 0, and equals the same session built with seed 0")
    func sessionWithoutSeedHasZero() {
        let start = HostTimestamp(nanoseconds: 5)
        #expect(EffectSession(start: start).seed == 0)
        #expect(EffectSession(start: start) == EffectSession(start: start, seed: 0))
    }

    @Test("the uniforms of a pass carry the session's seed, whatever the frame")
    func passCarriesTheSessionSeed() {
        let session = EffectSession(start: HostTimestamp(nanoseconds: 1), seed: 0xC0FFEE)
        let context = FrameContext(presentationTime: HostTimestamp(nanoseconds: 2), frameIndex: 1)
        let uniforms = EffectUniforms.pass(context, in: session, output: .bgra(width: 4, height: 4))
        #expect(uniforms.seed == 0xC0FFEE)
    }

    @Test("a session that starts draws its seed once, and a continuing frame keeps the current seed without drawing")
    func ofDrawsOnlyWhenItStarts() {
        let draws = Collector<UInt32>()
        let first = FrameContext(presentationTime: HostTimestamp(nanoseconds: 100), frameIndex: 0)
        let next = FrameContext(presentationTime: HostTimestamp(nanoseconds: 200), frameIndex: 1)

        let started = EffectSession.of(first, after: nil) {
            draws.append(42)
            return 42
        }
        #expect(started.seed == 42)
        #expect(draws.count == 1)

        let continued = EffectSession.of(next, after: started) {
            draws.append(7)
            return 7
        }
        #expect(continued == started)
        #expect(draws.count == 1, "a continuing frame does not draw")
    }

    // MARK: - Through the state

    @Test("the first admit's uniforms carry the seed drawn for the session it starts, and that draw is the only one")
    func firstAdmitCarriesTheDrawnSeed() async throws {
        let random = SequenceRandomSource([0xDEAD_BEEF])
        let fixture = StateFixture(randomSource: random)
        let admission = try await fixture.answer(fixture.admit())
        #expect(admission.uniforms.seed == 0xDEAD_BEEF)
        #expect(random.draws.values == [1 << 32])
    }

    @Test("a later frame of the same session keeps the seed and draws nothing")
    func continuingFrameKeepsTheSeed() async throws {
        let random = SequenceRandomSource([0xDEAD_BEEF])
        let fixture = StateFixture(randomSource: random)
        _ = try await fixture.prepared(.first)
        let first = try await fixture.answer(fixture.admit(Frame(index: 0)))
        let second = try await fixture.answer(fixture.admit(Frame(index: 1)))
        #expect(first.uniforms.seed == 0xDEAD_BEEF)
        #expect(second.uniforms.seed == 0xDEAD_BEEF)
        #expect(random.draws.count == 1, "the frame that continues the session does not draw")
    }

    @Test("a frame of index 0 starts a new session and draws the next seed")
    func restartDrawsAgain() async throws {
        let random = SequenceRandomSource([1, 2])
        let fixture = StateFixture(randomSource: random)
        _ = try await fixture.prepared(.first)
        let first = try await fixture.answer(fixture.admit(Frame(index: 0)))
        let restarted = try await fixture.answer(fixture.admit(Frame(index: 0)))
        #expect(first.uniforms.seed == 1)
        #expect(restarted.uniforms.seed == 2)
        #expect(random.draws.values == [1 << 32, 1 << 32])
    }

    @Test("the first frame of a stream whose index is not 0 starts a session and draws once")
    func firstFrameAtANonzeroIndexDraws() async throws {
        let random = SequenceRandomSource([7])
        let fixture = StateFixture(randomSource: random)
        let admission = try await fixture.answer(fixture.admit(Frame(index: 5)))
        #expect(admission.uniforms.seed == 7)
        #expect(random.draws.count == 1)
    }

    @Test("beginning another effect neither starts a session nor draws: the running session keeps its seed")
    func beginKeepsTheSeed() async throws {
        let random = SequenceRandomSource([9])
        let fixture = StateFixture(randomSource: random)
        _ = try await fixture.prepared(.first)
        _ = try await fixture.prepared(.second)
        _ = try await fixture.answer(fixture.admit(Frame(index: 0)))
        #expect(try await fixture.answer(fixture.begin(.first)) == .cached)
        let admission = try await fixture.answer(fixture.admit(Frame(index: 1)))
        #expect(admission.uniforms.seed == 9)
        #expect(random.draws.count == 1)
    }

    @Test("without a randomSource override the seed is 0, because the default source draws 0")
    func defaultSeedIsZero() async throws {
        let fixture = StateFixture()
        let admission = try await fixture.answer(fixture.admit(Frame(index: 3)))
        #expect(admission.uniforms.seed == 0)
    }
}
