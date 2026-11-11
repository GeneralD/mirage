/// The navigation the menu asks for (#12, #199). `AppRouter` implements it, and `MenuBarPresenter`
/// forwards *Browse Effects…* and *Settings…* to it, so the View talks to its Presenter only
/// and the Presenter knows no window.
@MainActor
public protocol MenuBarRouting: AnyObject {
    /// Opens the effect picker's window, or brings the open one to the front.
    func openEffectPicker()
    /// Opens the settings window, or brings the open one to the front.
    func openSettings()
}
