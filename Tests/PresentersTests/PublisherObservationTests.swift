import Combine
import TestSupport
import Testing

@testable import Presenters

@MainActor
@Suite("PublisherObservation", .timeLimit(.minutes(1)))
struct PublisherObservationTests {
    @Test("a value sent after init is applied on the main actor")
    func valueSentAfterInitIsApplied() async {
        let subject = PassthroughSubject<Int, Never>()
        let applied = Collector<Int>()
        let observation = PublisherObservation(of: subject.eraseToAnyPublisher()) { applied.append($0) }

        subject.send(1)
        await applied.waitForCount(1)

        #expect(applied.values == [1])
        observation.end()
    }

    @Test("the current value of a CurrentValueSubject is applied first, and the values sent later follow it")
    func currentValueIsAppliedFirst() async {
        let subject = CurrentValueSubject<Int, Never>(1)
        let applied = Collector<Int>()
        let observation = PublisherObservation(of: subject.eraseToAnyPublisher()) { applied.append($0) }

        await applied.waitForCount(1)
        subject.send(2)
        await applied.waitForCount(2)

        #expect(applied.values == [1, 2])
        observation.end()
    }

    @Test("while the main actor is held, sending 1, 2 and 3 applies only the newest value, 3")
    func onlyNewestIsAppliedWhenSentBeforeApply() async {
        let subject = PassthroughSubject<Int, Never>()
        let applied = Collector<Int>()
        let observation = PublisherObservation(of: subject.eraseToAnyPublisher()) { applied.append($0) }

        subject.send(1)
        subject.send(2)
        subject.send(3)
        await applied.waitForCount(1)

        #expect(applied.values == [3])
        observation.end()
    }

    @Test("end() cancels the subscription")
    func endCancelsTheSubscription() {
        let subject = CurrentValueSubject<Int, Never>(1)
        let cancels = Collector<Void>()
        let publisher = subject.handleEvents(receiveCancel: { cancels.append(()) }).eraseToAnyPublisher()
        let observation = PublisherObservation(of: publisher) { _ in }

        observation.end()

        #expect(cancels.count == 1)
    }

    @Test("letting the observation go ends its subscription")
    func letGoEndsTheSubscription() {
        let subject = CurrentValueSubject<Int, Never>(1)
        let cancels = Collector<Void>()
        let publisher = subject.handleEvents(receiveCancel: { cancels.append(()) }).eraseToAnyPublisher()
        var observation: PublisherObservation<Int>? = PublisherObservation(of: publisher) { _ in }
        weak let released = observation
        #expect(released != nil)

        observation = nil

        #expect(released == nil, "nothing else holds the observation, so letting it go released it")
        #expect(cancels.count == 1)
    }

    @Test("letting the observation go after end() does not cancel the subscription a second time")
    func letGoAfterEndDoesNotCancelAgain() {
        let subject = CurrentValueSubject<Int, Never>(1)
        let cancels = Collector<Void>()
        let publisher = subject.handleEvents(receiveCancel: { cancels.append(()) }).eraseToAnyPublisher()
        var observation: PublisherObservation<Int>? = PublisherObservation(of: publisher) { _ in }

        observation?.end()
        observation = nil

        #expect(cancels.count == 1)
    }

    @Test("a value still waiting when end() is called is never applied")
    func waitingValueIsDroppedByEnd() async {
        let subject = CurrentValueSubject<Int, Never>(1)
        let ended = Collector<Int>()
        let fresh = Collector<Int>()
        // The test holds the main actor from the init to end(), so the task that applies values has
        // not run: the value 2 is still waiting for it when end() lands.
        let first = PublisherObservation(of: subject.eraseToAnyPublisher()) { ended.append($0) }
        subject.send(2)
        first.end()

        // A second observation over the same subject applies its current value, 2, after the first
        // one's task was queued: if the first had applied the waiting value, it would be recorded first.
        let second = PublisherObservation(of: subject.eraseToAnyPublisher()) { fresh.append($0) }
        await fresh.waitForCount(1)

        #expect(ended.values.isEmpty)
        #expect(fresh.values == [2])
        second.end()
    }

    @Test("a value sent after end() is never applied")
    func valueSentAfterEndIsNotApplied() async {
        let subject = CurrentValueSubject<Int, Never>(1)
        let ended = Collector<Int>()
        let fresh = Collector<Int>()
        let first = PublisherObservation(of: subject.eraseToAnyPublisher()) { ended.append($0) }
        await ended.waitForCount(1)
        first.end()

        subject.send(2)
        let second = PublisherObservation(of: subject.eraseToAnyPublisher()) { fresh.append($0) }
        await fresh.waitForCount(1)

        #expect(ended.values == [1], "the value sent after end() was not applied by the ended observation")
        #expect(fresh.values == [2])
        second.end()
    }
}
