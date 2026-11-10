import Combine
import Dependencies
import Domain

/// The settings window's display state (#197): launch at login, the global hotkeys and the
/// reset-all flow. It turns `SettingsInteractor.state` into `@Published` values a View draws; the
/// notes and the hotkey rows are pure functions (`SettingsText.swift`), and drawing them is not its job.
///
/// It only observes and forwards. The Interactor's state is the truth: a toggle sent from the window
/// shows only once the state comes back with it. `start()` begins observing and asks the Interactor
/// to refresh; `stop()` ends the observation. A started Presenter that is let go ends its observation
/// too, since releasing the `StateObservation` cancels it.
@MainActor
public final class SettingsPresenter: ObservableObject {
    /// Whether launch at login is on, or waiting for approval (the login item then takes effect once approved).
    @Published public private(set) var launchesAtLogin = false
    /// Whether the launch-at-login switch can be flipped; `false` when the app was started in a way that cannot register it.
    @Published public private(set) var canChangeLaunchAtLogin = true
    /// The line under the switch when launch at login needs a word, `nil` otherwise.
    @Published public private(set) var launchAtLoginNote: String?
    /// Whether the button that opens System Settings' Login Items is offered, which is only when an approval is pending.
    @Published public private(set) var canOpenLoginItemsSettings = false
    /// Whether the global hotkeys are turned on.
    @Published public private(set) var hotkeysEnabled = true
    /// The line under the hotkeys when the system refused some of them, `nil` otherwise.
    @Published public private(set) var hotkeyNote: String?
    /// Whether a reset-all is running; the reset controls are disabled meanwhile.
    @Published public private(set) var isResetting = false
    /// Whether the reset confirmation is showing. The View binds its dialog's `isPresented` to it,
    /// so it can also be written from outside.
    @Published public var isConfirmingReset = false
    /// The hotkey list: one row per action, in `HotkeyAction.allCases` order. The bindings are the defaults.
    public let hotkeyRows: [SettingsHotkeyRow] = settingsHotkeyRows(for: defaultHotkeyBindings)
    /// Where a finished reset is reported: the Router that built this Presenter, which restarts what read the old settings.
    /// Weak, because the Router owns the Presenter; until a Router takes it a finished reset reports nothing.
    public weak var router: (any SettingsRouting)?

    @Dependency(\.settingsInteractor) private var interactor
    /// What a started Presenter holds; `nil` when it was never started or has been stopped.
    /// Releasing it ends the observation, so `stop()` and letting the Presenter go are one path.
    private var observation: StateObservation<SettingsState>?

    public init() {}

    /// Observes the Interactor's state and asks it to refresh, so the current settings arrive. Calling
    /// it again while started does nothing.
    public func start() {
        guard observation == nil else { return }
        observation = StateObservation<SettingsState>(of: interactor.state) { [weak self] state in self?.apply(state) }
        interactor.refresh()
    }

    /// Ends the observation and closes the reset confirmation. The values stay as they were.
    public func stop() {
        observation = nil
        isConfirmingReset = false
    }

    /// Turns launch at login on or off. The Interactor carries it out; the switch moves when the state says so.
    public func setLaunchAtLogin(_ on: Bool) {
        interactor.setLaunchAtLogin(on)
    }

    /// Opens System Settings' Login Items, where a pending approval is given.
    public func openLoginItemsSettings() {
        interactor.openLoginItemsSettings()
    }

    /// Turns the global hotkeys on or off. The Interactor carries it out; the switch moves when the state says so.
    public func setHotkeysEnabled(_ on: Bool) {
        interactor.setHotkeysEnabled(on)
    }

    /// Asks for the reset-all to be confirmed. Ignored while a reset is running.
    public func requestReset() {
        guard !isResetting else { return }
        isConfirmingReset = true
    }

    /// Runs the reset-all the confirmation asked for, then tells the router it is done. Ignored while a
    /// reset is running, so a second confirmation cannot start another one.
    public func confirmReset() {
        guard !isResetting else { return }
        isConfirmingReset = false
        isResetting = true
        let interactor = self.interactor
        Task { @MainActor [weak self] in
            await interactor.resetAll()
            self?.isResetting = false
            self?.router?.settingsDidReset()
        }
    }

    private func apply(_ state: SettingsState) {
        let launches = state.launchAtLogin == .on || state.launchAtLogin == .needsApproval
        let canChange = state.launchAtLogin != .unavailable
        let canOpen = state.launchAtLogin == .needsApproval
        // The module qualifier: the properties of the same names shadow the free functions inside the class.
        let launchNote = Presenters.launchAtLoginNote(of: state.launchAtLogin)
        let hotkeysNote = Presenters.hotkeyNote(of: state.hotkeys)
        if launchesAtLogin != launches { launchesAtLogin = launches }
        if canChangeLaunchAtLogin != canChange { canChangeLaunchAtLogin = canChange }
        if launchAtLoginNote != launchNote { launchAtLoginNote = launchNote }
        if canOpenLoginItemsSettings != canOpen { canOpenLoginItemsSettings = canOpen }
        if hotkeysEnabled != state.hotkeysEnabled { hotkeysEnabled = state.hotkeysEnabled }
        if hotkeyNote != hotkeysNote { hotkeyNote = hotkeysNote }
    }
}
