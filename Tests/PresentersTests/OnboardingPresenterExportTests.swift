import Domain
import TestDoubles
import TestSupport
import Testing

@testable import Presenters

/// The support log on the onboarding window (#227): the save button's title, a save's progress and its notice, and
/// the context the report is written from. The install status and the catalog are covered by
/// `OnboardingPresenterTests` and `OnboardingPresenterCatalogTests`.
@MainActor
@Suite("OnboardingPresenterExport", .timeLimit(.minutes(1)))
struct OnboardingPresenterExportTests {
    private let ripple = EffectCatalogEntry.fixture(.bundled("Ripple"))
    private let saved = SupportLogExportOutcome.saved(path: "/tmp/report.txt", lineCount: 3, logError: nil)
    private let failed = SupportLogExportOutcome.failed(description: "disk full")

    /// A catalog that has chosen `Ripple`, which failed to compile with `compilerMessage`.
    private func failedCatalog(compilerMessage: String?) -> EffectCatalogState {
        .fixture([ripple], outcome: .failed(.compileFailed), compilerMessage: compilerMessage)
    }

    /// Starts a save on a task of its own and waits until the Interactor has received it, so the test can look at the
    /// save while it runs. The returned task ends when the save does.
    private func beginSave(_ presenter: OnboardingPresenter, _ interactor: FakeOnboardingInteractor) async -> Task<Void, Never> {
        let received = interactor.exports.count + 1
        let save = Task { await presenter.exportSupportLog() }
        await interactor.exports.waitForCount(received)
        return save
    }

    // MARK: - Button and notice

    @Test("before any save the button offers its usual title, nothing is saving, and no notice is shown")
    func quietBeforeSave() {
        let rig = OnboardingPresenterRig()

        #expect(rig.presenter.isSavingLog == false)
        #expect(rig.presenter.logNotice == nil)
        #expect(rig.presenter.supportLogButtonTitle == "Save Support Log")
    }

    @Test("while the report is being saved the button says Saving… and no notice is shown")
    func savingShowsTitleAndNoNotice() async {
        let rig = OnboardingPresenterRig()
        rig.interactor.holdExports()

        let save = await beginSave(rig.presenter, rig.interactor)

        #expect(rig.presenter.isSavingLog)
        #expect(rig.presenter.logNotice == nil)
        #expect(rig.presenter.supportLogButtonTitle == "Saving…")
        rig.interactor.completeExport(with: saved)
        await save.value
    }

    @Test("a saved report shows a success notice and the button gets its usual title back")
    func savedShowsSuccessNotice() async {
        let rig = OnboardingPresenterRig()
        rig.interactor.holdExports()
        let save = await beginSave(rig.presenter, rig.interactor)

        rig.interactor.completeExport(with: saved)
        await save.value

        #expect(rig.presenter.isSavingLog == false)
        #expect(rig.presenter.logNotice == supportLogNotice(of: saved))
        #expect(rig.presenter.logNotice?.tone == .success)
        #expect(rig.presenter.supportLogButtonTitle == "Save Support Log")
    }

    @Test("a failed report shows a failure notice, and the next save is accepted")
    func failedShowsFailureNoticeAndAcceptsNextSave() async {
        let rig = OnboardingPresenterRig()
        rig.interactor.holdExports()
        let first = await beginSave(rig.presenter, rig.interactor)

        rig.interactor.completeExport(with: failed)
        await first.value

        #expect(rig.presenter.isSavingLog == false)
        #expect(rig.presenter.logNotice == supportLogNotice(of: failed))
        #expect(rig.presenter.logNotice?.tone == .failure)

        let second = await beginSave(rig.presenter, rig.interactor)
        #expect(rig.presenter.isSavingLog)
        rig.interactor.completeExport(with: saved)
        await second.value
        #expect(rig.presenter.logNotice == supportLogNotice(of: saved))
    }

    @Test("a save started while one is running does nothing and reaches the Interactor once")
    func saveWhileSavingIsIgnored() async {
        let rig = OnboardingPresenterRig()
        rig.interactor.holdExports()
        let first = await beginSave(rig.presenter, rig.interactor)

        await rig.presenter.exportSupportLog()

        #expect(rig.interactor.exports.count == 1, "the second call never reached the Interactor")
        #expect(rig.interactor.pendingExportCount == 1)
        #expect(rig.presenter.isSavingLog)
        rig.interactor.completeExport(with: saved)
        await first.value
    }

