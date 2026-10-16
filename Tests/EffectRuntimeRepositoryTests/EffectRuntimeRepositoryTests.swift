import Domain
import EffectRuntimeRepository
import TestDoubles
import TestSupport
import Testing

/// The Repository over the real `EffectRuntimeStateDataSource`, against
/// `FakeShaderCompiler` and `FakeGPURenderer`: the test decides when each compile and
/// each pass ends, and drains the executor the state decides on, so every
/// interleaving below is written down rather than waited for. This suite owns what
/// the Repository decides — which port each call goes through, what it maps and logs,
/// and that the whole stack still behaves as one runtime. The rules of the state
/// itself (the cache, tickets, waiting, retrying, the session clock) are proven
/// through its port in `EffectRuntimeStateDataSourceTests`.
@Suite("EffectRuntimeRepository", .timeLimit(.minutes(1)))
@MainActor
struct EffectRuntimeRepositoryTests {
    // MARK: - Executor confinement

    @Test("nothing is decided before the executor runs the runtime's step: no compile starts until the drain")
    func compileWaitsForTheExecutor() async throws {
        let fixture = RuntimeFixture()
        let call = fixture.prepare(.first)
        await fixture.executor.enqueued.waitForCount(1)

        #expect(fixture.compiler.requests.count == 0)
        #expect(fixture.executor.drain() == 1)
        // The step has taken the ticket; the compile starts on the prepare's own task.
        await fixture.compiler.requests.waitForCount(1)
        #expect(fixture.compiler.requests.values.map(\.effect) == [.first])
        _ = try await fixture.succeedCompile(1)
        #expect(await fixture.answer(call) == .success)
    }

    // MARK: - Cache

    @Test("an effect compiles once: preparing it again is a cache hit that compiles nothing and runs the same library")
    func cacheHit() async throws {
        let fixture = RuntimeFixture()
        let library = try await fixture.prepared(.first)

        #expect(await fixture.answer(fixture.prepare(.first)) == .success)
        #expect(fixture.compiler.requests.count == 1, "the second prepare was a hit")
        #expect(fixture.log.messages(in: .effect) == ["effect 'first' compiled"], "logged once, as selected, and not for the hit")

        fixture.renderer.respond(with: .success(.sample))
        #expect(await fixture.answer(fixture.apply()) == .success)
        let pass = try #require(fixture.renderer.requests.values.only)
        #expect(identity(pass.library) == identity(library))
    }

    // MARK: - Newest wins

    /// Which of two overlapping compiles finishes first.
    enum Finish: String, Sendable, CaseIterable, CustomTestStringConvertible {
        case newestFirst = "the newer compile finishes first"
        case oldestFirst = "the older compile finishes first"
        var testDescription: String { rawValue }
    }

    @Test(
        "newest wins: a slow compile overtaken by a newer prepare answers its own outcome but never becomes the effect apply runs",
        arguments: Finish.allCases
    )
    func newestWins(_ finish: Finish) async throws {
        let fixture = RuntimeFixture()
        let older = fixture.prepare(.first)
        let olderRequest = try #require(await fixture.compileRequest(1))
        let newer = fixture.prepare(.second)
        let newerRequest = try #require(await fixture.compileRequest(2))
        #expect(newerRequest.effect == .second)

        let newest: FakeLibraryHandle
        switch finish {
        case .newestFirst:
            newest = try #require(fixture.compiler.succeed(newerRequest))
            #expect(await fixture.answer(newer) == .success)
            #expect(fixture.compiler.succeed(olderRequest) != nil)
            #expect(await fixture.answer(older) == .success, "its compile succeeded; it lost only the selection")
        case .oldestFirst:
            #expect(fixture.compiler.succeed(olderRequest) != nil)
            #expect(await fixture.answer(older) == .success)
            // The older effect never runs, not even before the newer one is ready: a
            // frame that arrives now waits for the newest compile.
            let waiting = await fixture.applyQueued()
            #expect(await fixture.stillWaiting(waiting), "the apply waits for the newest compile")
            #expect(fixture.renderer.requests.count == 0)
            newest = try #require(fixture.compiler.succeed(newerRequest))
            #expect(await fixture.answer(newer) == .success)
            let pass = try #require(await fixture.renderRequest(1))
            #expect(identity(pass.library) == identity(newest))
            #expect(fixture.renderer.complete(pass, with: .success(.sample)))
            #expect(await fixture.answer(waiting) == .success)
        }

        fixture.renderer.respond(with: .success(.sample))
        #expect(await fixture.answer(fixture.apply(Frame(index: 1))) == .success)
        #expect(identity(try #require(fixture.renderer.requests.last).library) == identity(newest))
        #expect(fixture.log.contains("effect 'first' compiled, but a newer one was prepared since"), "superseded in either order")
    }

