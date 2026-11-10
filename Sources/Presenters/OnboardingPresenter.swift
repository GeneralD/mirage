import Combine
import Dependencies
import Domain

/// The onboarding window's display state (#225): the virtual camera's status line, the buttons that open
/// the System Settings pane for its approval, and a notice when System Settings did not open. It turns
/// `OnboardingInteractor.install` into `@Published` values a View draws; deciding the words and buttons
/// is `OnboardingText`'s job, drawing them is not (it imports neither AppKit nor SwiftUI).
///
/// The Presenter owns the Interactor's observation for the window, as `MenuBarPresenter` does for the menu:
/// `start()` begins observing and starts the Interactor, `stop()` ends both, and a started Presenter that is
/// let go does what `stop()` does. `openSettings(_:)` does not touch the observation.
///
/// The install statuses reach the main actor through a `PublisherObservation`, which keeps the newest status
/// until it is applied and applies nothing after it ends.
@MainActor
public final class OnboardingPresenter: ObservableObject {
    /// The status line; the pending one until the first install status arrives.
    @Published public private(set) var status: OnboardingStatusDisplay = onboardingPendingStatus
    /// The buttons that open System Settings for the current status: one per approval pane while approval is
    /// needed or was denied, none otherwise.
    @Published public private(set) var paneActions: [OnboardingPaneAction] = []
    /// The notice that System Settings did not open; `nil` otherwise. A different install status clears it.
    @Published public private(set) var settingsNotice: OnboardingNotice?

    @Dependency(\.onboardingInteractor) private var interactor
    @Dependency(\.hostEnvironment) private var environment
    /// What a started Presenter holds; `nil` when it was never started or has been stopped.
    private var running: Running?
    /// The install status the last `apply` received. A notice belongs to the status it was raised under: a
    /// different status clears it, a repeated one does not.
    private var lastInstall: InstallStatus?

    public init() {}

    /// Observes the Interactor's install status, then starts the Interactor. Calling it again while started
    /// does nothing.
    public func start() {
        guard running == nil else { return }
        running = Running(over: interactor) { [weak self] install in self?.apply(install) }
        interactor.start()
    }

    /// Ends the observation and stops the Interactor. The status and the buttons stay as they were, even when
    /// a status had already been sent and not yet applied.
    public func stop() {
        guard running != nil else { return interactor.stop() }
        running = nil
    }

    /// Opens the System Settings pane for the approval. A pane that did not open sets `settingsNotice`; one
    /// that did clears it.
    public func openSettings(_ pane: SystemSettingsPane) async {
        let opened = await interactor.openApprovalSettings(pane)
        setSettingsNotice(opened ? nil : onboardingSettingsFailure)
    }

    private func apply(_ install: InstallStatus) {
        let status = onboardingStatus(of: install)
        let paneActions = Presenters.paneActions(for: install, systemMajor: environment.info.systemVersion.major)
        if self.status != status { self.status = status }
        if self.paneActions != paneActions { self.paneActions = paneActions }
        if lastInstall != install {
            lastInstall = install
            setSettingsNotice(nil)
        }
    }

    private func setSettingsNotice(_ notice: OnboardingNotice?) {
        if settingsNotice != notice { settingsNotice = notice }
    }
}

extension OnboardingPresenter {
    /// A started Presenter's observation of the Interactor's install statuses and the Interactor's run, ended
    /// together when this is released. Its own class rather than the Presenter's `deinit`, for the same reason
    /// as `MenuBarPresenter.Running`: a main-actor class's `deinit` is not isolated.
    private final class Running {
        private let observation: PublisherObservation<InstallStatus>
        private let interactor: any OnboardingInteractor

        @MainActor
        init(over interactor: any OnboardingInteractor, apply: @escaping @MainActor (InstallStatus) -> Void) {
            self.interactor = interactor
            observation = PublisherObservation(of: interactor.install, apply: apply)
        }

        deinit {
            observation.end()
            interactor.stop()
        }
    }
}
