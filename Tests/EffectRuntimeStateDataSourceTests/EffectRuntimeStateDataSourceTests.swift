import Domain
import EffectRuntimeStateDataSource
import TestDoubles
import TestSupport
import Testing

/// The runtime's memory on its own: tickets, the cache, the selection and the
/// callers waiting for it, driven through the port with no compiler and no
/// renderer. The test plays the repository — it begins, settles and admits in
/// the order it writes down — and drains the executor the state decides on.
@Suite("EffectRuntimeState", .timeLimit(.minutes(1)))
@MainActor
struct EffectRuntimeStateDataSourceTests {
    // MARK: - Executor confinement

    @Test("a call is decided on the executor: nothing happens before the drain, and one step takes the ticket")
    func decidedOnTheExecutor() async throws {
        let fixture = StateFixture()
        let first = fixture.begin(.first)
        await fixture.executor.enqueued.waitForCount(1)
        #expect(first.answered.count == 0, "no step has run")

        let begun = try await fixture.answer(first)
        let ticket = try #require(begun.ticket)
        let second = try #require(try await fixture.answer(fixture.begin(.second)).ticket)
        #expect(second != ticket, "every begin takes the next ticket")
    }

    // MARK: - Cache

    @Test("an effect compiles once: after its compile settled, begin is a hit and its library is the selection")
    func cacheHit() async throws {
        let fixture = StateFixture()
        let compile = try await fixture.startCompile(.first)
        let compiled = try await fixture.succeed(compile)
        #expect(compiled.settlement == .compiled(selected: true))

        #expect(try await fixture.answer(fixture.begin(.first)) == .cached)
        let admission = try await fixture.answer(fixture.admit())
        #expect(identity(admission.library) == identity(compiled.library))
        #expect(fixture.fallbackReads.count == 0, "something was prepared, so the fallback is not asked")
    }

    /// A change of what is compiled is a new key; a change of the name alone is not.
    struct KeyChange: Sendable, CustomTestStringConvertible {
        let label: String
        let effect: EffectSource
        let compilesAgain: Bool
        var testDescription: String { label }

        static let all = [
            KeyChange(label: "renamed", effect: EffectSource(name: "renamed", source: EffectSource.first.source), compilesAgain: false),
            KeyChange(
                label: "another source", effect: EffectSource(name: "first", source: EffectSource.first.source + "\n"), compilesAgain: true),
            KeyChange(
                label: "another entry point",
                effect: EffectSource(name: "first", source: EffectSource.first.source, options: ShaderCompileOptions(entryPoint: "other")),
                compilesAgain: true),
            KeyChange(
                label: "fast math",
                effect: EffectSource(name: "first", source: EffectSource.first.source, options: ShaderCompileOptions(precise: false)),
                compilesAgain: true),
        ]
    }

    @Test("the cache key is the source and the compile options, never the name", arguments: KeyChange.all)
    func cacheKey(_ change: KeyChange) async throws {
        let fixture = StateFixture()
        let original = try await fixture.prepared(.first)

        let begun = try await fixture.answer(fixture.begin(change.effect))
        if change.compilesAgain {
            #expect(begun.ticket != nil, "a new key compiles")
        } else {
            #expect(begun == .cached)
            let admission = try await fixture.answer(fixture.admit())
            #expect(identity(admission.library) == identity(original))
        }
    }

    @Test("a failed compile is not cached: beginning the same source again compiles it again")
    func failureIsNotCached() async throws {
        let fixture = StateFixture()
        let settlement = try await fixture.fail(try await fixture.startCompile(.first))
        #expect(settlement == .failed(.compileFailed))

        #expect(try await fixture.answer(fixture.begin(.first)).ticket != nil)
    }

    // MARK: - Newest wins

    /// Which of two overlapping compiles finishes first.
    enum Finish: String, Sendable, CaseIterable, CustomTestStringConvertible {
        case newestFirst = "the newer compile finishes first"
        case oldestFirst = "the older compile finishes first"
        var testDescription: String { rawValue }
    }

