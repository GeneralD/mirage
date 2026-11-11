import Dependencies
import Domain
import Presenters
import TestDoubles
import TestSupport
import Testing

@testable import AppRouter

/// The parameter panel window's glue (#118): its title, which is the Presenter's, and its close, which reports the window to the
/// Router whether it was shown or not. Every window here is made over a `ParameterPanelPresenter` whose Interactor is a
/// `FakeEffectInteractor`, built inside `withDependencies`, so no suite reaches the live Interactor. No suite calls `show()`,
/// which would bring the window onto the main screen.
@MainActor
@Suite("ParameterPanelWindow", .timeLimit(.minutes(1)))
struct ParameterPanelWindowTests {
    @Test("the window's title is the Presenter's windowTitle, which is Adjust Effect, and making the window does not report a close")
    func titledFromThePresenterAndSilentWhenMade() {
        let closed = Collector<ObjectIdentifier>()
        let presenter = makePresenter()

        let window = ParameterPanelWindow(presenter: presenter) { closed.append(ObjectIdentifier($0)) }

        #expect(presenter.windowTitle == "Adjust Effect")
        #expect(window.windowTitle == presenter.windowTitle)
        #expect(closed.values.isEmpty)
    }

    @Test("close() reports the window once, as itself, even when it was never shown")
    func closeReportsOnceAsItself() {
        let closed = Collector<ObjectIdentifier>()
        let window = ParameterPanelWindow(presenter: makePresenter()) { closed.append(ObjectIdentifier($0)) }

        window.close()

        #expect(closed.values == [ObjectIdentifier(window)])
    }

    @Test("ParameterPanelWindow can be used as any ParameterWindow, and closing it through the protocol reports it once")
    func usableAsParameterWindow() {
        let closed = Collector<ObjectIdentifier>()
        let window: any ParameterWindow = ParameterPanelWindow(presenter: makePresenter()) { closed.append(ObjectIdentifier($0)) }

        window.close()

        #expect(closed.values == [ObjectIdentifier(window)])
    }
}

/// A panel Presenter over a `FakeEffectInteractor` that shows the chromatic effect, built inside `withDependencies` so that it never
/// reaches the live Interactor. It is not started: the window reads only the Presenter's title, which needs no state.
@MainActor
private func makePresenter() -> ParameterPanelPresenter {
    withDependencies {
        $0.effectInteractor = FakeEffectInteractor(state: .fixture([EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))]))
    } operation: {
        ParameterPanelPresenter()
    }
}
