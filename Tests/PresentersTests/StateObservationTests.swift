import Combine
import TestSupport
import Testing

@testable import Presenters

@MainActor
@Suite("StateObservation", .timeLimit(.minutes(1)))
struct StateObservationTests {
    @Test("the current value arrives first, and the later values follow in the order they were sent")
    func currentValueThenLaterValuesInOrder() async {
        let subject = CurrentValueSubject<Int, Never>(1)
        let applied = Collector<Int>()
        let observation = StateObservation(of: subject.eraseToAnyPublisher()) { applied.append($0) }

        await applied.waitForCount(1)
        subject.send(2)
        await applied.waitForCount(2)
        subject.send(3)
        await applied.waitForCount(3)

        #expect(applied.values == [1, 2, 3])
        observation.end()
    }

    @Test("when states are sent before the first one is applied, only the newest one arrives")
    func onlyNewestArrivesWhenSentBeforeApply() async {
        let subject = CurrentValueSubject<Int, Never>(1)
        let applied = Collector<Int>()
        let observation = StateObservation(of: subject.eraseToAnyPublisher()) { applied.append($0) }

        subject.send(2)
        subject.send(3)
        await applied.waitForCount(1)

        #expect(applied.values == [3])
        observation.end()
    }

    @Test("nothing is applied after end(), and a state that was sent and still waiting is dropped too")
    func endDropsTheWaitingState() async {
        let subject = CurrentValueSubject<Int, Never>(1)
        let ended = Collector<Int>()
        let fresh = Collector<Int>()
        let first = StateObservation(of: subject.eraseToAnyPublisher()) { ended.append($0) }

        subject.send(2)
        first.end()
        let second = StateObservation(of: subject.eraseToAnyPublisher()) { fresh.append($0) }
        await fresh.waitForCount(1)

        #expect(ended.values.isEmpty)
        #expect(fresh.values == [2])
        second.end()
    }

    @Test("end() cancels the subscription exactly once, even when the observation is let go afterwards")
    func endCancelsExactlyOnce() {
        let subject = CurrentValueSubject<Int, Never>(1)
        let cancels = Collector<Void>()
        let publisher = subject.handleEvents(receiveCancel: { cancels.append(()) }).eraseToAnyPublisher()
        var observation: StateObservation<Int>? = StateObservation(of: publisher) { _ in }

        observation?.end()
        observation = nil

        #expect(cancels.count == 1)
    }

    @Test("letting the observation go without end() cancels the subscription exactly once")
    func letGoWithoutEndCancelsExactlyOnce() {
        let subject = CurrentValueSubject<Int, Never>(1)
        let cancels = Collector<Void>()
        let publisher = subject.handleEvents(receiveCancel: { cancels.append(()) }).eraseToAnyPublisher()
        var observation: StateObservation<Int>? = StateObservation(of: publisher) { _ in }

        #expect(observation != nil)
        observation = nil

        #expect(cancels.count == 1)
    }
}