    // MARK: - Compile failure

    @Test("a compile failure is compileFailed from prepare and from every apply after it, without rendering or compiling again")
    func compileFailurePropagates() async throws {
        let fixture = RuntimeFixture()
        let prepare = fixture.prepare(.first)
        try await fixture.failCompile(1, message: "effect:3:5: error: use of undeclared identifier 'oops'")
        #expect(await fixture.answer(prepare) == .failure(.compileFailed))
        #expect(fixture.log.messages(in: .effect) == ["effect 'first' did not compile: effect:3:5: error: use of undeclared identifier 'oops'"])

        for index in UInt32(0)..<3 {
            #expect(await fixture.answer(fixture.apply(Frame(index: index))) == .failure(.compileFailed))
        }
        #expect(fixture.renderer.requests.count == 0)
        #expect(fixture.compiler.requests.count == 1)
    }

    // MARK: - No GPU context

    @Test("a compile that found no GPU context is not final: prepare answers internalError, the next apply compiles that effect again")
    func contextFailureIsRetried() async throws {
        let fixture = RuntimeFixture()
        let prepare = fixture.prepare(.first)
        try await fixture.failCompileForWantOfAContext(1)
        #expect(await fixture.answer(prepare) == .failure(.internalError), "the runtime failed, not the effect")
        #expect(fixture.log.messages(in: .effect) == ["effect 'first' did not compile: no GPU context to compile on: noDevice"])

        // The prepared effect is the one retried, not the bundled one.
        fixture.renderer.respond(with: .success(.sample))
        let apply = fixture.apply()
        let library = try await fixture.succeedCompile(2)
        #expect(fixture.compiler.requests.values.map(\.effect) == [.first, .first])
        #expect(await fixture.answer(apply) == .success)
        #expect(identity(try #require(fixture.renderer.requests.values.only).library) == identity(library))
        #expect(await fixture.compilesFinished(1), "the prepare's compile was awaited; only the apply's ran on the work runner")
        #expect(
            fixture.log.messages(in: .effect) == [
                "effect 'first' did not compile: no GPU context to compile on: noDevice",
                "effect 'first' compiled after 1 failed attempt for environment reasons",
            ], "a streak of one is reported in the singular")

