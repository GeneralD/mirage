import AppRouter
import Presenters
import TestSupport
import Testing

@testable import ViewGallery

/// An onboarding window that is never on screen: it only counts what the Router asks of it.
@MainActor
private final class FakeOnboardingWindow {
    private(set) var shows = 0
    private(set) var closes = 0
}

extension FakeOnboardingWindow: OnboardingWindow {
    func show() {
        shows += 1
    }

    func close() {
        closes += 1
    }
}

/// Lets the main actor run the work already queued on it, so that the values applied before this call are applied when it returns.
@MainActor
private func drainMainActor() async {
    await Task { @MainActor in }.value
}

@MainActor
@Suite("Onboarding screens", .timeLimit(.minutes(1)))
struct OnboardingScreenTests {
    @Test("the two onboarding screens are registered under their names, in this order")
    func registered() {
        #expect(galleryScreens.map(\.name).filter { $0.hasPrefix("onboarding") } == ["onboarding-approval", "onboarding-compile-failed"])
    }

    @Test("onboarding-approval shows that approval is needed, offers the Login Items pane and then the Privacy pane, and has no effect message")
    func approvalScreen() async {
        let router = openOnboarding(install: .needsApproval, catalog: onboardingApprovalCatalog, systemMajor: 15) { _, _ in
            FakeOnboardingWindow()
        }
        let presenter = router.onboardingPresenter
        await settle(presenter.$status) { $0.headline == "Approval needed" }
        await drainMainActor()

        #expect(presenter.status.headline == "Approval needed")
        #expect(presenter.paneActions.map(\.pane) == [.loginItemsAndExtensions, .privacyAndSecurity])
        #expect(presenter.effectStatus == nil)
        #expect(presenter.compilerMessage == nil)
    }

    @Test("onboarding-compile-failed shows the extension as ready with no pane action, the effect's status line and a four-line message")
    func compileFailedScreen() async throws {
        let router = openOnboarding(install: .installed, catalog: onboardingCompileFailedCatalog, systemMajor: 15) { _, _ in
            FakeOnboardingWindow()
        }
        let presenter = router.onboardingPresenter
        await settle(presenter.$effectStatus) { $0 != nil }
        await settle(presenter.$status) { $0.headline == "Virtual camera ready" }

        #expect(presenter.status.headline == "Virtual camera ready")
        #expect(presenter.paneActions.isEmpty)
        #expect(presenter.effectStatus == "Ripple: compile failed")
        let message = try #require(presenter.compilerMessage)
        #expect(message.split(separator: "\n").count == 4)
        #expect(message.hasPrefix("effect.metal:12:15: error"))
        #expect(presenter.geometry.messageHeight == 76)
    }

    @Test("opening an onboarding screen makes one window over the Router's Presenter, shows it once and never closes it")
    func opensOneWindow() throws {
        let windows = Collector<FakeOnboardingWindow>()

        _ = openOnboarding(install: .needsApproval, catalog: onboardingApprovalCatalog, systemMajor: 15) { _, _ in
            let window = FakeOnboardingWindow()
            windows.append(window)
            return window
        }

        let window = try #require(windows.values.first)
        #expect(windows.count == 1)
        #expect(window.shows == 1)
        #expect(window.closes == 0)
    }
}
