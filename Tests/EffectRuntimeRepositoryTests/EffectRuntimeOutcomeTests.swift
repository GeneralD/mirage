import Domain
import EffectRuntimeRepository
import TestDoubles
import TestSupport
import Testing

/// What the Repository reports of each `apply`: the pass's timing or failure, stamped with the
/// fingerprint of the effect the pass ran, told to the state's stream before the answer is narrowed to
/// the `Result<Void, EffectFailure>` the pipeline gets. The stream itself (its order, its 64-outcome
/// backlog, who gets what) is proven through the state's port in `PassOutcomeTests`; this suite owns
/// which outcome each kind of pass reports, and that the whole stack answers as it did before.
@Suite("EffectRuntimeRepository outcomes", .timeLimit(.minutes(1)))
@MainActor
struct EffectRuntimeOutcomeTests {
    // MARK: - What a pass reports

    @Test("a pass that rendered reports its timing, stamped with the effect that ran it, and apply still answers success")
    func renderedPassReportsItsTiming() async throws {
        let fixture = RuntimeFixture()
        _ = try await fixture.prepared(.first)
        let watch = fixture.watchOutcomes()
        defer { watch.stop() }

        fixture.renderer.respond(with: .success(.sample))
        #expect(await fixture.answer(fixture.apply()) == .success)
        #expect(
            try #require(await fixture.delivered(1, to: watch)) == [EffectPassOutcome(fingerprint: .of(.first), result: .success(.sample))])
    }

    @Test(
        "a pass the GPU failed reports the failure with the same stamp, and apply answers that failure to the pipeline unchanged",
        arguments: [EffectFailure.timeout, .pageFault, .accessRevoked, .outOfMemory, .invalidResource, .unknown(code: 77)]
    )
    func failedPassReportsItsFailure(_ failure: EffectFailure) async throws {
        let fixture = RuntimeFixture()
        _ = try await fixture.prepared(.first)
        let watch = fixture.watchOutcomes()
        defer { watch.stop() }

        fixture.renderer.respond(with: .failure(failure))
        #expect(await fixture.answer(fixture.apply()) == .failure(failure))
        #expect(try #require(await fixture.delivered(1, to: watch)) == [EffectPassOutcome(fingerprint: .of(.first), result: .failure(failure))])
    }

    @Test("a selection that is itself a failure is reported too, once per frame and stamped with the effect that did not compile")
    func compileFailureIsReportedPerFrame() async throws {
        let fixture = RuntimeFixture()
        let prepare = fixture.prepare(.first)
        try await fixture.failCompile(1)
        #expect(await fixture.answer(prepare) == .failure(.compileFailed))
        let watch = fixture.watchOutcomes()
        defer { watch.stop() }

        for index in UInt32(0)..<2 {
            #expect(await fixture.answer(fixture.apply(Frame(index: index))) == .failure(.compileFailed))
        }
        let failure = EffectPassOutcome(fingerprint: .of(.first), result: .failure(.compileFailed))
        #expect(try #require(await fixture.delivered(2, to: watch)) == [failure, failure])
        #expect(fixture.renderer.requests.count == 0, "nothing rendered")
    }

