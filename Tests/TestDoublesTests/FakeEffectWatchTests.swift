import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("FakeEffectWatch", .timeLimit(.minutes(1)))
struct FakeEffectWatchTests {
    private let watch = FakeEffectWatch()
    private let set = EffectWatchSet(directories: ["/effects"], files: ["/effects/a.lens/effect.metal"])

    /// A task that counts what a subject iterating the stream would see.
    private func listen(to stream: AsyncStream<Void>, into heard: Collector<Void>) -> Task<Void, Never> {
        Task { for await _ in stream { heard.append(()) } }
    }

    @Test("one fire is exactly one element")
    func fireIsOneElement() async {
        let heard = Collector<Void>()
        let consumer = listen(to: watch.changes(of: set), into: heard)

        #expect(watch.fire())
        await heard.waitForCount(1)
        consumer.cancel()
        await consumer.value

        #expect(heard.count == 1)
    }

    @Test("every fire is one more element, in a stream nobody has to be iterating yet")
    func firesAreBuffered() async {
        let stream = watch.changes(of: set)
        watch.fire()
        watch.fire()
        watch.fire()

        let heard = Collector<Void>()
        let consumer = listen(to: stream, into: heard)
        await heard.waitForCount(3)
        consumer.cancel()
        await consumer.value

        #expect(heard.count == 3)
    }

    @Test("the watch is registered before changes(of:) returns, so a fire right after it is delivered, not lost")
    func registeredBeforeItReturns() async {
        let stream = watch.changes(of: set)
        #expect(watch.fire(), "the stream is live as soon as the call returns")

        let heard = Collector<Void>()
        let consumer = listen(to: stream, into: heard)
        await heard.waitForCount(1)
        consumer.cancel()
        await consumer.value
    }

    @Test("requests records the set of every call, in order, and the count of live streams")
    func requestsAreRecorded() async {
        let other = EffectWatchSet(directories: ["/effects", "/effects/a.lens"], files: [])
        let first = watch.changes(of: set)
        let second = watch.changes(of: other)
        withExtendedLifetime((first, second)) {
            #expect(watch.requests.values == [set, other])
            #expect(watch.activeCount == 2)
        }
    }

    @Test("fire without a request reaches the latest stream, and request: picks another one")
    func fireTargetsAStream() async {
        let firstHeard = Collector<Void>()
        let secondHeard = Collector<Void>()
        let first = listen(to: watch.changes(of: set), into: firstHeard)
        let second = listen(to: watch.changes(of: set), into: secondHeard)

        #expect(watch.fire())
        await secondHeard.waitForCount(1)
        #expect(watch.fire(request: 0))
        await firstHeard.waitForCount(1)
        #expect(!watch.fire(request: 5), "no such request")

        first.cancel()
        second.cancel()
        await first.value
        await second.value
        #expect(firstHeard.count == 1)
        #expect(secondHeard.count == 1)
    }

    @Test("a stream that ends is recorded by its request number, stops hearing fires, and no longer counts as live")
    func terminationIsRecorded() async {
        let heard = Collector<Void>()
        let first = listen(to: watch.changes(of: set), into: heard)
        let second = listen(to: watch.changes(of: set), into: heard)

        first.cancel()
        await watch.terminations.waitForCount(1)
        #expect(watch.terminations.values == [0])
        #expect(watch.activeCount == 1)
        #expect(!watch.fire(request: 0), "the ended stream hears nothing")

        second.cancel()
        await watch.terminations.waitForCount(2)
        #expect(watch.terminations.values == [0, 1])
        #expect(watch.activeCount == 0)
        #expect(!watch.fire(), "no live stream: nothing heard it")
        #expect(heard.count == 0)
    }
}
