/// The navigation the settings window asks for. `AppRouter` implements it, and `SettingsPresenter`
/// reports to it, so the View talks to its Presenter only and the Presenter knows no window.
@MainActor
public protocol SettingsRouting: AnyObject {
    /// Called once a reset-all has finished and the new settings are published, so the Router can restart what read the old ones.
    func settingsDidReset()
}
