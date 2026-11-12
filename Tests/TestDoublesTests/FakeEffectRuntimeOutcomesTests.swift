import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("FakeEffectRuntimeRepository outcomes", .timeLimit(.minutes(1)))
struct FakeEffectRuntimeOutcomesTests {
    private let runtime = FakeEffectRuntimeRepository()

    private func outcome(_ n: Int) -> EffectPassOutcome {
        EffectPassOutcome(fingerprint: EffectFingerprint(value: String(n)), result: .success(GPUTiming(gpuStart: 1, gpuEnd: 2)))
    }

    @Test("outcomes() records one subscription per call, and the first is recorded before the call returns")
    func subscriptionIsRecordedWhenOutcomesReturns() {
        let first = runtime.outcomes()
        #expect(runtime.outcomeStreams.count == 1, "no wait: the record is there as soon as the call returns")

        let second = runtime.outcomes()
        #expect(runtime.outcomeStreams.count == 2, "one record per call")
        _ = (first, second)
    }

    @Test("an outcome emitted once a subscription's record is seen reaches that subscription")
    func emittedOutcomeReachesOpenSubscription() async {
        let consumer = Task { () -> EffectPassOutcome? in
            await runtime.outcomes().first(where: { _ in true })
        }
        await runtime.outcomeStreams.waitForCount(1)
        runtime.report(outcome(1))

        #expect(await consumer.value == outcome(1), "the emit right after the record is not lost")
    }

    @Test("an outcome emitted before a subscription opens is not replayed to it")
    func outcomeBeforeSubscriptionIsNotReplayed() async {
        runtime.report(outcome(1))
        let stream = runtime.outcomes()
        runtime.report(outcome(2))

        #expect(await stream.first(where: { _ in true }) == outcome(2))
    }

    @Test("every open subscription receives each emitted outcome, in emit order")
    func everyOpenSubscriptionReceivesEachOutcome() async {
        let first = runtime.outcomes()
        let second = runtime.outcomes()
        runtime.report(outcome(1))
        runtime.report(outcome(2))

        #expect(await first.prefix(2).reduce(into: [EffectPassOutcome]()) { $0.append($1) } == [outcome(1), outcome(2)])
        #expect(await second.prefix(2).reduce(into: [EffectPassOutcome]()) { $0.append($1) } == [outcome(1), outcome(2)])
    }

    @Test("a subscription nobody reads keeps only the newest 64 outcomes, fingerprints 6 through 69")
    func unreadSubscriptionKeepsNewest64() async {
        let stream = runtime.outcomes()
        for n in 0..<70 { runtime.report(outcome(n)) }

        let read = await stream.prefix(64).reduce(into: [String]()) { $0.append($1.fingerprint.value) }
        #expect(read == (6..<70).map { String($0) })
    }

    @Test("a consumer cancelled after its last outcome gets no later outcome, and a subscription opened later still does")
    func cancelledConsumerGetsNoLaterOutcome() async {
        let received = Collector<EffectPassOutcome>()
        let stream = runtime.outcomes()
        let consumer = Task {
            for await outcome in stream { received.append(outcome) }
        }

        // The consumer is iterating once it has seen the first outcome, so the cancel below ends a live loop.
        runtime.report(outcome(1))
        await received.waitForCount(1)

        consumer.cancel()
        await consumer.value
        let later = runtime.outcomes()
        runtime.report(outcome(2))

        #expect(received.values == [outcome(1)], "the cancelled consumer does not see the outcome emitted after the cancel")
        #expect(await later.first(where: { _ in true }) == outcome(2))
    }
}
