import Presenters
import Views

/// The menu-bar lane's wireframe (epic #42, D8; #12): it builds the `MenuBarPresenter`, the
/// `EffectPickerPresenter` and the `SettingsPresenter`, decides when the menu's lifecycle begins and
/// ends, and opens and closes the picker's window and the settings window. It resolves nothing itself
/// (the key-path lint gives the View lane Presenters and Support only), and it never touches the
/// `EffectInteractor`: the menu's Presenter owns that lifecycle, so `start()` / `stop()` here are the
/// Presenter's, and the entry lane never calls `effectInteractor.start()` (a second `start()` is a
/// restart, and the catalog would run twice; `scripts/check-dependency-keypaths.sh` denies `App` and
/// `DevHarness` the key).
///
/// The Presenters are built in `init`, not on first read or in `start()`. Each captures the
/// dependencies of the scope it is made in, so a test (or a harness) that wraps the router's
/// construction in `withDependencies` decides what both talk to, and the View reads
/// `menuBarPresenter` before anything is started.
///
/// What `start()` and `stop()` guarantee for the menu is its Presenter's: a second `start()` while
/// started does nothing, a started Presenter that is let go stops itself, and the Router adds no
/// state of its own to those. The picker is the Router's own state: one window at most, made by
/// `makePickerWindow` when the menu asks for it, the picker's Presenter observing while that window
/// is open and not otherwise, and both let go when it closes, from its title bar or from `stop()`.
/// The settings window is the Router's own state in the same way, over its own Presenter, and a
/// reset-all that finishes comes back through `settingsDidReset()`.
@MainActor
public final class AppRouter {
    /// Builds the picker's window over its Presenter; the window calls the closure it is given when
    /// it closes, with itself.
    public typealias PickerWindowFactory =
        @MainActor (EffectPickerPresenter, @escaping @MainActor (any PickerWindow) -> Void) -> any PickerWindow

    /// Builds the settings window over its Presenter; the window calls the closure it is given when
    /// it closes, with itself.
    public typealias SettingsWindowFactory =
        @MainActor (SettingsPresenter, @escaping @MainActor (any SettingsWindow) -> Void) -> any SettingsWindow

    /// The one Presenter the menu draws from; the same instance on every read.
    public let menuBarPresenter: MenuBarPresenter
    /// The one Presenter the picker draws from; the same instance on every read, started only while
    /// the picker's window is open.
    public let effectPickerPresenter: EffectPickerPresenter
    /// The one Presenter the settings window draws from; the same instance on every read, started only
    /// while the settings window is open.
    public let settingsPresenter: SettingsPresenter
    private let makePickerWindow: PickerWindowFactory
    /// The picker's open window; `nil` while none is open.
    private var pickerWindow: (any PickerWindow)?
    private let makeSettingsWindow: SettingsWindowFactory
    /// The settings window's open window; `nil` while none is open.
    private var settingsWindow: (any SettingsWindow)?

    /// Each factory runs once, here, except the two window factories, which run at every opening of
    /// their window. The defaults build the live Presenters and the live windows; a test passes its own
    /// to see how often and where the Router asks for one, and to open no real window.
    public init(
        makeMenuBarPresenter: @MainActor () -> MenuBarPresenter = { MenuBarPresenter() },
        makeEffectPickerPresenter: @MainActor () -> EffectPickerPresenter = { EffectPickerPresenter() },
        makePickerWindow: @escaping PickerWindowFactory = AppRouter.pickerWindow(over:onClose:),
        makeSettingsPresenter: @MainActor () -> SettingsPresenter = { SettingsPresenter() },
        makeSettingsWindow: @escaping SettingsWindowFactory = AppRouter.settingsWindow(over:onClose:)
    ) {
        menuBarPresenter = makeMenuBarPresenter()
        effectPickerPresenter = makeEffectPickerPresenter()
        self.makePickerWindow = makePickerWindow
        settingsPresenter = makeSettingsPresenter()
        self.makeSettingsWindow = makeSettingsWindow
        menuBarPresenter.router = self
        settingsPresenter.router = self
    }

    /// Starts the menu: the Presenter observes the catalog and starts the Interactor.
    public func start() {
        menuBarPresenter.start()
    }

    /// Ends the menu, and the windows with it: the picker's window and the settings window close, and
    /// the menu's Presenter lets go of the observation and stops the Interactor.
    public func stop() {
        closeEffectPicker()
        closeSettings()
        menuBarPresenter.stop()
    }

    /// Closes the picker's window, if one is open, and ends its Presenter's observation.
    public func closeEffectPicker() {
        guard let window = pickerWindow else { return }
        releasePicker()
        // The window reports this close too; by then it is not the open one, and the report does nothing.
        window.close()
    }

    /// Closes the settings window, if one is open, and ends its Presenter's observation.
    public func closeSettings() {
        guard let window = settingsWindow else { return }
        releaseSettings()
        // The window reports this close too; by then it is not the open one, and the report does nothing.
        window.close()
    }

    /// The live window: `EffectPickerWindow` around `EffectPickerView`.
    public static func pickerWindow(
        over presenter: EffectPickerPresenter, onClose: @escaping @MainActor (any PickerWindow) -> Void
    ) -> any PickerWindow {
        EffectPickerWindow(presenter: presenter) { window in onClose(window) }
    }

    /// The live window: `SettingsPanelWindow` around `SettingsView`.
    public static func settingsWindow(
        over presenter: SettingsPresenter, onClose: @escaping @MainActor (any SettingsWindow) -> Void
    ) -> any SettingsWindow {
        SettingsPanelWindow(presenter: presenter) { window in onClose(window) }
    }
}

extension AppRouter: MenuBarRouting {
    /// Opens the picker's window and starts its Presenter; while a window is open, brings that one
    /// to the front instead of making another.
    public func openEffectPicker() {
        if let pickerWindow { return pickerWindow.show() }
        let window = makePickerWindow(effectPickerPresenter) { [weak self] closed in self?.pickerWindowDidClose(closed) }
        pickerWindow = window
        effectPickerPresenter.start()
        window.show()
    }

    /// Opens the settings window and starts its Presenter; while a window is open, brings that one
    /// to the front instead of making another.
    public func openSettings() {
        if let settingsWindow { return settingsWindow.show() }
        let window = makeSettingsWindow(settingsPresenter) { [weak self] closed in self?.settingsWindowDidClose(closed) }
        settingsWindow = window
        settingsPresenter.start()
        window.show()
    }
}

extension AppRouter: SettingsRouting {
    /// A reset-all has finished: the menu starts again, so what reads the stored values reads the new ones.
    public func settingsDidReset() {
        menuBarPresenter.stop()
        menuBarPresenter.start()
    }
}

extension AppRouter {
    /// A window closed, whoever closed it. Only the open one ends the picker: a report from a window
    /// the Router has already let go changes nothing.
    private func pickerWindowDidClose(_ window: any PickerWindow) {
        guard pickerWindow === window else { return }
        releasePicker()
    }

    private func releasePicker() {
        pickerWindow = nil
        effectPickerPresenter.stop()
    }

    /// A window closed, whoever closed it. Only the open one ends the settings Presenter: a report from
    /// a window the Router has already let go changes nothing.
    private func settingsWindowDidClose(_ window: any SettingsWindow) {
        guard settingsWindow === window else { return }
        releaseSettings()
    }

    private func releaseSettings() {
        settingsWindow = nil
        settingsPresenter.stop()
    }
}