    @Test("the next save clears the notice of the one before as it starts")
    func nextSaveClearsNotice() async {
        let rig = OnboardingPresenterRig()
        rig.interactor.holdExports()
        let first = await beginSave(rig.presenter, rig.interactor)
        rig.interactor.completeExport(with: failed)
        await first.value
        #expect(rig.presenter.logNotice != nil)

        let second = await beginSave(rig.presenter, rig.interactor)

        #expect(rig.presenter.logNotice == nil)
        #expect(rig.presenter.isSavingLog)
        rig.interactor.completeExport(with: saved)
        await second.value
    }

    // MARK: - Stop

    @Test("stop during a save discards its result: nothing is saving and no notice is shown")
    func stopDiscardsRunningSave() async {
        let rig = OnboardingPresenterRig()
        await rig.start()
        rig.interactor.holdExports()
        let save = await beginSave(rig.presenter, rig.interactor)

        rig.presenter.stop()

        #expect(rig.presenter.isSavingLog == false)
        #expect(rig.presenter.logNotice == nil)
        #expect(rig.presenter.supportLogButtonTitle == "Save Support Log")

        rig.interactor.completeExport(with: saved)
        await save.value
        #expect(rig.presenter.isSavingLog == false)
        #expect(rig.presenter.logNotice == nil, "the result that came back after stop was thrown away")
    }

    @Test("a save that stop ended does not touch the save that started after it")
    func endedSaveDoesNotTouchNewerSave() async {
        let rig = OnboardingPresenterRig()
        rig.interactor.holdExports()
        let older = await beginSave(rig.presenter, rig.interactor)
        rig.presenter.stop()
        let newer = await beginSave(rig.presenter, rig.interactor)

        // The Interactor answers the oldest held export first, which is the one stop ended.
        rig.interactor.completeExport(with: saved)
        await older.value

        #expect(rig.presenter.isSavingLog, "the newer save is still running")
        #expect(rig.presenter.logNotice == nil)

        rig.interactor.completeExport(with: failed)
        await newer.value
        #expect(rig.presenter.isSavingLog == false)
        #expect(rig.presenter.logNotice == supportLogNotice(of: failed))
    }

    // MARK: - The report's context

    @Test("the report carries the install status, the chosen effect's status line and the compiler's message as sent")
    func reportCarriesWhatTheWindowShows() async {
        let rig = OnboardingPresenterRig(
            install: .needsApproval, catalog: failedCatalog(compilerMessage: "  error: unknown type 'half3x4'\n"))
        await rig.start()
        await settle(rig.presenter.$effectStatus) { $0 != nil }

        await rig.presenter.exportSupportLog()

        #expect(
            rig.interactor.exports.values == [
                SupportReportContext(
                    install: .needsApproval, effectStatus: "Ripple: compile failed", compilerMessage: "  error: unknown type 'half3x4'\n")
            ])
    }

    @Test("the report carries the compiler's whole message, where the window shows only an excerpt of it")
    func reportCarriesWholeMessage() async {
        let message = String(repeating: "a", count: 2500)
        let rig = OnboardingPresenterRig(catalog: failedCatalog(compilerMessage: message))
        await rig.start()
        await settle(rig.presenter.$compilerMessage) { $0 != nil }

        await rig.presenter.exportSupportLog()

        #expect(rig.presenter.compilerMessage == String(repeating: "a", count: 2000) + "…")
        #expect(rig.interactor.exports.values.map { $0.compilerMessage } == [message])
    }

    @Test("before an install status arrives the report says the extension is not installed")
    func reportSaysNotInstalledBeforeAnyStatus() async {
        let rig = OnboardingPresenterRig(install: .installed)

        await rig.presenter.exportSupportLog()

        #expect(rig.interactor.exports.values == [SupportReportContext(install: .notInstalled)])
    }

    @Test("the report carries the install status that arrived last")
    func reportCarriesLatestInstallStatus() async {
        let rig = OnboardingPresenterRig(install: .needsApproval)
        await rig.start()
        rig.interactor.publish(.installed)
        await settle(rig.presenter.$status) { $0 == onboardingStatus(of: .installed) }

        await rig.presenter.exportSupportLog()

        #expect(rig.interactor.exports.values.map { $0.install } == [.installed])
    }
}
