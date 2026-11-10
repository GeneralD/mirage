import Domain
import EffectRuntimeStateDataSource
import TestDoubles
import TestSupport
import Testing

/// The stream of how passes ended, which lives in the state so that it is confined to the executor
/// like everything else the state remembers: `report` queues, the executor delivers to every open
/// stream, and a stream keeps the newest 64 outcomes nobody has read. The test plays the pipeline's
/// side, reporting what it likes, and the observer's, reading on a task of its own.
@Suite("EffectRuntimeState outcomes", .timeLimit(.minutes(1)))
@MainActor
struct PassOutcomeTests {
    private static func passed(_ effect: EffectSource, seconds: Double = 0.004) -> EffectPassOutcome {
        EffectPassOutcome(fingerprint: .of(effect), result: .success(GPUTiming(gpuStart: 10, gpuEnd: 10 + seconds)))
    }

    private static func failed(_ effect: EffectSource, _ failure: EffectFailure) -> EffectPassOutcome {
        EffectPassOutcome(fingerprint: .of(effect), result: .failure(failure))
    }

    // MARK: - Executor confinement

    @Test("report is queued, not run: the call returns at once and nothing reaches a stream until the executor runs it")
    func reportIsQueued() async throws {
        let fixture = StateFixture()
        let watch = fixture.watchOutcomes()
        defer { watch.stop() }
        fixture.executor.drain()
        let queued = fixture.executor.pendingCount

        fixture.report(Self.passed(.first))
        #expect(fixture.executor.pendingCount == queued + 1, "queued on the executor, not run on this thread")
        #expect(watch.delivered.count == 0)

        #expect(try #require(await fixture.delivered(1, to: watch)) == [Self.passed(.first)])
    }

    @Test("a report made right after outcomes() returns reaches the stream, before anything has been drained")
    func openingIsOrderedWithTheReports() async throws {
        let fixture = StateFixture()
        let watch = fixture.watchOutcomes()
        defer { watch.stop() }
        fixture.report(Self.passed(.first))

        #expect(fixture.executor.pendingCount == 2, "the registration and the report, in that order")
        #expect(try #require(await fixture.delivered(1, to: watch)) == [Self.passed(.first)])
    }

    @Test("a report with nobody listening is harmless: the executor runs it and nothing else happens")
    func reportWithoutObservers() {
        let fixture = StateFixture()
        fixture.report(Self.passed(.first))
        #expect(fixture.executor.drain() == 1)
    }

    // MARK: - What arrives

    @Test("outcomes arrive in the order they were reported, each with its stamp and its result untouched")
    func orderAndContent() async throws {
        let fixture = StateFixture()
        let watch = fixture.watchOutcomes()
        defer { watch.stop() }
        let reported = [
            Self.passed(.first),
            Self.failed(.first, .timeout),
            Self.failed(.second, .unknown(code: 77)),
            Self.passed(.second, seconds: 0.2),
        ]
        for outcome in reported { fixture.report(outcome) }

        #expect(try #require(await fixture.delivered(4, to: watch)) == reported)
    }

    @Test("every open stream gets every outcome: two observers do not split them between them")
    func streamsAreIndependent() async throws {
        let fixture = StateFixture()
        let first = fixture.watchOutcomes()
        let second = fixture.watchOutcomes()
        defer {
            first.stop()
            second.stop()
        }
        let reported = [Self.passed(.first), Self.failed(.first, .pageFault), Self.passed(.second)]
        for outcome in reported { fixture.report(outcome) }

        #expect(try #require(await fixture.delivered(3, to: first)) == reported)
        #expect(try #require(await fixture.delivered(3, to: second)) == reported)
    }

    @Test("a stream replays nothing: an outcome reported before it was opened is not delivered to it")
    func noReplay() async throws {
        let fixture = StateFixture()
        fixture.report(Self.passed(.first))
        fixture.executor.drain()

        let watch = fixture.watchOutcomes()
        defer { watch.stop() }
        fixture.report(Self.passed(.second))
        #expect(try #require(await fixture.delivered(1, to: watch)) == [Self.passed(.second)])
    }

    @Test("a consumer that lets go is forgotten through the executor, and the streams that remain go on receiving")
    func finishedStreamIsForgotten() async throws {
        let fixture = StateFixture()
        let leaving = fixture.watchOutcomes()
        let staying = fixture.watchOutcomes()
        defer { staying.stop() }
        fixture.report(Self.passed(.first))
        _ = try #require(await fixture.delivered(1, to: leaving))
        let jobs = fixture.executor.enqueued.count

        leaving.stop()
        await fixture.executor.enqueued.waitForCount(jobs + 1)
        fixture.report(Self.passed(.second))
        #expect(try #require(await fixture.delivered(2, to: staying)) == [Self.passed(.first), Self.passed(.second)])
        #expect(leaving.delivered.values == [Self.passed(.first)], "nothing reached the stream after its consumer let go")
    }

    // MARK: - A slow observer

    @Test("an observer that does not read loses the old outcomes and keeps the newest 64, in order")
    func slowObserverKeepsTheNewest() async throws {
        let fixture = StateFixture()
        let stream = fixture.subject.outcomes()
        let reported = (0..<70).map { Self.passed(.first, seconds: Double($0 + 1)) }
        for outcome in reported { fixture.report(outcome) }

        // Reporting queued and returned seventy times with nobody reading; the executor takes them all.
        #expect(fixture.executor.drain() == 71, "the registration and seventy reports")
        #expect(await fixture.read(64, from: stream) == Array(reported.suffix(64)))
    }
}
