import AppRouter
import Dependencies
import Domain

extension GalleryScreen {
    /// The settings window with launch at login on and the global hotkeys registered.
    static var settings: GalleryScreen {
        GalleryScreen(name: "settings", summary: "Settings: launch at login on, global hotkeys registered") {
            openSettings(showing: settingsState)
        }
    }

    /// The settings window with the login item awaiting approval and a hotkey the system refused.
    static var settingsAttention: GalleryScreen {
        GalleryScreen(name: "settings-attention", summary: "Settings: login item awaiting approval, a hotkey in conflict") {
            openSettings(showing: settingsAttentionState)
        }
    }
}

/// Builds an `AppRouter` whose settings Presenter reads `settings`, opens its settings window and answers the Router, which keeps
/// the window alive. The Router is made inside `withDependencies` because its Presenters capture the dependencies of the scope they
/// are built in. `makeSettingsWindow` is the seam a test uses to open no real window.
@MainActor
func openSettings(
    showing settings: SettingsState,
    makeSettingsWindow: @escaping AppRouter.SettingsWindowFactory = AppRouter.settingsWindow(over:onClose:)
) -> AppRouter {
    let router = withDependencies {
        $0.settingsInteractor = GallerySettingsInteractor(settings: settings)
    } operation: {
        AppRouter(makeSettingsWindow: makeSettingsWindow)
    }
    router.openSettings()
    return router
}

/// Launch at login on, the global hotkeys on and all three registered.
var settingsState: SettingsState {
    SettingsState(launchAtLogin: .on, hotkeysEnabled: true, hotkeys: .active)
}

/// The login item waits for approval in System Settings, and Toggle Bypass could not be registered.
var settingsAttentionState: SettingsState {
    SettingsState(launchAtLogin: .needsApproval, hotkeysEnabled: true, hotkeys: .conflicted([.toggleBypass]))
}
