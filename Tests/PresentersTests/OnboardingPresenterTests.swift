import Combine
import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import Presenters

@MainActor
@Suite("OnboardingPresenter", .timeLimit(.minutes(1)))
struct OnboardingPresenterTests {
    private let loginItems = OnboardingPaneAction(pane: .loginItemsAndExtensions, title: "Open Login Items & Extensions")
    private let privacy = OnboardingPaneAction(pane: .privacyAndSecurity, title: "Open Privacy & Security")

    // MARK: - Status

    @Test("before start the status is the pending one, nothing is offered, and the Interactor is asked nothing")
    func quietBeforeStart() {
        let rig = OnboardingPresenterRig(install: .needsApproval)

        #expect(rig.presenter.status == onboardingPendingStatus)
        #expect(rig.presenter.paneActions.isEmpty)
        #expect(rig.presenter.settingsNotice == nil)
        #expect(rig.interactor.starts.count == 0)
        #expect(rig.interactor.stops.count == 0)
        #expect(rig.interactor.openedPanes.count == 0)
    }

    @Test("start starts the Interactor once and shows the status it reports")
    func startShowsCurrentStatus() async {
        let rig = OnboardingPresenterRig(install: .installed)

        await rig.start()

        #expect(rig.interactor.starts.count == 1)
        #expect(rig.presenter.status == onboardingStatus(of: .installed))
    }

    @Test("start called twice in a row starts the Interactor once")
    func startIsIdempotent() async {
        let rig = OnboardingPresenterRig(install: .installed)

        rig.presenter.start()
        rig.presenter.start()
        await settle(rig.presenter.$status) { $0 == onboardingStatus(of: .installed) }

        #expect(rig.interactor.starts.count == 1)
    }

    @Test("the status and the buttons follow each transition in turn, and installed offers no buttons")
    func followsTransitions() async {
        let rig = OnboardingPresenterRig(install: .notInstalled)
        await rig.start()

        rig.interactor.publish(.installing)
        await settle(rig.presenter.$status) { $0 == onboardingStatus(of: .installing) }
        #expect(rig.presenter.paneActions.isEmpty)

        rig.interactor.publish(.needsApproval)
        await settle(rig.presenter.$status) { $0 == onboardingStatus(of: .needsApproval) }
        #expect(rig.presenter.paneActions == [loginItems, privacy])

        rig.interactor.publish(.installed)
        await settle(rig.presenter.$status) { $0 == onboardingStatus(of: .installed) }
        #expect(rig.presenter.paneActions.isEmpty)
    }

    @Test(
        "needsApproval offers the Login Items pane first on macOS 15 and the Privacy pane first on macOS 14",
        arguments: [
            (
                15,
                [
                    OnboardingPaneAction(pane: .loginItemsAndExtensions, title: "Open Login Items & Extensions"),
                    OnboardingPaneAction(pane: .privacyAndSecurity, title: "Open Privacy & Security"),
                ]
            ),
            (
                14,
                [
                    OnboardingPaneAction(pane: .privacyAndSecurity, title: "Open Privacy & Security"),
                    OnboardingPaneAction(pane: .loginItemsAndExtensions, title: "Open Login Items & Extensions"),
                ]
            ),
        ])
    func approvalPanesFollowTheMacOSVersion(systemMajor: Int, expected: [OnboardingPaneAction]) async {
        let rig = OnboardingPresenterRig(install: .needsApproval, systemMajor: systemMajor)

        await rig.start()

        #expect(rig.presenter.paneActions == expected)
    }

    @Test("a denied approval shows a failure and offers both panes")
    func deniedOffersBothPanes() async {
        let rig = OnboardingPresenterRig(install: .failed(.denied))

        await rig.start()

        #expect(rig.presenter.status.tone == .failure)
        #expect(rig.presenter.paneActions == [loginItems, privacy])
    }

    @Test("a canceled installation shows a failure and offers no pane")
    func canceledOffersNoPane() async {
        let rig = OnboardingPresenterRig(install: .failed(.canceled))

        await rig.start()

        #expect(rig.presenter.status.tone == .failure)
        #expect(rig.presenter.paneActions.isEmpty)
    }

    @Test("a status that changes nothing is not published again")
    func unchangedValuesAreNotPublished() async {
        let rig = OnboardingPresenterRig(install: .needsApproval)
        await rig.start()
        let statuses = Collector<OnboardingStatusDisplay>()
        let actions = Collector<[OnboardingPaneAction]>()
        let subscriptions = [
            rig.presenter.$status.dropFirst().sink { statuses.append($0) },
            rig.presenter.$paneActions.dropFirst().sink { actions.append($0) },
        ]

        rig.interactor.publish(.needsApproval)
        await drainMainActor()
        rig.interactor.publish(.installed)
        await settle(rig.presenter.$status) { $0 == onboardingStatus(of: .installed) }

        #expect(statuses.values == [onboardingStatus(of: .installed)], "the repeated status published nothing of its own")
        #expect(actions.values == [[]])
        withExtendedLifetime(subscriptions) {}
    }

    // MARK: - Lifecycle

    @Test("stop ends the observation, cancels the subscription, stops the Interactor, and shows nothing that comes later")
    func stopEndsObservation() async {
        let rig = OnboardingPresenterRig(install: .notInstalled)
        await rig.start()

        rig.presenter.stop()
        rig.interactor.publish(.installed)
        await drainMainActor()

        #expect(rig.interactor.cancellations.count == 1, "the subscription was cancelled")
        #expect(rig.interactor.stops.count == 1)
        #expect(rig.presenter.status == onboardingStatus(of: .notInstalled), "the status stays as it was when stop was called")
    }

