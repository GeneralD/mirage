import Domain

// The words of the onboarding window (#221): the virtual camera's status, the buttons that open
// System Settings and the support-log controls, as pure values, so that the View only draws them.
// Where the approval sits depends on the macOS version, so no single pane is named as the one.

/// The window's title.
public let onboardingWindowTitle = "Set Up the Virtual Camera"
/// The menu item that opens the window.
public let onboardingMenuTitle = "Set Up Virtual Camera…"
/// The heading of the support-log section.
public let onboardingSupportLogTitle = "Support Log"
/// The button that saves the support log.
public let onboardingSupportLogButton = "Save Support Log"
/// What the button shows while the log is being saved.
public let onboardingSupportLogSaving = "Saving…"
/// What the support-log section says under its button.
public let onboardingSupportLogHint =
    "Saves the recent app log and your macOS version to a file and shows it in Finder. Attach it when you report a problem."
/// The heading over the compiler message of an effect that failed.
public let onboardingCompilerMessageTitle = "Why the effect failed"

/// The status shown while the install status is not known yet.
let onboardingPendingStatus = OnboardingStatusDisplay(tone: .progress, headline: "Checking the virtual camera…", detail: "")

/// The notice shown when System Settings could not be opened.
let onboardingSettingsFailure = OnboardingNotice(tone: .warning, text: "System Settings did not open. Open it from the Apple menu.")

/// What the window says about the virtual camera in `status`.
func onboardingStatus(of status: InstallStatus) -> OnboardingStatusDisplay {
    switch status {
    case .notInstalled:
        OnboardingStatusDisplay(
            tone: .neutral, headline: "Virtual camera not installed", detail: "The app installs it when it starts. Nothing to do yet.")
    case .installing:
        OnboardingStatusDisplay(tone: .progress, headline: "Installing the virtual camera…", detail: "This takes a few seconds.")
    case .needsApproval:
        OnboardingStatusDisplay(
            tone: .warning, headline: "Approval needed",
            detail:
                "Allow the extension in System Settings. Depending on your macOS version it is under Privacy & Security or General > Login Items & Extensions."
        )
    case .installed:
        OnboardingStatusDisplay(tone: .success, headline: "Virtual camera ready", detail: "Pick it as the camera in Zoom, Meet or OBS.")
    case .rebootRequired:
        OnboardingStatusDisplay(
            tone: .warning, headline: "Restart your Mac", detail: "The virtual camera turns on after the next restart.")
    case .failed(.denied):
        OnboardingStatusDisplay(
            tone: .failure, headline: "Approval was denied",
            detail: "Allow the extension in System Settings, then quit and reopen the app.")
    case .failed(.canceled):
        OnboardingStatusDisplay(tone: .failure, headline: "Installation was canceled", detail: "Quit and reopen the app to try again.")
    case .failed(.invalidBuild(let code)):
        OnboardingStatusDisplay(
            tone: .failure, headline: "This build cannot install the extension",
            detail: "Run the signed app from /Applications. (error \(code))")
    case .failed(.other(let code, let description)):
        OnboardingStatusDisplay(tone: .failure, headline: "Installation failed", detail: "\(description) (error \(code))")
    }
}

/// The panes the approval can be sent to on macOS `major`. From macOS 15 on it is under Login Items &
/// Extensions, before that under Privacy & Security, but both are returned, as the place is not
/// pinned to one of them.
func approvalPanes(forSystemMajor major: Int) -> [SystemSettingsPane] {
    major >= 15 ? [.loginItemsAndExtensions, .privacyAndSecurity] : [.privacyAndSecurity, .loginItemsAndExtensions]
}

/// The buttons that open System Settings for `status`: one per approval pane, in the order of
/// `approvalPanes`, while the extension waits for approval or was denied; none for any other status.
func paneActions(for status: InstallStatus, systemMajor: Int) -> [OnboardingPaneAction] {
    switch status {
    case .needsApproval, .failed(.denied):
        approvalPanes(forSystemMajor: systemMajor).map { pane in OnboardingPaneAction(pane: pane, title: paneTitle(of: pane)) }
    case .notInstalled, .installing, .installed, .rebootRequired, .failed(.canceled), .failed(.invalidBuild), .failed(.other):
        []
    }
}

/// The title of the button that opens `pane`.
private func paneTitle(of pane: SystemSettingsPane) -> String {
    switch pane {
    case .loginItemsAndExtensions: "Open Login Items & Extensions"
    case .privacyAndSecurity: "Open Privacy & Security"
    }
}
