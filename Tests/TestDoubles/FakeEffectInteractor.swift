import Combine
import Domain
import TestSupport

/// `EffectInteractor` as the Presenter suites see it: `state` is a `CurrentValueSubject`
/// the test drives with `publish(_:)`, so a subscriber gets the current state at once
/// and every later one. Commands are only recorded (`starts`, `stops`, `selections`,
/// `folderOpens`); nothing they would cause happens unless the test publishes it.
public final class FakeEffectInteractor: EffectInteractor, @unchecked Sendable {
    private let subject: CurrentValueSubject<EffectCatalogState, Never>
    /// One entry per `start()` call.
    public let starts = Collector<Void>()
    /// One entry per `stop()` call.
    public let stops = Collector<Void>()
    /// The ids `select` was called with, in call order.
    public let selections = Collector<EffectID>()
    /// One entry per `openEffectsFolder()` call.
    public let folderOpens = Collector<Void>()

    public init(state: EffectCatalogState) {
        subject = CurrentValueSubject(state)
    }

    public var state: AnyPublisher<EffectCatalogState, Never> { subject.eraseToAnyPublisher() }

    /// Makes `state` the current state and sends it to every subscriber.
    public func publish(_ state: EffectCatalogState) {
        subject.send(state)
    }

    public func start() {
        starts.append(())
    }

    public func stop() {
        stops.append(())
    }

    public func select(_ id: EffectID) {
        selections.append(id)
    }

    public func openEffectsFolder() {
        folderOpens.append(())
    }
}
