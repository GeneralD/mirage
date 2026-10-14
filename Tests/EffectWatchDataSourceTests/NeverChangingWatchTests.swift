import Domain
import EffectWatchDataSource
import TestDoubles
import TestSupport
import Testing

@MainActor
@Suite("NeverChangingWatch", .timeLimit(.minutes(1)))
struct NeverChangingWatchTests {
    private let subject = NeverChangingWatch()
    private let watchSet = EffectWatchSet(directories: ["/effects"], files: ["/effects/a.lens/effect.metal"])

    @Test("the stream yields no element, however long it is iterated")
    func yieldsNothing() async {
        let heard = Collector<Void>()
        let consumer = Task { for await _ in subject.changes(of: watchSet) { heard.append(()) } }

        let heardAnything = await tickUntil(50, tick: {}, until: { heard.count > 0 })
        #expect(!heardAnything)

        consumer.cancel()
        await consumer.value
        #expect(heard.count == 0)
    }

    @Test("the stream stays open until its consumer lets go, and then ends")
    func endsWithItsConsumer() async {
        let ended = Collector<Void>()
        let consumer = Task {
            for await _ in subject.changes(of: .empty) {}
            ended.append(())
        }

        let endedByItself = await tickUntil(50, tick: {}, until: { ended.count > 0 })
        #expect(!endedByItself, "an empty watch set is still a stream that waits")

        consumer.cancel()
        await ended.waitForCount(1)
    }
}