    @Test("newest wins: a compile overtaken by a newer begin settles as not selected, whichever finishes first", arguments: Finish.allCases)
    func newestWins(_ finish: Finish) async throws {
        let fixture = StateFixture()
        let older = try await fixture.startCompile(.first)
        let newer = try await fixture.startCompile(.second)

        let newest: Compiled
        switch finish {
        case .newestFirst:
            newest = try await fixture.succeed(newer)
            #expect(try await fixture.succeed(older).settlement == .compiled(selected: false))
        case .oldestFirst:
            #expect(try await fixture.succeed(older).settlement == .compiled(selected: false))
            // Not even before the newer one is ready: a frame that arrives now waits for the newest compile.
            let waiting = fixture.admit()
            #expect(await fixture.stillWaiting(waiting))
            newest = try await fixture.succeed(newer)
            #expect(identity(try await fixture.answer(waiting).library) == identity(newest.library))
        }
        #expect(newest.settlement == .compiled(selected: true))
        #expect(identity(try await fixture.answer(fixture.admit()).library) == identity(newest.library))
    }

    @Test("a superseded compile's success still fills the cache: beginning that effect again is a hit that selects it")
    func supersededSuccessFillsTheCache() async throws {
        let fixture = StateFixture()
        let older = try await fixture.startCompile(.first)
        let newer = try await fixture.startCompile(.second)
        _ = try await fixture.succeed(newer)
        let superseded = try await fixture.succeed(older)
        #expect(superseded.settlement == .compiled(selected: false))

        #expect(try await fixture.answer(fixture.begin(.first)) == .cached)
        #expect(identity(try await fixture.answer(fixture.admit()).library) == identity(superseded.library))
    }

    @Test("a superseded compile that finishes while a caller waits does not release it: it gets the newest effect")
    func supersededCompileDoesNotReleaseAWaitingCaller() async throws {
        let fixture = StateFixture()
        let older = try await fixture.startCompile(.first)
        let newer = try await fixture.startCompile(.second)
        let waiting = fixture.admit()

        _ = try await fixture.succeed(older)
        #expect(await fixture.stillWaiting(waiting), "the older library is not the effect it waits for")

        let newest = try await fixture.succeed(newer)
        #expect(identity(try await fixture.answer(waiting).library) == identity(newest.library))
    }

    @Test("a cache hit settles the selection: it releases a caller waiting on the compile it overtook, which then cannot take it back")
    func cacheHitReleasesAWaitingCaller() async throws {
        let fixture = StateFixture()
        let cached = try await fixture.prepared(.first)
        let slow = try await fixture.startCompile(.second)
        let waiting = fixture.admit()
        #expect(await fixture.stillWaiting(waiting), "the second effect is still compiling")

        #expect(try await fixture.answer(fixture.begin(.first)) == .cached)
        #expect(identity(try await fixture.answer(waiting).library) == identity(cached))

        #expect(try await fixture.succeed(slow).settlement == .compiled(selected: false))
        #expect(identity(try await fixture.answer(fixture.admit()).library) == identity(cached))
    }

    @Test("a compile that fails after a newer one succeeded settles as failed for its own caller and leaves the newer effect selected")
    func staleFailureLoses() async throws {
        let fixture = StateFixture()
        let older = try await fixture.startCompile(.first)
        let newer = try await fixture.startCompile(.second)
        let newest = try await fixture.succeed(newer)

        #expect(try await fixture.fail(older) == .failed(.compileFailed))
        #expect(identity(try await fixture.answer(fixture.admit()).library) == identity(newest.library))
    }

    @Test("a newer begin that fails wins too: admit answers compileFailed rather than the older effect, and it stays final")
    func newerFailureWins() async throws {
        let fixture = StateFixture()
        _ = try await fixture.prepared(.first)
        let broken = try await fixture.startCompile(.second)
        #expect(try await fixture.fail(broken) == .failed(.compileFailed))

        for index in UInt32(0)..<3 {
            let admission = try await fixture.answer(fixture.admit(Frame(index: index)))
            #expect(admission.failure == .compileFailed)
            #expect(admission.compile == nil, "a broken source is not compiled again")
        }
        #expect(fixture.fallbackReads.count == 0)
    }

    // MARK: - Waiting

    @Test("a caller waiting on a compile that fails is held back until it does, then told compileFailed")
    func waitingCallerSeesTheFailure() async throws {
        let fixture = StateFixture()
        let compile = try await fixture.startCompile(.first)
        let waiting = fixture.admit()
        #expect(await fixture.stillWaiting(waiting), "it waits for the compile instead of answering ahead of it")

        _ = try await fixture.fail(compile)
        #expect(try await fixture.answer(waiting).failure == .compileFailed)
    }

