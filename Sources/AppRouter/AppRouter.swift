import Presenters

/// The menu-bar lane's wireframe (epic #42, D8): it builds the one `MenuBarPresenter` and
/// decides when the menu's lifecycle begins and ends. It resolves nothing itself (the key-path
/// lint gives the View lane Presenters and Support only), and it never touches the
/// `EffectInteractor`: the Presenter owns that lifecycle, so `start()` / `stop()` here are the
/// Presenter's, and the entry lane never calls `effectInteractor.start()` (a second `start()`
/// is a restart, and the catalog would run twice).
///
/// The Presenter is built in `init`, not on first read or in `start()`. It captures the
/// dependencies of the scope it is made in, so a test (or a harness) that wraps the router's
/// construction in `withDependencies` decides what the Presenter talks to, and the View reads
/// `menuBarPresenter` before anything is started.
///
/// What `start()` and `stop()` guarantee is the Presenter's: a second `start()` while started
/// does nothing, a started Presenter that is let go stops itself, and the Router adds no
/// state of its own to those.
@MainActor
public final class AppRouter {
    /// The one Presenter the menu draws from; the same instance on every read.
    public let menuBarPresenter: MenuBarPresenter

    /// `makeMenuBarPresenter` runs once, here. The default builds the live Presenter; a test
    /// passes its own to see how often and where the Router asks for one.
    public init(makeMenuBarPresenter: @MainActor () -> MenuBarPresenter = { MenuBarPresenter() }) {
        menuBarPresenter = makeMenuBarPresenter()
    }

    /// Starts the menu: the Presenter observes the catalog and starts the Interactor.
    public func start() {
        menuBarPresenter.start()
    }

    /// Ends the menu: the Presenter lets go of the observation and stops the Interactor.
    public func stop() {
        menuBarPresenter.stop()
    }
}
