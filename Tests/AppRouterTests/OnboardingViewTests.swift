import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import Presenters
@testable import Views

/// The onboarding window's Views (#228). `Views` holds no logic and is not measured for coverage, so these tests build each body
/// over a real Presenter, state by state, and check the one pure mapping the window has: the symbol and the colour of a tone.
@MainActor
@Suite("OnboardingView", .timeLimit(.minutes(1)))
struct OnboardingViewTests {
    @Test("the window builds before any install status arrives, showing the pending status and no approval buttons")
    func buildsBeforeAnyStatus() {
        let presenter = makeWindowPresenter(over: FakeOnboardingInteractor())

        #expect(presenter.status == onboardingPendingStatus)
        #expect(presenter.paneActions.isEmpty)
        _ = OnboardingView(presenter: presenter).body
    }

    @Test(
        "the window builds for every install status the Presenter can show",
        arguments: [
            InstallStatus.notInstalled, .installing, .needsApproval, .installed, .rebootRequired,
            .failed(.denied), .failed(.canceled), .failed(.invalidBuild(code: 1)), .failed(.other(code: 2, description: "boom")),
        ])
    func buildsForEveryInstallStatus(_ install: InstallStatus) async {
        let presenter = await startedWindow(over: FakeOnboardingInteractor(install: install))

        _ = OnboardingView(presenter: presenter).body
    }

    @Test("the status section offers one approval button per pane while approval is needed, and none once the extension is installed")
    func statusSectionOffersThePaneButtonsOnlyWhileApprovalIsNeeded() async {
        let needsApproval = await startedWindow(over: FakeOnboardingInteractor(install: .needsApproval))
        #expect(needsApproval.paneActions.count == 2)
        _ = OnboardingStatusSection(presenter: needsApproval).body

        let installed = await startedWindow(over: FakeOnboardingInteractor(install: .installed))
        #expect(installed.paneActions.isEmpty)
        _ = OnboardingStatusSection(presenter: installed).body
    }

    @Test("the diagnostics section builds the compiler message of a failed effect in the block the Presenter sized for it")
    func diagnosticsSectionBuildsTheCompilerMessage() async {
        let failed = await startedWindow(
            catalog: .fixture([chromatic], outcome: .failed(.compileFailed), compilerMessage: "error: unknown type 'half3x4'"))
        await settle(failed.$compilerMessage) { $0 != nil }

        #expect(failed.effectStatus != nil)
        #expect(failed.geometry.messageHeight > 0)
        _ = OnboardingDiagnosticsSection(presenter: failed).body
    }

    @Test("the diagnostics section builds only the support log while the chosen effect has no status to explain")
    func diagnosticsSectionBuildsWithoutAnEffectStatus() async {
        let clean = await startedWindow()

        #expect(clean.effectStatus == nil)
        _ = OnboardingDiagnosticsSection(presenter: clean).body
    }

    @Test("the diagnostics section builds the save button in its saving state, and the notice once the save ends")
    func diagnosticsSectionBuildsWhileSavingAndAfterTheSave() async {
        let interactor = FakeOnboardingInteractor()
        interactor.holdExports()
        let presenter = await startedWindow(over: interactor)

        let save = Task { await presenter.exportSupportLog() }
        // The Interactor has the export, and the continuation that answers it, once its context is recorded.
        await interactor.exports.waitForCount(1)
        #expect(presenter.isSavingLog)
        #expect(presenter.supportLogButtonTitle == onboardingSupportLogSaving)
        _ = OnboardingDiagnosticsSection(presenter: presenter).body

        interactor.completeExport(with: .saved(path: "/fake/support-log.txt", lineCount: 0, logError: nil))
        await save.value
        #expect(presenter.logNotice != nil)
        _ = OnboardingDiagnosticsSection(presenter: presenter).body
    }

    @Test("each tone draws the symbol the window's words call for")
    func eachToneDrawsItsSymbol() {
        #expect(OnboardingTone.neutral.symbolName == "circle.dashed")
        #expect(OnboardingTone.progress.symbolName == "hourglass")
        #expect(OnboardingTone.success.symbolName == "checkmark.circle.fill")
        #expect(OnboardingTone.warning.symbolName == "exclamationmark.triangle.fill")
        #expect(OnboardingTone.failure.symbolName == "xmark.octagon.fill")
    }

    @Test("the success, warning and failure tones are drawn in green, orange and red")
    func eachToneDrawsInItsColour() {
        #expect(OnboardingTone.success.color == .green)
        #expect(OnboardingTone.warning.color == .orange)
        #expect(OnboardingTone.failure.color == .red)
    }
}

private let chromatic = EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))

/// An `OnboardingPresenter` made inside `withDependencies`, so that it never reaches the live Interactors: `interactor` reports the
/// install status and `catalog` the chosen effect. The Presenter captures the dependencies of the scope it is made in.
@MainActor
private func makeWindowPresenter(
    over interactor: FakeOnboardingInteractor, catalog: EffectCatalogState = .fixture([chromatic])
) -> OnboardingPresenter {
    withDependencies {
        $0.onboardingInteractor = interactor
        $0.effectInteractor = FakeEffectInteractor(state: catalog)
        $0.hostEnvironment = FixedHostEnvironment(systemMajor: 15)
    } operation: {
        OnboardingPresenter()
    }
}

/// A started window Presenter that has received its first install status, so the buttons and the words are the ones of that status.
@MainActor
private func startedWindow(
    over interactor: FakeOnboardingInteractor = FakeOnboardingInteractor(),
    catalog: EffectCatalogState = .fixture([chromatic])
) async -> OnboardingPresenter {
    let presenter = makeWindowPresenter(over: interactor, catalog: catalog)
    presenter.start()
    await settle(presenter.$status) { $0 != onboardingPendingStatus }
    return presenter
}