        // Once it compiled, it is cached like any other.
        #expect(await fixture.answer(fixture.apply(Frame(index: 1))) == .success)
        #expect(fixture.compiler.requests.count == 2)
    }

    @Test("with the bundled effect, a missing context answers internalError for that frame and the next frame compiles it again")
    func bundledContextFailureIsRetried() async throws {
        let fixture = RuntimeFixture()
        let first = fixture.apply()
        try await fixture.failCompileForWantOfAContext(1)
        #expect(await fixture.answer(first) == .failure(.internalError))

        fixture.renderer.respond(with: .success(.sample))
        let second = fixture.apply(Frame(index: 1))
        let library = try await fixture.succeedCompile(2)
        #expect(fixture.compiler.requests.values.map(\.effect) == [.bundled, .bundled])
        #expect(await fixture.answer(second) == .success)
        #expect(identity(try #require(fixture.renderer.requests.values.only).library) == identity(library))
    }

    @Test("a source that does not compile stays final: later frames answer compileFailed without compiling again")
    func sourceFailureStaysFinal() async throws {
        let fixture = RuntimeFixture()
        let prepare = fixture.prepare(.first)
        try await fixture.failCompile(1)
        #expect(await fixture.answer(prepare) == .failure(.compileFailed))
        #expect(await fixture.answer(fixture.apply()) == .failure(.compileFailed))
        #expect(fixture.compiler.requests.count == 1)
    }

    @Test("a cache-hit prepare answers an apply that is retrying a compile: that apply does not wait for the compile")
    func cacheHitAnswersARetryingApply() async throws {
        let fixture = RuntimeFixture()
        let cached = try await fixture.prepared(.first)
        let broken = fixture.prepare(.second)
        try await fixture.failCompileForWantOfAContext(2)
        #expect(await fixture.answer(broken) == .failure(.internalError))

        let apply = fixture.apply()
        let retry = try #require(await fixture.compileRequest(3))
        #expect(retry.effect == .second, "the prepared effect is the one retried")
        #expect(await fixture.stillWaiting(apply), "nothing is settled while the retry runs")

        #expect(await fixture.answer(fixture.prepare(.first)) == .success, "a hit settles at once")
        let pass = try #require(await fixture.renderRequest(1))
        #expect(identity(pass.library) == identity(cached))
        #expect(fixture.compiler.pendingCount == 1, "the retry has not ended")
        #expect(fixture.renderer.complete(pass, with: .success(.sample)))
        #expect(await fixture.answer(apply) == .success)

        // The retry ends late: it fills the cache but does not take the selection back.
        let late = try #require(fixture.compiler.succeed(retry))
        #expect(await fixture.compilesFinished(1))
        fixture.renderer.respond(with: .success(.sample))
        #expect(await fixture.answer(fixture.apply(Frame(index: 1))) == .success)
        #expect(identity(try #require(fixture.renderer.requests.last).library) == identity(cached))
        #expect(await fixture.answer(fixture.prepare(.second)) == .success, "the late success filled the cache")
        #expect(fixture.compiler.requests.count == 3)
        #expect(identity(late) != identity(cached))
    }

    @Test("a missing GPU context is logged once while every frame retries, and the recovery says how many attempts it took")
    func contextFailureIsLoggedOncePerStreak() async throws {
        let fixture = RuntimeFixture()
        let failure = "effect 'bundled' did not compile: no GPU context to compile on: noDevice"
        for number in 1...3 {
            let frame = fixture.apply(Frame(index: UInt32(number - 1)))
            try await fixture.failCompileForWantOfAContext(number)
            #expect(await fixture.answer(frame) == .failure(.internalError))
        }
        #expect(await fixture.compilesFinished(3))
        #expect(fixture.log.messages(in: .effect) == [failure], "the retries of one streak are counted, not logged")

        fixture.renderer.respond(with: .success(.sample))
        let recovered = fixture.apply(Frame(index: 3))
        _ = try await fixture.succeedCompile(4)
        #expect(await fixture.answer(recovered) == .success)
        #expect(await fixture.compilesFinished(4))
        #expect(fixture.log.messages(in: .effect) == [failure, "effect 'bundled' compiled after 3 failed attempts for environment reasons"])
    }

    @Test("a prepare after a streak starts a new one: its first GPU-context failure is logged again")
    func aNewPrepareLogsItsOwnFirstFailure() async throws {
        let fixture = RuntimeFixture()
        let first = fixture.prepare(.first)
        try await fixture.failCompileForWantOfAContext(1)
        #expect(await fixture.answer(first) == .failure(.internalError))
        let retried = fixture.apply()
        try await fixture.failCompileForWantOfAContext(2)
        #expect(await fixture.answer(retried) == .failure(.internalError))

        let second = fixture.prepare(.second)
        try await fixture.failCompileForWantOfAContext(3)
        #expect(await fixture.answer(second) == .failure(.internalError))
        #expect(await fixture.compilesFinished(1))
        #expect(
            fixture.log.messages(in: .effect) == [
                "effect 'first' did not compile: no GPU context to compile on: noDevice",
                "effect 'second' did not compile: no GPU context to compile on: noDevice",
            ])
    }

    // MARK: - The bundled default

    @Test("with nothing prepared, the first apply compiles the bundled effect, waits for it and renders with it; later frames reuse it")
    func bundledDefault() async throws {
        let fixture = RuntimeFixture()
        let first = fixture.apply()
        let request = try #require(await fixture.compileRequest(1))
        #expect(request.effect == .bundled)
        #expect(await fixture.stillWaiting(first), "nothing to render before the compile settles")
        #expect(fixture.renderer.requests.count == 0)

        let library = try #require(fixture.compiler.succeed(request))
        let pass = try #require(await fixture.renderRequest(1))
        #expect(identity(pass.library) == identity(library))
        #expect(fixture.renderer.complete(pass, with: .success(.sample)))
        #expect(await fixture.answer(first) == .success)

        fixture.renderer.respond(with: .success(.sample))
        #expect(await fixture.answer(fixture.apply(Frame(index: 1))) == .success)
        #expect(fixture.compiler.requests.count == 1)
        #expect(identity(try #require(fixture.renderer.requests.last).library) == identity(library))
    }

    @Test("a broken bundled effect compiles once and every apply answers compileFailed, so the pipeline passes frames through")
    func brokenBundledEffect() async throws {
        let fixture = RuntimeFixture()
        let first = fixture.apply()
        try await fixture.failCompile(1)
        #expect(await fixture.answer(first) == .failure(.compileFailed))
        #expect(await fixture.answer(fixture.apply(Frame(index: 1))) == .failure(.compileFailed))
        #expect(fixture.compiler.requests.count == 1)
        #expect(fixture.renderer.requests.count == 0)
    }

    @Test("an apply arriving while the bundled effect compiles waits for that same compile")
    func secondApplyJoinsTheBundledCompile() async throws {
        let fixture = RuntimeFixture()
        let first = fixture.apply()
        let request = try #require(await fixture.compileRequest(1))
        let second = await fixture.applyQueued(Frame(index: 1))
        #expect(await fixture.stillWaiting(second))
        #expect(fixture.compiler.requests.count == 1, "it joined the compile instead of starting its own")

        fixture.renderer.respond(with: .success(.sample))
        let library = try #require(fixture.compiler.succeed(request))
        #expect(await fixture.answer(first) == .success)
        #expect(await fixture.answer(second) == .success)
        #expect(fixture.renderer.requests.values.map { identity($0.library) } == [identity(library), identity(library)])
    }

    @Test("a prepare during the bundled compile wins: the apply that started that compile does not wait for it and runs the prepared effect")
    func prepareOvertakesTheBundledCompile() async throws {
        let fixture = RuntimeFixture()
        let apply = fixture.apply()
        let bundledRequest = try #require(await fixture.compileRequest(1))
        let prepare = fixture.prepare(.first)
        let prepared = try await fixture.succeedCompile(2)
        #expect(await fixture.answer(prepare) == .success)

        // The newer effect has settled, so the apply goes on while the bundled compile still runs.
        let pass = try #require(await fixture.renderRequest(1))
        #expect(identity(pass.library) == identity(prepared))
        #expect(fixture.compiler.pendingCount == 1, "the bundled compile has not ended")
        #expect(fixture.renderer.complete(pass, with: .success(.sample)))
        #expect(await fixture.answer(apply) == .success)

        // It ends late: cached and logged as superseded, and nothing renders it.
        let bundled = try #require(fixture.compiler.succeed(bundledRequest))
        #expect(await fixture.compilesFinished(1))
        #expect(fixture.log.contains("effect 'bundled' compiled, but a newer one was prepared since"))
        #expect(fixture.renderer.requests.count == 1)
        #expect(await fixture.answer(fixture.prepare(.bundled)) == .success, "the late success filled the cache")
        fixture.renderer.respond(with: .success(.sample))
        #expect(await fixture.answer(fixture.apply(Frame(index: 1))) == .success)
        #expect(identity(try #require(fixture.renderer.requests.last).library) == identity(bundled))
    }

    // MARK: - The pass

    @Test(
        "apply hands the renderer the library and both leases' tokens and answers with the pass's outcome",
        arguments: [
            Result<GPUTiming, EffectFailure>.success(.sample), .failure(.timeout), .failure(.pageFault), .failure(.invalidResource),
            .failure(.unknown(code: 77)),
        ]
    )
    func passOutcome(_ outcome: Result<GPUTiming, EffectFailure>) async throws {
        let fixture = RuntimeFixture()
        let library = try await fixture.prepared(.first)
        let frame = Frame(index: 4)
        let call = fixture.apply(frame)

        let pass = try #require(await fixture.renderRequest(1))
        #expect(identity(pass.library) == identity(library))
        #expect(pass.input == frame.input.token)
        #expect(pass.output == frame.output.token)
        #expect(call.answered.count == 0, "apply answers only when the pass does")
        #expect(fixture.renderer.complete(pass, with: outcome))
        #expect(await fixture.answer(call) == Reply(outcome))
    }

    @Test("the uniforms: seconds since the session's first frame, the caller's frame index, the output's size, seed 0")
    func uniforms() async throws {
        let fixture = RuntimeFixture()
        _ = try await fixture.prepared(.first)
        fixture.renderer.respond(with: .success(.sample))
        // A run starting at 5 s, a frame stamped before it, then a restart (index 0 again) at 100 s.
        let frames: [(index: UInt32, nanoseconds: UInt64)] = [
            (0, 5_000_000_000), (1, 5_500_000_000), (2, 7_250_000_000), (3, 4_000_000_000), (0, 100_000_000_000), (1, 100_040_000_000),
        ]
        for frame in frames {
            #expect(await fixture.answer(fixture.apply(Frame(index: frame.index, nanoseconds: frame.nanoseconds))) == .success)
        }

        let uniforms = fixture.renderer.requests.values.map(\.uniforms)
        #expect(uniforms.map(\.time) == [0, 0.5, 2.25, 0, 0, 0.04])
        #expect(uniforms.map(\.frameIndex) == frames.map(\.index))
        #expect(uniforms.allSatisfy { $0.resolution == SIMD2(640, 360) && $0.seed == 0 })
    }

    // MARK: - Cancellation

    @Test("cancelling the caller cuts nothing short: a cancelled prepare and a cancelled apply still answer with the real outcome")
    func cancellationIsIgnored() async throws {
        let fixture = RuntimeFixture()
        let prepare = fixture.prepare(.first)
        let request = try #require(await fixture.compileRequest(1))
        prepare.task.cancel()
        let library = try #require(fixture.compiler.succeed(request))
        #expect(await fixture.answer(prepare) == .success)

        let apply = fixture.apply()
        let pass = try #require(await fixture.renderRequest(1))
        apply.task.cancel()
        #expect(identity(pass.library) == identity(library))
        #expect(fixture.renderer.complete(pass, with: .failure(.pageFault)))
        #expect(await fixture.answer(apply) == .failure(.pageFault))
    }
}

extension Array {
    /// The single element, or `nil` when there is none or more than one.
    fileprivate var only: Element? { count == 1 ? first : nil }
}