    @Test("a status that was on its way when stop was called is never applied")
    func stopDropsTheStatusOnItsWay() async {
        let rig = OnboardingPresenterRig(install: .notInstalled)
        await rig.start()
        let shown = Collector<OnboardingStatusDisplay>()
        let subscription = rig.presenter.$status.dropFirst().sink { shown.append($0) }

        // The test holds the main actor from the first publish to the wait below, so the task that applies
        // statuses has not run: the status is on its way when stop() lands.
        rig.interactor.publish(.installing)
        rig.presenter.stop()
        // The restart must begin from a status other than the one on its way, or it would hide an application of it.
        rig.interactor.publish(.installed)
        rig.presenter.start()
        await settle(rig.presenter.$status) { $0 == onboardingStatus(of: .installed) }

        #expect(shown.values == [onboardingStatus(of: .installed)], "the status went from the one before stop straight to the restart's")
        withExtendedLifetime(subscription) {}
    }

    @Test("a Presenter started again after stop shows the status the Interactor has then")
    func restartAfterStopShowsCurrentStatus() async {
        let rig = OnboardingPresenterRig(install: .notInstalled)
        await rig.start()
        rig.presenter.stop()
        rig.interactor.publish(.installed)

        rig.presenter.start()
        await settle(rig.presenter.$status) { $0 == onboardingStatus(of: .installed) }

        #expect(rig.interactor.starts.count == 2)
    }

    @Test("stop stops the Interactor even when the Presenter was never started, and cancels no subscription")
    func stopWithoutStartStopsTheInteractor() {
        let rig = OnboardingPresenterRig()

        rig.presenter.stop()

        #expect(rig.interactor.stops.count == 1)
        #expect(rig.interactor.cancellations.count == 0)
    }

    // Releasing a Presenter releases the run it holds on the thread the test is running on, so like `stop()`
    // it has happened by the time the assignment returns.

    @Test("a started Presenter that is let go stops the Interactor")
    func letGoWhileStartedStops() {
        let interactor = FakeOnboardingInteractor()
        var presenter: OnboardingPresenter? = makeOnboardingPresenter(over: interactor)
        presenter?.start()
        weak let letGo = presenter
        #expect(interactor.stops.count == 0)

        presenter = nil

        #expect(letGo == nil, "nothing else holds the Presenter, so the stop below is its release's")
        #expect(interactor.stops.count == 1)
    }

    @Test("a Presenter that was never started asks nothing of the Interactor when it is let go")
    func letGoBeforeStartIsQuiet() {
        let interactor = FakeOnboardingInteractor()
        var idle: OnboardingPresenter? = makeOnboardingPresenter(over: interactor)
        weak let letGoIdle = idle

        idle = nil

        #expect(letGoIdle == nil)
        #expect(interactor.stops.count == 0)

        // A started Presenter let go afterwards shows that a release does reach the Interactor, so the single stop
        // below is the started one's, and the idle one's silence is not a release that never ran.
        var started: OnboardingPresenter? = makeOnboardingPresenter(over: interactor)
        started?.start()
        started = nil

        #expect(interactor.stops.count == 1)
    }

    @Test("a Presenter that was stopped does not stop the Interactor a second time when it is let go")
    func letGoAfterStopIsQuiet() {
        let interactor = FakeOnboardingInteractor()
        var presenter: OnboardingPresenter? = makeOnboardingPresenter(over: interactor)
        presenter?.start()
        presenter?.stop()
        #expect(interactor.stops.count == 1)

        presenter = nil

        #expect(interactor.stops.count == 1)
    }

    // MARK: - Opening System Settings

    @Test("openSettings hands the pane to the Interactor, and a pane that opens leaves no notice")
    func openSettingsOpensThePane() async {
        let rig = OnboardingPresenterRig(install: .needsApproval, opensSettings: true)
        await rig.start()

        await rig.presenter.openSettings(.privacyAndSecurity)

        #expect(rig.interactor.openedPanes.values == [.privacyAndSecurity])
        #expect(rig.presenter.settingsNotice == nil)
    }

    @Test("a pane that did not open shows the failure notice, and the next one that opens clears it")
    func failedOpenShowsNoticeUntilTheNextOpen() async {
        let interactor = AnsweringOnboardingInteractor(FakeOnboardingInteractor(install: .needsApproval), answers: [false, true])
        let presenter = makeOnboardingPresenter(over: interactor)

        await presenter.openSettings(.privacyAndSecurity)
        #expect(presenter.settingsNotice == onboardingSettingsFailure)

        await presenter.openSettings(.privacyAndSecurity)
        #expect(presenter.settingsNotice == nil)
    }

    @Test("a notice stays through a repeated status, and a different status clears it")
    func noticeClearsOnlyOnADifferentStatus() async {
        let interactor = AnsweringOnboardingInteractor(FakeOnboardingInteractor(install: .needsApproval), answers: [false])
        let presenter = makeOnboardingPresenter(over: interactor)
        presenter.start()
        await settle(presenter.$status) { $0 == onboardingStatus(of: .needsApproval) }
        await presenter.openSettings(.privacyAndSecurity)
        #expect(presenter.settingsNotice == onboardingSettingsFailure)

        interactor.inner.publish(.needsApproval)
        await drainMainActor()
        #expect(presenter.settingsNotice == onboardingSettingsFailure, "a repeated status keeps the notice")

        interactor.inner.publish(.installed)
        await settle(presenter.$status) { $0 == onboardingStatus(of: .installed) }
        #expect(presenter.settingsNotice == nil)
    }
}