    @Test("callers waiting on one compile are released together, each with its own uniforms")
    func waitingCallersAreReleasedTogether() async throws {
        let fixture = StateFixture()
        let compile = try await fixture.startCompile(.first)
        let early = fixture.admit(Frame(index: 0, nanoseconds: 5_000_000_000))
        let late = fixture.admit(Frame(index: 1, nanoseconds: 5_250_000_000))
        #expect(await fixture.stillWaiting(early))
        #expect(await fixture.stillWaiting(late))

        let compiled = try await fixture.succeed(compile)
        let first = try await fixture.answer(early)
        let second = try await fixture.answer(late)
        #expect(identity(first.library) == identity(compiled.library))
        #expect(identity(second.library) == identity(compiled.library))
        #expect([first.uniforms.time, second.uniforms.time] == [0, 0.25])
    }

    @Test("cancelling a waiting caller cuts nothing short: it is still released with the real selection")
    func cancellationIsIgnored() async throws {
        let fixture = StateFixture()
        let compile = try await fixture.startCompile(.first)
        let waiting = fixture.admit()
        #expect(await fixture.stillWaiting(waiting))
        waiting.task.cancel()

        let compiled = try await fixture.succeed(compile)
        #expect(identity(try await fixture.answer(waiting).library) == identity(compiled.library))
    }

    // MARK: - Nothing prepared: the fallback

    @Test("with nothing prepared, admit hands back the fallback to compile; a caller meeting that compile waits for it")
    func fallbackCompile() async throws {
        let fixture = StateFixture()
        let first = try await fixture.answer(fixture.admit())
        let compile = try #require(first.compile)
        #expect(compile.effect == .bundled)
        #expect(fixture.fallbackReads.count == 1)

        let second = fixture.admit(Frame(index: 1))
        #expect(await fixture.stillWaiting(second), "it joins the compile instead of starting its own")
        #expect(fixture.fallbackReads.count == 1)

        let compiled = try await fixture.succeed(compile)
        #expect(compiled.settlement == .compiled(selected: true))
        #expect(identity(try await fixture.answer(second).library) == identity(compiled.library))
        #expect(identity(try await fixture.answer(fixture.selected()).library) == identity(compiled.library))
        #expect(fixture.fallbackReads.count == 1)
    }

    @Test("selected waits for the compile to settle and answers at once afterwards")
    func selectedWaits() async throws {
        let fixture = StateFixture()
        let compile = try #require(try await fixture.answer(fixture.admit()).compile)
        let waiting = fixture.selected()
        #expect(await fixture.stillWaiting(waiting))

        let compiled = try await fixture.succeed(compile)
        #expect(identity(try await fixture.answer(waiting).library) == identity(compiled.library))
        #expect(identity(try await fixture.answer(fixture.selected()).library) == identity(compiled.library))
    }

    @Test("a begin during the fallback's compile wins: the fallback's late success is cached but not selected")
    func beginOvertakesTheFallbackCompile() async throws {
        let fixture = StateFixture()
        let fallback = try #require(try await fixture.answer(fixture.admit()).compile)
        let prepared = try await fixture.prepared(.first)

        #expect(try await fixture.succeed(fallback).settlement == .compiled(selected: false))
        #expect(identity(try await fixture.answer(fixture.selected()).library) == identity(prepared))
    }

    @Test("a broken fallback compiles once: every admit after it is told compileFailed, and the fallback is not asked again")
    func brokenFallback() async throws {
        let fixture = StateFixture()
        let compile = try #require(try await fixture.answer(fixture.admit()).compile)
        #expect(try await fixture.fail(compile) == .failed(.compileFailed))

        let admission = try await fixture.answer(fixture.admit(Frame(index: 1)))
        #expect(admission.failure == .compileFailed)
        #expect(admission.compile == nil)
        #expect(fixture.fallbackReads.count == 1)
    }

    // MARK: - No GPU context

    @Test("a compile that found no GPU context is not final: the next admit hands that same effect back, not the fallback")
    func contextFailureIsRetried() async throws {
        let fixture = StateFixture()
        let compile = try await fixture.startCompile(.first)
        #expect(try await fixture.fail(compile, cause: .environment) == .failed(.internalError), "the runtime failed, not the effect")

        let retry = try #require(try await fixture.answer(fixture.admit()).compile)
        #expect(retry.effect == .first)
        #expect(retry.ticket != compile.ticket)
        #expect(fixture.fallbackReads.count == 0)

        let compiled = try await fixture.succeed(retry)
        #expect(identity(try await fixture.answer(fixture.admit(Frame(index: 1))).library) == identity(compiled.library))
    }

