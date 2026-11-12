import Dependencies
import Domain
import Presenters
import TestDoubles
import TestSupport
import Testing

@testable import AppRouter

/// The onboarding window's glue (#229): its title, which is `onboardingWindowTitle`, and its close, which reports the window to the
/// Router whether it was shown or not. Every window here is made over an `OnboardingPresenter` whose Interactor, host and catalog
/// are fakes, built inside `withDependencies`, so no suite reaches the live Interactor. No suite calls `show()`, which would bring
/// the window onto the main screen; the gallery's onboarding screen (#234) checks what it looks like.
@MainActor
@Suite("OnboardingWindow", .timeLimit(.minutes(1)))
struct OnboardingWindowTests {
    @Test("the window's title is Set Up the Virtual Camera, and making the window does not report a close")
    func titledAndSilentWhenMade() {
        let closed = Collector<ObjectIdentifier>()

        let window = OnboardingWindowImpl(presenter: makePresenter()) { closed.append(ObjectIdentifier($0)) }

        #expect(window.windowTitle == "Set Up the Virtual Camera")
        #expect(window.windowTitle == onboardingWindowTitle)
        #expect(closed.values.isEmpty)
    }

    @Test("close() reports the window once, as itself, even when it was never shown")
    func closeReportsOnceAsItself() {
        let closed = Collector<ObjectIdentifier>()
        let window = OnboardingWindowImpl(presenter: makePresenter()) { closed.append(ObjectIdentifier($0)) }

        window.close()

        #expect(closed.values == [ObjectIdentifier(window)])
    }

    @Test("OnboardingWindowImpl can be used as any OnboardingWindow, and closing it through the protocol reports it once")
    func usableAsOnboardingWindow() {
        let closed = Collector<ObjectIdentifier>()
        let window: any OnboardingWindow = OnboardingWindowImpl(presenter: makePresenter()) { closed.append(ObjectIdentifier($0)) }

        window.close()

        #expect(closed.values == [ObjectIdentifier(window)])
    }
}

/// An onboarding Presenter over fakes that show the chromatic effect, built inside `withDependencies` so that it never reaches
/// the live Interactor. It is not started: the window reads only the title, which needs no state.
@MainActor
private func makePresenter() -> OnboardingPresenter {
    withDependencies {
        $0.onboardingInteractor = FakeOnboardingInteractor()
        $0.hostEnvironment = FixedHostEnvironment(systemMajor: 15)
        $0.effectInteractor = FakeEffectInteractor(state: .fixture([EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))]))
    } operation: {
        OnboardingPresenter()
    }
}
