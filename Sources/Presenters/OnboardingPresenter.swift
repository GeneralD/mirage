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
/// The window also says why the chosen effect failed (#226): the catalog's status line and the compiler's
/// message, read from `EffectInteractor.state`. This Presenter only observes that Interactor; `start()` and
/// `stop()` never start or stop it, since the menu's Presenter owns its lifecycle.
///
/// The install statuses reach the main actor through a `PublisherObservation`, which keeps the newest status
/// until it is applied and applies nothing after it ends. The catalog's states reach it through a
/// `CatalogStateObservation`, which does the same for states.
///
/// The support log (#227) is saved one at a time through `exportSupportLog()`, which hands the Interactor the
/// install status, the chosen effect's status line and the compiler's whole message, and shows the outcome as
/// `logNotice`. `stop()` abandons a save that is still running, so its result is never shown.
@MainActor
public final class OnboardingPresenter: ObservableObject {
    /// The status line; the pending one until the first install status arrives.
    @Published public private(set) var status: OnboardingStatusDisplay = onboardingPendingStatus
    /// The buttons that open System Settings for the current status: one per approval pane while approval is
    /// needed or was denied, none otherwise.
    @Published public private(set) var paneActions: [OnboardingPaneAction] = []
    /// The notice that System Settings did not open; `nil` otherwise. A different install status clears it.
    @Published public private(set) var settingsNotice: OnboardingNotice?
    /// The chosen effect's status line, as the menu says it (`"Ripple: compile failed"`); `nil` when the last
    /// attempt succeeded or nothing was attempted.
    @Published public private(set) var effectStatus: String?
    /// The compiler's message for the chosen effect, cut for the window (`compilerMessageExcerpt`); `nil` when
    /// there is none.
    @Published public private(set) var compilerMessage: String?
    /// The layout of the block that shows `compilerMessage`; 0 high when there is no block.
    public var geometry: OnboardingGeometry { OnboardingGeometry(message: compilerMessage) }
    /// Whether a support log is being saved; the button shows `supportLogButtonTitle` while it is.
    @Published public private(set) var isSavingLog = false
    /// The notice about the last save: the file it wrote, or why it could not write one; `nil` while a save runs,
    /// once a new save starts, and after `stop()`.
    @Published public private(set) var logNotice: OnboardingNotice?
    /// The save button's title: "Saving…" while a save runs, the usual title otherwise.
    public var supportLogButtonTitle: String { isSavingLog ? onboardingSupportLogSaving : onboardingSupportLogButton }

    @Dependency(\.onboardingInteractor) private var interactor
    @Dependency(\.hostEnvironment) private var environment
    /// The catalog this window reports on. Only observed, never started or stopped.
    @Dependency(\.effectInteractor) private var effects
    /// What a started Presenter holds; `nil` when it was never started or has been stopped.
    private var running: Running?
    /// The install status the last `apply` received. A notice belongs to the status it was raised under: a
    /// different status clears it, a repeated one does not.
    private var lastInstall: InstallStatus?
    /// The compiler's message as the catalog sent it. `compilerMessage` shows only an excerpt of it; the report keeps all of it.
    private var rawCompilerMessage: String?
    /// The number of the newest save started or ended. A save whose number is no longer this one was ended by `stop()`
    /// or replaced by a newer save, so its result is dropped.
    private var saveNumber = 0

    public init() {}

    /// Observes the Interactor's install status and the catalog's state, then starts the install Interactor.
    /// Calling it again while started does nothing.
    public func start() {
        guard running == nil else { return }
        running = Running(
            over: interactor,
            effects: effects,
            applyInstall: { [weak self] install in self?.apply(install) },
            applyEffect: { [weak self] state in self?.apply(effect: state) })
        interactor.start()
    }

    /// Ends the observation and stops the Interactor. The status and the buttons stay as they were, even when
    /// a status had already been sent and not yet applied. A save that is running is abandoned: its result is
    /// dropped, and the button and the notice go back to their resting state.
    public func stop() {
        endSave()
        guard running != nil else { return interactor.stop() }
        running = nil
    }

    /// Opens the System Settings pane for the approval. A pane that did not open sets `settingsNotice`; one
    /// that did clears it.
    public func openSettings(_ pane: SystemSettingsPane) async {
        let opened = await interactor.openApprovalSettings(pane)
        setSettingsNotice(opened ? nil : onboardingSettingsFailure)
    }

    /// Saves the support log through the Interactor, from the install status, the chosen effect's status line and
    /// the compiler's whole message. The outcome becomes `logNotice`. Calling it while a save runs does nothing.
    public func exportSupportLog() async {
        guard !isSavingLog else { return }
        isSavingLog = true
        if logNotice != nil { logNotice = nil }
        saveNumber += 1
        let number = saveNumber
        let context = SupportReportContext(
            install: lastInstall ?? .notInstalled, effectStatus: effectStatus, compilerMessage: rawCompilerMessage)
        let outcome = await interactor.exportSupportLog(context)
        // Ended by stop(), or replaced by a newer save: nothing of it is shown any more.
        guard number == saveNumber else { return }
        isSavingLog = false
        logNotice = supportLogNotice(of: outcome)
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

    private func apply(effect state: EffectCatalogState) {
        let effectStatus = MenuBarText.status(of: state)
        let compilerMessage = compilerMessageExcerpt(of: state.compilerMessage)
        rawCompilerMessage = state.compilerMessage
        if self.effectStatus != effectStatus { self.effectStatus = effectStatus }
        if self.compilerMessage != compilerMessage { self.compilerMessage = compilerMessage }
    }

    private func setSettingsNotice(_ notice: OnboardingNotice?) {
        if settingsNotice != notice { settingsNotice = notice }
    }

    /// Retires the save that is running, if any, so its result is dropped, and puts the button and the notice back
    /// to their resting state.
    private func endSave() {
        saveNumber += 1
        if isSavingLog { isSavingLog = false }
        if logNotice != nil { logNotice = nil }
    }
}

extension OnboardingPresenter {
    /// A started Presenter's observations of the Interactor's install statuses and of the catalog's states, and
    /// the Interactor's run, ended together when this is released. Its own class rather than the Presenter's
    /// `deinit`, for the same reason as `MenuBarPresenter.Running`: a main-actor class's `deinit` is not isolated.
    /// Only the install Interactor is stopped here: the catalog's Interactor belongs to the menu's Presenter.
    private final class Running {
        private let observation: PublisherObservation<InstallStatus>
        private let effectObservation: CatalogStateObservation
        private let interactor: any OnboardingInteractor

        @MainActor
        init(
            over interactor: any OnboardingInteractor,
            effects: any EffectInteractor,
            applyInstall: @escaping @MainActor (InstallStatus) -> Void,
            applyEffect: @escaping @MainActor (EffectCatalogState) -> Void
        ) {
            self.interactor = interactor
            observation = PublisherObservation(of: interactor.install, apply: applyInstall)
            effectObservation = CatalogStateObservation(of: effects.state, apply: applyEffect)
        }

        deinit {
            observation.end()
            effectObservation.end()
            interactor.stop()
        }
    }
}