    @Test("the fallback's compile is retried the same way, and the fallback is asked only once")
    func fallbackContextFailureIsRetried() async throws {
        let fixture = StateFixture()
        let compile = try #require(try await fixture.answer(fixture.admit()).compile)
        _ = try await fixture.fail(compile, cause: .environment)

        let retry = try #require(try await fixture.answer(fixture.admit(Frame(index: 1))).compile)
        #expect(retry.effect == .bundled)
        #expect(retry.ticket != compile.ticket)
        #expect(fixture.fallbackReads.count == 1)
    }

    @Test("a caller waiting on a compile that found no GPU context is released with internalError, not left waiting")
    func waitingCallerIsReleasedWhenTheContextIsMissing() async throws {
        let fixture = StateFixture()
        let compile = try await fixture.startCompile(.first)
        let waiting = fixture.admit()
        #expect(await fixture.stillWaiting(waiting))

        _ = try await fixture.fail(compile, cause: .environment)
        #expect(try await fixture.answer(waiting).failure == .internalError)
    }

    @Test("a superseded compile that found no GPU context settles as internalError and leaves the newer effect selected")
    func supersededContextFailureLoses() async throws {
        let fixture = StateFixture()
        let older = try await fixture.startCompile(.first)
        let newer = try await fixture.startCompile(.second)
        let newest = try await fixture.succeed(newer)

        #expect(try await fixture.fail(older, cause: .environment) == .failed(.internalError))
        let admission = try await fixture.answer(fixture.admit())
        #expect(identity(admission.library) == identity(newest.library))
        #expect(admission.compile == nil, "the older effect is not retried over the newer one")
    }

    @Test("the retry finds the library a superseded compile of the same source cached meanwhile, and compiles nothing")
    func retryHitsTheCache() async throws {
        let fixture = StateFixture()
        let older = try await fixture.startCompile(.first)
        let newer = try await fixture.startCompile(.first)
        let superseded = try await fixture.succeed(older)
        #expect(superseded.settlement == .compiled(selected: false))
        _ = try await fixture.fail(newer, cause: .environment)

        let admission = try await fixture.answer(fixture.admit())
        #expect(admission.compile == nil)
        #expect(identity(admission.library) == identity(superseded.library))
    }

    // MARK: - Uniforms and the session

    @Test("the uniforms: seconds since the session's first frame, the caller's frame index, the output's size, seed 0")
    func uniforms() async throws {
        let fixture = StateFixture()
        _ = try await fixture.prepared(.first)
        // A run starting at 5 s, a frame stamped before it, then a restart (index 0 again) at 100 s.
        let frames: [(index: UInt32, nanoseconds: UInt64)] = [
            (0, 5_000_000_000), (1, 5_500_000_000), (2, 7_250_000_000), (3, 4_000_000_000), (0, 100_000_000_000), (1, 100_040_000_000),
        ]
        let admitted = Collector<EffectUniforms>()
        for frame in frames {
            admitted.append(try await fixture.answer(fixture.admit(Frame(index: frame.index, nanoseconds: frame.nanoseconds))).uniforms)
        }

        let uniforms = admitted.values
        #expect(uniforms.map(\.time) == [0, 0.5, 2.25, 0, 0, 0.04])
        #expect(uniforms.map(\.frameIndex) == frames.map(\.index))
        #expect(uniforms.allSatisfy { $0.resolution == SIMD2(640, 360) && $0.seed == 0 })
    }

    @Test("a session that did not start at index 0 starts at the first frame the state is handed")
    func sessionStartsAtTheFirstFrame() async throws {
        let fixture = StateFixture()
        _ = try await fixture.prepared(.first)
        let times = [
            try await fixture.answer(fixture.admit(Frame(index: 7, nanoseconds: 20_000_000_000))).uniforms.time,
            try await fixture.answer(fixture.admit(Frame(index: 8, nanoseconds: 21_500_000_000))).uniforms.time,
        ]
        #expect(times == [0, 1.5])
    }
}
