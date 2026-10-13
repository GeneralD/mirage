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

    @Test("a prepare during the bundled compile wins: the apply that started that compile runs the prepared effect")
    func prepareOvertakesTheBundledCompile() async throws {
        let fixture = RuntimeFixture()
        let apply = fixture.apply()
        let bundledRequest = try #require(await fixture.compileRequest(1))
        let prepare = fixture.prepare(.first)
        let prepared = try await fixture.succeedCompile(2)
        #expect(await fixture.answer(prepare) == .success)

        fixture.renderer.respond(with: .success(.sample))
        #expect(fixture.compiler.succeed(bundledRequest) != nil)
        #expect(await fixture.answer(apply) == .success)
        #expect(identity(try #require(fixture.renderer.requests.values.only).library) == identity(prepared))
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
