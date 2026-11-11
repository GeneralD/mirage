import Presenters

/// The onboarding window's wireframe (#230): it builds the `OnboardingPresenter` once, with the Router, and decides when the
/// onboarding window opens and when it closes. It is kept apart from `AppRouter` so that the menu's Router stays as it is; the
/// App layer wires the menu entry that opens onboarding (#232).
///
/// The Presenter's life is the window's. `openOnboarding()` starts it as it makes the window, and the window's close, from its
/// title bar or from `close()`, stops it and lets go of the window. A Presenter that is let go while started stops its Interactor,
/// as `OnboardingPresenter` does for itself. The Router never touches the `EffectInteractor`: the Presenter only observes the
/// catalog's state, so opening and closing the window starts and stops nothing there.
///
/// The Presenter is built in `init`, not on first read or in `openOnboarding()`, so a test (or a harness) that wraps the Router's
/// construction in `withDependencies` decides what the Presenter talks to, and the View reads `onboardingPresenter` before anything
/// is started. The window is the Router's own state: one window at most, made by `makeWindow` at each opening, and let go when it
/// closes.
@MainActor
public final class OnboardingRouter {
    /// Builds the onboarding window over its Presenter; the window calls the closure it is given when it closes, with itself.
    public typealias WindowFactory =
        @MainActor (OnboardingPresenter, @escaping @MainActor (any OnboardingWindow) -> Void) -> any OnboardingWindow

    /// The one Presenter the onboarding window draws from; the same instance on every read, started only while the window is open.
    public let onboardingPresenter: OnboardingPresenter
    private let makeWindow: WindowFactory
    /// The onboarding window's open window; `nil` while none is open.
    private var onboardingWindow: (any OnboardingWindow)?

    /// The Presenter is made once, here; the window factory runs at every opening of the window. The defaults build the live
    /// Presenter and the live window; a test passes its own to see how often and where the Router asks for one, and to open no
    /// real window.
    public init(
        makeOnboardingPresenter: @MainActor () -> OnboardingPresenter = { OnboardingPresenter() },
        makeWindow: @escaping WindowFactory = OnboardingRouter.window(over:onClose:)
    ) {
        onboardingPresenter = makeOnboardingPresenter()
        self.makeWindow = makeWindow
    }

    /// Opens the onboarding window and starts its Presenter; while the window is open, brings that one to the front instead of
    /// making another.
    public func openOnboarding() {
        if let onboardingWindow { return onboardingWindow.show() }
        let window = makeWindow(onboardingPresenter) { [weak self] closed in self?.onboardingWindowDidClose(closed) }
        onboardingWindow = window
        onboardingPresenter.start()
        window.show()
    }

    /// Closes the onboarding window, if one is open: the window is let go and its Presenter stopped first. Without a window it
    /// does nothing.
    public func close() {
        guard let onboardingWindow else { return }
        releaseOnboardingWindow()
        // The window reports this close too; by then it is not the open one, and the report does nothing.
        onboardingWindow.close()
    }

    /// The live window: `OnboardingWindowImpl`, which reports its close through `onClose`.
    public static func window(
        over presenter: OnboardingPresenter, onClose: @escaping @MainActor (any OnboardingWindow) -> Void
    ) -> any OnboardingWindow {
        OnboardingWindowImpl(presenter: presenter) { window in onClose(window) }
    }
}

extension OnboardingRouter {
    /// A window closed, whoever closed it. Only the open one ends the Presenter: a report from a window the Router has already
    /// let go changes nothing.
    private func onboardingWindowDidClose(_ closed: any OnboardingWindow) {
        guard onboardingWindow === closed else { return }
        releaseOnboardingWindow()
    }

    private func releaseOnboardingWindow() {
        onboardingWindow = nil
        onboardingPresenter.stop()
    }
}
