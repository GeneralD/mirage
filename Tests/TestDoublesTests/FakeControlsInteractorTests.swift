import Combine
import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("FakeControlsInteractor", .timeLimit(.minutes(1)))
struct FakeControlsInteractorTests {
    @Test("subscribing receives the current state first, then the state that publish sent")
    func subscribeReceivesCurrentThenPublished() {
        let initial = ControlsState(isBypassed: false, framesPerSecond: 30)
        let fake = FakeControlsInteractor(state: initial)
        let seen = Collector<ControlsState>()
        let subscription = fake.state.sink { seen.append($0) }

        let published = ControlsState(isBypassed: true, framesPerSecond: 60)
        fake.publish(published)

        #expect(seen.values == [initial, published])
        withExtendedLifetime(subscription) {}
    }

    @Test("a fake built without a state holds ControlsState() from construction until publish")
    func defaultStateFromConstruction() {
        let fake = FakeControlsInteractor()
        let seen = Collector<ControlsState>()
        let subscription = fake.state.sink { seen.append($0) }

        #expect(seen.values == [ControlsState()])
        withExtendedLifetime(subscription) {}
    }

    @Test("start, stop and toggleBypass are each recorded once per call, and the state does not change")
    func commandsRecordWithoutChangingState() {
        let initial = ControlsState(isBypassed: false, framesPerSecond: 60)
        let fake = FakeControlsInteractor(state: initial)
        let seen = Collector<ControlsState>()
        let subscription = fake.state.sink { seen.append($0) }

        fake.start()
        fake.start()
        fake.stop()
        fake.toggleBypass()
        fake.toggleBypass()

        #expect(fake.starts.count == 2)
        #expect(fake.stops.count == 1)
        #expect(fake.toggles.count == 2)
        #expect(seen.values == [initial], "a command publishes nothing: only publish(_:) changes the state")
        withExtendedLifetime(subscription) {}
    }

    @Test("cancelling a subscription to state records one stateCancel")
    func cancellingRecordsOneStateCancel() {
        let fake = FakeControlsInteractor()
        let subscription = fake.state.sink { _ in }
        #expect(fake.stateCancels.count == 0)

        subscription.cancel()

        #expect(fake.stateCancels.count == 1)
    }
}
