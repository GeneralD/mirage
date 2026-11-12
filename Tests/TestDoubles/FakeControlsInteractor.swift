import Combine
import Domain
import TestSupport

/// `ControlsInteractor` as the Presenter suites see it: `state` is a `CurrentValueSubject` the test
/// drives with `publish(_:)`, so a subscriber gets the current controls at once and every later one.
/// Commands are only recorded (`starts`, `stops`, `toggles`); nothing they would cause happens unless
/// the test publishes it. `stateCancels` counts the subscriptions to `state` that were cancelled.
public final class FakeControlsInteractor: ControlsInteractor, @unchecked Sendable {
    private let subject: CurrentValueSubject<ControlsState, Never>
    /// One entry per `start()` call.
    public let starts = Collector<Void>()
    /// One entry per `stop()` call.
    public let stops = Collector<Void>()
    /// One entry per `toggleBypass()` call.
    public let toggles = Collector<Void>()
    /// One entry per cancelled subscription to `state`.
    public let stateCancels = Collector<Void>()

    public init(state: ControlsState = ControlsState()) {
        subject = CurrentValueSubject(state)
    }

    public var state: AnyPublisher<ControlsState, Never> {
        let cancels = stateCancels
        return subject.handleEvents(receiveCancel: { cancels.append(()) }).eraseToAnyPublisher()
    }

    /// Makes `state` the current controls and sends them to every subscriber.
    public func publish(_ state: ControlsState) {
        subject.send(state)
    }

    public func start() {
        starts.append(())
    }

    public func stop() {
        stops.append(())
    }

    public func toggleBypass() {
        toggles.append(())
    }
}