    @Test("a frame that found no GPU context to compile on reports internalError for the effect it tried")
    func contextFailureIsReported() async throws {
        let fixture = RuntimeFixture()
        let watch = fixture.watchOutcomes()
        defer { watch.stop() }

        let apply = fixture.apply()
        try await fixture.failCompileForWantOfAContext(1)
        #expect(await fixture.answer(apply) == .failure(.internalError))
        #expect(
            try #require(await fixture.delivered(1, to: watch)) == [EffectPassOutcome(fingerprint: .of(.bundled), result: .failure(.internalError))]
        )
    }

    // MARK: - Whose outcome it is

    @Test("a pass admitted under one effect is that effect's outcome even when another is selected before the pass ends")
    func lateOutcomeBelongsToTheEffectItRan() async throws {
        let fixture = RuntimeFixture()
        _ = try await fixture.prepared(.first)
        let watch = fixture.watchOutcomes()
        defer { watch.stop() }
        let late = GPUTiming(gpuStart: 20, gpuEnd: 20.5)

        let slow = fixture.apply()
        let pass = try #require(await fixture.renderRequest(1), "the pass is on the GPU, admitted under the first effect")
        _ = try await fixture.prepared(.second)
        #expect(fixture.renderer.complete(pass, with: .failure(.timeout)))
        #expect(await fixture.answer(slow) == .failure(.timeout))

        fixture.renderer.respond(with: .success(late))
        #expect(await fixture.answer(fixture.apply(Frame(index: 1))) == .success)
        #expect(
            try #require(await fixture.delivered(2, to: watch)) == [
                EffectPassOutcome(fingerprint: .of(.first), result: .failure(.timeout)),
                EffectPassOutcome(fingerprint: .of(.second), result: .success(late)),
            ], "the late timeout is the first effect's, not the second's that was selected when it ended")
    }

    @Test("with nothing prepared, a pass is stamped with the bundled effect that the apply compiled")
    func bundledPassIsStampedWithTheBundledEffect() async throws {
        let fixture = RuntimeFixture()
        let watch = fixture.watchOutcomes()
        defer { watch.stop() }

        let apply = fixture.apply()
        let request = try #require(await fixture.compileRequest(1))
        #expect(fixture.compiler.succeed(request) != nil)
        let pass = try #require(await fixture.renderRequest(1))
        #expect(fixture.renderer.complete(pass, with: .success(.sample)))
        #expect(await fixture.answer(apply) == .success)

        #expect(
            try #require(await fixture.delivered(1, to: watch)) == [EffectPassOutcome(fingerprint: .of(.bundled), result: .success(.sample))])
    }

    @Test("an apply that started the bundled compile but was overtaken by a prepare is stamped with the prepared effect it ran")
    func overtakenFallbackIsStampedWithTheNewerEffect() async throws {
        let fixture = RuntimeFixture()
        let watch = fixture.watchOutcomes()
        defer { watch.stop() }
        let apply = fixture.apply()
        let bundledRequest = try #require(await fixture.compileRequest(1))
        let prepare = fixture.prepare(.first)
        _ = try await fixture.succeedCompile(2)
        #expect(await fixture.answer(prepare) == .success)

        let pass = try #require(await fixture.renderRequest(1))
        #expect(fixture.renderer.complete(pass, with: .success(.sample)))
        #expect(await fixture.answer(apply) == .success)
        #expect(
            try #require(await fixture.delivered(1, to: watch)) == [EffectPassOutcome(fingerprint: .of(.first), result: .success(.sample))],
            "the library it ran was the first effect's, so was the stamp")

        // The bundled compile ends late, as the test above it in the Repository suite shows.
        #expect(fixture.compiler.succeed(bundledRequest) != nil)
        #expect(await fixture.compilesFinished(1))
    }

    // MARK: - The frame path never waits for the observer

    @Test("an observer that never reads does not hold up apply: seventy passes answer, and the stream keeps the newest 64")
    func unreadStreamDoesNotHoldUpApply() async throws {
        let fixture = RuntimeFixture()
        _ = try await fixture.prepared(.first)
        let stream = fixture.subject.outcomes()
        let timings = (0..<70).map { GPUTiming(gpuStart: Double($0), gpuEnd: Double($0) + 0.004) }

        for (index, timing) in timings.enumerated() {
            fixture.renderer.respond(with: .success(timing))
            #expect(await fixture.answer(fixture.apply(Frame(index: UInt32(index)))) == .success, "pass \(index) was not held up")
        }
        // The last report was queued before its apply answered; the executor delivers it now.
        fixture.executor.drain()
        let kept = await fixture.read(64, from: stream).compactMap { try? $0.result.get() }
        #expect(kept == Array(timings.suffix(64)), "the oldest six were dropped, the rest arrive in order")
    }

    @Test("outcomes() opens a stream for each call: two observers both see the pass")
    func eachObserverSeesEveryPass() async throws {
        let fixture = RuntimeFixture()
        _ = try await fixture.prepared(.first)
        let first = fixture.watchOutcomes()
        let second = fixture.watchOutcomes()
        defer {
            first.stop()
            second.stop()
        }

        fixture.renderer.respond(with: .success(.sample))
        #expect(await fixture.answer(fixture.apply()) == .success)
        let outcome = EffectPassOutcome(fingerprint: .of(.first), result: .success(.sample))
        #expect(try #require(await fixture.delivered(1, to: first)) == [outcome])
        #expect(try #require(await fixture.delivered(1, to: second)) == [outcome])
    }
}
