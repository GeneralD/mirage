import Combine
import Dependencies
import Domain
import TestDoubles
import TestSupport

@testable import Presenters

/// Builds an `OnboardingPresenter` over `interactor` and the macOS major version `systemMajor`, inside
/// `withDependencies`: the Presenter captures the dependencies of the scope it is made in.
@MainActor
func makeOnboardingPresenter(over interactor: any OnboardingInteractor, systemMajor: Int = 15) -> OnboardingPresenter {
    withDependencies {
        $0.onboardingInteractor = interactor
        $0.hostEnvironment = FixedHostEnvironment(systemMajor: systemMajor)
    } operation: {
        OnboardingPresenter()
    }
}

/// An `OnboardingPresenter` over a `FakeOnboardingInteractor` the test publishes into.
@MainActor
struct OnboardingPresenterRig {
    let interactor: FakeOnboardingInteractor
    let presenter: OnboardingPresenter

    init(install: InstallStatus = .notInstalled, systemMajor: Int = 15, opensSettings: Bool = true) {
        let interactor = FakeOnboardingInteractor(install: install, opensSettings: opensSettings)
        self.interactor = interactor
        presenter = makeOnboardingPresenter(over: interactor, systemMajor: systemMajor)
    }

    /// Starts the Presenter and waits for the status it reports first to reach the window.
    func start() async {
        presenter.start()
        await settle(presenter.$status) { $0 != onboardingPendingStatus }
    }
}

/// An `OnboardingInteractor` that answers `openApprovalSettings(_:)` from `answers`, in order, and repeats the
/// last answer after them, so a test can have System Settings fail and then open. Everything else is `inner`'s.
final class AnsweringOnboardingInteractor: OnboardingInteractor, @unchecked Sendable {
    let inner: FakeOnboardingInteractor
    private var answers: [Bool]

    init(_ inner: FakeOnboardingInteractor, answers: [Bool]) {
        self.inner = inner
        self.answers = answers
    }

    var install: AnyPublisher<InstallStatus, Never> { inner.install }

    func start() { inner.start() }

    func stop() { inner.stop() }

    func openApprovalSettings(_ pane: SystemSettingsPane) async -> Bool {
        _ = await inner.openApprovalSettings(pane)
        guard answers.count > 1 else { return answers.first ?? false }
        return answers.removeFirst()
    }

    func exportSupportLog(_ context: SupportReportContext) async -> SupportLogExportOutcome {
        await inner.exportSupportLog(context)
    }
}

/// Lets the main actor run the work already queued on it. Work for a value sent before this call is queued
/// ahead of this task, so it has been applied when the call returns; nothing waits on time.
@MainActor
func drainMainActor() async {
    await Task { @MainActor in }.value
}
