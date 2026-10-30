import Combine
import Domain
import TestDoubles
import TestSupport

/// A `FakeEffectInteractor` that also counts its `state` subscriptions that were cancelled,
/// which is how a test proves that a Presenter let go of the publisher. Shared by the suites of
/// the two Presenters that observe the Interactor.
final class SpyEffectInteractor: EffectInteractor, Sendable {
    let inner: FakeEffectInteractor
    /// One entry per `state` subscription that was cancelled.
    let cancellations = Collector<Void>()

    init(_ inner: FakeEffectInteractor) {
        self.inner = inner
    }

    var state: AnyPublisher<EffectCatalogState, Never> {
        let cancellations = cancellations
        return inner.state.handleEvents(receiveCancel: { cancellations.append(()) }).eraseToAnyPublisher()
    }

    func publish(_ state: EffectCatalogState) { inner.publish(state) }
    func start() { inner.start() }
    func stop() { inner.stop() }
    func select(_ id: EffectID) { inner.select(id) }
    func openEffectsFolder() { inner.openEffectsFolder() }

    var starts: Collector<Void> { inner.starts }
    var stops: Collector<Void> { inner.stops }
    var selections: Collector<EffectID> { inner.selections }
    var folderOpens: Collector<Void> { inner.folderOpens }
}
