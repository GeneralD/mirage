import Combine
import Domain
import TestSupport

/// `OnboardingInteractor` as the Presenter suites see it: `install` is a `CurrentValueSubject` the test drives
/// with `publish(_:)`, so a subscriber gets the current status at once and every later one. A subscription that
/// is cancelled is counted in `cancellations`. Commands are only recorded (`starts`, `stops`, `openedPanes`,
/// `exports`); nothing they would cause happens unless the test publishes it. `openApprovalSettings(_:)` answers
/// `opensSettings` and `exportSupportLog(_:)` answers `exportOutcome`.
public final class FakeOnboardingInteractor: OnboardingInteractor, @unchecked Sendable {
    private let subject: CurrentValueSubject<InstallStatus, Never>
    private let opensSettings: Bool
    private let exportOutcome: SupportLogExportOutcome
    /// One entry per `start()` call.
    public let starts = Collector<Void>()
    /// One entry per `stop()` call.
    public let stops = Collector<Void>()
    /// One entry per subscription to `install` that was cancelled.
    public let cancellations = Collector<Void>()
    /// The System Settings panes `openApprovalSettings(_:)` was asked to open, in order.
    public let openedPanes = Collector<SystemSettingsPane>()
    /// The contexts `exportSupportLog(_:)` was asked to export, in order.
    public let exports = Collector<SupportReportContext>()

    public init(
        install: InstallStatus = .notInstalled,
        opensSettings: Bool = true,
        exportOutcome: SupportLogExportOutcome = .saved(path: "/fake/support-log.txt", lineCount: 0, logError: nil)
    ) {
        subject = CurrentValueSubject(install)
        self.opensSettings = opensSettings
        self.exportOutcome = exportOutcome
    }

    public var install: AnyPublisher<InstallStatus, Never> {
        let cancellations = cancellations
        let observed = subject.handleEvents(receiveCancel: { cancellations.append(()) })
        return observed.eraseToAnyPublisher()
    }

    /// Makes `status` the current one and sends it to every subscriber.
    public func publish(_ status: InstallStatus) {
        subject.send(status)
    }

    public func start() {
        starts.append(())
    }

    public func stop() {
        stops.append(())
    }

    public func openApprovalSettings(_ pane: SystemSettingsPane) async -> Bool {
        openedPanes.append(pane)
        return opensSettings
    }

    public func exportSupportLog(_ context: SupportReportContext) async -> SupportLogExportOutcome {
        exports.append(context)
        return exportOutcome
    }
}
