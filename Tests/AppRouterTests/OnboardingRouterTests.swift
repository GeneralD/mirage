import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import AppRouter
@testable import Presenters

/// The onboarding Router's half (#230): the window it opens from a request, the Presenter it starts and stops with that window,
/// and the window's end, from the title bar or from `close()`. Every window here is a `FakeOnboardingWindow` made through
/// `makeWindow`, so no suite opens a real one; the live window's own glue is the last test, which makes one and never shows it.
@MainActor
@Suite("OnboardingRouter", .timeLimit(.minutes(1)))
struct OnboardingRouterTests {
    @Test("the Presenter is built with the Router, once, and no window is made; the Interactor is asked nothing")
    func builtWithTheRouter() {
        let rig = OnboardingRig()

        #expect(rig.presenterBuilds.count == 1)
        #expect(rig.windows.count == 0)
        #expect(rig.router.onboardingPresenter.status == onboardingPendingStatus)
        #expect(rig.interactor.starts.count == 0)
        #expect(rig.interactor.stops.count == 0)
    }

    @Test("openOnboarding makes one window over the Presenter, shows it and starts the Presenter, whose status reaches the window")
    func openShowsTheWindowAndStartsThePresenter() async throws {
        let rig = OnboardingRig(install: .installed)

        rig.router.openOnboarding()

        let window = try #require(rig.windows.values.first)
        #expect(rig.windows.count == 1)
        #expect(window.presenter === rig.router.onboardingPresenter)
        #expect(window.shows == 1)
        #expect(rig.interactor.starts.count == 1)
        await settle(rig.router.onboardingPresenter.$status) { $0 == onboardingStatus(of: .installed) }
        #expect(rig.router.onboardingPresenter.status == onboardingStatus(of: .installed))
    }

    @Test("asking again while the window is open shows the same window and makes no other, and starts the Presenter once")
    func openWhileOpenShowsTheSameWindow() throws {
        let rig = OnboardingRig()

        rig.router.openOnboarding()
        rig.router.openOnboarding()

        let window = try #require(rig.windows.values.first)
        #expect(rig.windows.count == 1)
        #expect(window.shows == 2)
        #expect(rig.interactor.starts.count == 1)
        #expect(rig.presenterBuilds.count == 1)
    }

    @Test("closing the window from its title bar stops the Presenter, and the next request makes a new window")
    func titleBarCloseEndsThePresenter() throws {
        let rig = OnboardingRig()
        rig.router.openOnboarding()
        let first = try #require(rig.windows.values.first)

        first.closeFromTitleBar()

        #expect(rig.interactor.stops.count == 1, "the Presenter was stopped, and so its Interactor")
        #expect(first.closes == 0, "the window closed itself; the Router does not close it again")
        rig.router.openOnboarding()
        #expect(rig.windows.count == 2)
        #expect(first.shows == 1)
        #expect(rig.windows.values.last?.shows == 1)
        #expect(rig.interactor.starts.count == 2)
    }

    @Test("close() closes the open window once and stops the Presenter; without a window it does nothing")
    func closeClosesTheWindowOnce() throws {
        let rig = OnboardingRig()
        rig.router.close()
        #expect(rig.interactor.stops.count == 0)
        rig.router.openOnboarding()
        let window = try #require(rig.windows.values.first)

        rig.router.close()
        rig.router.close()

        #expect(window.closes == 1)
        #expect(rig.interactor.stops.count == 1)
        rig.router.openOnboarding()
        #expect(rig.windows.count == 2, "the closed window is not brought back")
    }

    @Test("a close reported by a window the Router has already let go leaves the open one alone")
    func staleCloseIsIgnored() throws {
        let rig = OnboardingRig()
        rig.router.openOnboarding()
        let first = try #require(rig.windows.values.first)
        rig.router.close()
        rig.router.openOnboarding()
        let second = try #require(rig.windows.values.last)

        first.closeFromTitleBar()

        #expect(rig.interactor.stops.count == 1, "only the close() stopped the Presenter; the open one still runs")
        #expect(rig.interactor.starts.count == 2)
        rig.router.openOnboarding()
        #expect(rig.windows.count == 2)
        #expect(second.shows == 2, "the second window is still the open one")
    }

    @Test("a Router let go with the window open stops the Interactor through its Presenter")
    func letGoWithTheWindowOpen() {
        let interactor = FakeOnboardingInteractor()
        var rig: OnboardingRig? = OnboardingRig(interactor: interactor)
        rig?.router.openOnboarding()
        #expect(interactor.starts.count == 1)
        #expect(interactor.stops.count == 0)

        rig = nil

        #expect(interactor.stops.count == 1, "nothing the window added keeps the Router or the Presenter alive")
    }

    @Test("the live window is an OnboardingWindowImpl over the Presenter, and its close reports that window")
    func liveWindowReportsItsClose() {
        let closed = Collector<ObjectIdentifier>()

        let window = OnboardingRouter.window(over: makePresenter(over: FakeOnboardingInteractor())) { closed.append(ObjectIdentifier($0)) }
        // Never shown: closing a window that was never on screen still reports, and puts nothing on screen.
        window.close()

        #expect(window is OnboardingWindowImpl)
        #expect(closed.values == [ObjectIdentifier(window)])
    }
}

/// A Router whose Presenter talks to `interactor`, built inside `withDependencies` so that it never reaches the live Interactor,
/// and whose windows are `FakeOnboardingWindow`s, recorded in the order they were made.
@MainActor
private struct OnboardingRig {
    let interactor: FakeOnboardingInteractor
    let presenterBuilds = Collector<Void>()
    let windows = Collector<FakeOnboardingWindow>()
    let router: OnboardingRouter

    init(install: InstallStatus = .notInstalled) {
        self.init(interactor: FakeOnboardingInteractor(install: install))
    }

    init(interactor: FakeOnboardingInteractor) {
        let (presenterBuilds, windows) = (presenterBuilds, windows)
        self.interactor = interactor
        router = OnboardingRouter(
            makeOnboardingPresenter: {
                presenterBuilds.append(())
                return makePresenter(over: interactor)
            },
            makeWindow: { presenter, onClose in
                let window = FakeOnboardingWindow(presenter: presenter, onClose: onClose)
                windows.append(window)
                return window
            })
    }
}

/// An onboarding Presenter over `interactor` and fakes that show the chromatic effect, built inside `withDependencies` so that it
/// never reaches the live Interactor. It is not started: each test starts it through the Router.
@MainActor
private func makePresenter(over interactor: FakeOnboardingInteractor) -> OnboardingPresenter {
    withDependencies {
        $0.onboardingInteractor = interactor
        $0.hostEnvironment = FixedHostEnvironment(systemMajor: 15)
        $0.effectInteractor = FakeEffectInteractor(state: .fixture([EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))]))
    } operation: {
        OnboardingPresenter()
    }
}

/// The onboarding window as the Router sees it. Like the live window, `close()` reports itself through `onClose`;
/// `closeFromTitleBar()` is a close the Router did not ask for.
@MainActor
private final class FakeOnboardingWindow {
    let presenter: OnboardingPresenter
    private let onClose: @MainActor (any OnboardingWindow) -> Void
    private(set) var shows = 0
    private(set) var closes = 0

    init(presenter: OnboardingPresenter, onClose: @escaping @MainActor (any OnboardingWindow) -> Void) {
        self.presenter = presenter
        self.onClose = onClose
    }

    func closeFromTitleBar() {
        onClose(self)
    }
}

extension FakeOnboardingWindow: OnboardingWindow {
    func show() {
        shows += 1
    }

    func close() {
        closes += 1
        onClose(self)
    }
}
