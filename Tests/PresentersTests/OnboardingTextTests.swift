import Domain
import Testing

@testable import Presenters

@Suite("OnboardingText")
struct OnboardingTextTests {
    // The expectations are written out as literals, not read from the constants, so that changing a
    // word turns these red.

    @Test(
        "each install status shows its tone, headline and detail",
        arguments: [
            (
                InstallStatus.notInstalled,
                OnboardingStatusDisplay(
                    tone: .neutral, headline: "Virtual camera not installed", detail: "The app installs it when it starts. Nothing to do yet.")
            ),
            (
                InstallStatus.installing,
                OnboardingStatusDisplay(tone: .progress, headline: "Installing the virtual camera…", detail: "This takes a few seconds.")
            ),
            (
                InstallStatus.needsApproval,
                OnboardingStatusDisplay(
                    tone: .warning, headline: "Approval needed",
                    detail:
                        "Allow the extension in System Settings. Depending on your macOS version it is under Privacy & Security or General > Login Items & Extensions."
                )
            ),
            (
                InstallStatus.installed,
                OnboardingStatusDisplay(tone: .success, headline: "Virtual camera ready", detail: "Pick it as the camera in Zoom, Meet or OBS.")
            ),
            (
                InstallStatus.rebootRequired,
                OnboardingStatusDisplay(tone: .warning, headline: "Restart your Mac", detail: "The virtual camera turns on after the next restart.")
            ),
            (
                InstallStatus.failed(.denied),
                OnboardingStatusDisplay(
                    tone: .failure, headline: "Approval was denied", detail: "Allow the extension in System Settings, then quit and reopen the app.")
            ),
            (
                InstallStatus.failed(.canceled),
                OnboardingStatusDisplay(tone: .failure, headline: "Installation was canceled", detail: "Quit and reopen the app to try again.")
            ),
            (
                InstallStatus.failed(.invalidBuild(code: 3)),
                OnboardingStatusDisplay(
                    tone: .failure, headline: "This build cannot install the extension",
                    detail: "Run the signed app from /Applications. (error 3)")
            ),
            (
                InstallStatus.failed(.other(code: 7, description: "boom")),
                OnboardingStatusDisplay(tone: .failure, headline: "Installation failed", detail: "boom (error 7)")
            ),
        ])
    func statusWording(status: InstallStatus, expected: OnboardingStatusDisplay) {
        #expect(onboardingStatus(of: status) == expected)
    }

    @Test("a failure with a code ends its detail with that code, after the system's own description")
    func failureDetailEndsWithCode() {
        #expect(onboardingStatus(of: .failed(.invalidBuild(code: 3))).detail.hasSuffix("(error 3)"))
        #expect(onboardingStatus(of: .failed(.other(code: 7, description: "boom"))).detail == "boom (error 7)")
    }

    @Test(
        "from macOS 15 on, Login Items & Extensions is offered first, and both panes are offered",
        arguments: [15, 16, 26])
    func loginItemsFirstFromMacOS15(major: Int) {
        #expect(approvalPanes(forSystemMajor: major) == [.loginItemsAndExtensions, .privacyAndSecurity])
    }

    @Test(
        "before macOS 15, Privacy & Security is offered first, and both panes are offered",
        arguments: [14, 13, 0, -1])
    func privacyFirstBeforeMacOS15(major: Int) {
        #expect(approvalPanes(forSystemMajor: major) == [.privacyAndSecurity, .loginItemsAndExtensions])
    }

    @Test(
        "a pending approval or a denied one offers both panes, in the order of the macOS version",
        arguments: [InstallStatus.needsApproval, .failed(.denied)])
    func approvalStatusesOfferBothPanes(status: InstallStatus) {
        #expect(paneActions(for: status, systemMajor: 15).map(\.pane) == [.loginItemsAndExtensions, .privacyAndSecurity])
        #expect(paneActions(for: status, systemMajor: 14).map(\.pane) == [.privacyAndSecurity, .loginItemsAndExtensions])
    }

    @Test("each approval pane's button says where it leads")
    func paneButtonTitles() {
        #expect(
            paneActions(for: .needsApproval, systemMajor: 15) == [
                OnboardingPaneAction(pane: .loginItemsAndExtensions, title: "Open Login Items & Extensions"),
                OnboardingPaneAction(pane: .privacyAndSecurity, title: "Open Privacy & Security"),
            ])
    }

    @Test(
        "no other install status offers a System Settings button",
        arguments: [
            InstallStatus.notInstalled,
            .installing,
            .installed,
            .rebootRequired,
            .failed(.canceled),
            .failed(.invalidBuild(code: 3)),
            .failed(.other(code: 7, description: "boom")),
        ])
    func otherStatusesOfferNoPane(status: InstallStatus) {
        #expect(paneActions(for: status, systemMajor: 15).isEmpty)
    }

    @Test("the pending status says it is checking the virtual camera, with no detail yet")
    func pendingStatusWording() {
        #expect(onboardingPendingStatus == OnboardingStatusDisplay(tone: .progress, headline: "Checking the virtual camera…", detail: ""))
    }

    @Test("a System Settings pane that does not open is a warning that points to the Apple menu")
    func settingsFailureWording() {
        #expect(
            onboardingSettingsFailure
                == OnboardingNotice(tone: .warning, text: "System Settings did not open. Open it from the Apple menu."))
    }

    @Test("the public wording constants hold the words the window, the menu and the support log show")
    func publicWordingConstants() {
        #expect(onboardingWindowTitle == "Set Up the Virtual Camera")
        #expect(onboardingMenuTitle == "Set Up Virtual Camera…")
        #expect(onboardingSupportLogTitle == "Support Log")
        #expect(onboardingSupportLogButton == "Save Support Log")
        #expect(onboardingSupportLogSaving == "Saving…")
        #expect(
            onboardingSupportLogHint
                == "Saves the recent app log and your macOS version to a file and shows it in Finder. Attach it when you report a problem.")
        #expect(onboardingCompilerMessageTitle == "Why the effect failed")
    }
}
