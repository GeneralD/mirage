import Combine
import Domain
import EffectInteractor
import TestDoubles
import TestSupport
import Testing

@Suite("StaticEffectInteractor")
struct StaticEffectInteractorTests {
    private let chromatic = EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))

    @Test("state publishes the state it was made with to every subscriber, and never completes")
    func publishesItsState() {
        let state = EffectCatalogState.fixture([chromatic])
        let subject = StaticEffectInteractor(state: state)

        let first = Collector<EffectCatalogState>()
        let second = Collector<EffectCatalogState>()
        let completions = Collector<Void>()
        let subscriptions = [
            subject.state.sink(receiveCompletion: { _ in completions.append(()) }, receiveValue: { first.append($0) }),
            subject.state.sink(receiveCompletion: { _ in completions.append(()) }, receiveValue: { second.append($0) }),
        ]

        #expect(first.values == [state])
        #expect(second.values == [state])
        #expect(completions.count == 0)
        withExtendedLifetime(subscriptions) {}
    }

    @Test("made with no state it publishes nothing, and never completes")
    func publishesNothing() {
        let subject = StaticEffectInteractor()
        let values = Collector<EffectCatalogState>()
        let completions = Collector<Void>()
        let subscription = subject.state.sink(receiveCompletion: { _ in completions.append(()) }, receiveValue: { values.append($0) })

        subject.start()
        #expect(values.count == 0)
        #expect(completions.count == 0)
        withExtendedLifetime(subscription) {}
    }

    @Test("the commands do nothing, and need no UseCase: the unimplemented defaults would report one")
    func commandsDoNothing() {
        let subject = StaticEffectInteractor()
        subject.start()
        subject.select(.package("glitch"))
        subject.openEffectsFolder()
        subject.stop()
    }
}
