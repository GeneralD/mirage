import Combine
import Domain
import TestSupport

/// `OnboardingInteractor` as the Presenter suites see it: `install` is a `CurrentValueSubject` the test drives
/// with `publish(_:)`, so a subscriber gets the current status at once and every later one. A subscription that
/// is cancelled is counted in `cancellations`. Commands are only recorded (`starts`, `stops`, `openedPanes`,
/// `exports`); nothing they would cause happens unless the test publishes it. `openApprovalSettings(_:)` answers
/// `opensSettings` and `exportSupportLog(_:)` answers `exportOutcome`, unless `holdExports()` has held it: a held
/// export suspends until `completeExport(with:)` answers the oldest one.
public final class FakeOnboardingInteractor: OnboardingInteractor, @unchecked Sendable {
    /// The held exports: whether new ones are held, and the continuations of the ones that are suspended, oldest first.
    private struct ExportHolds {
        var holding = false
        var waiting: [CheckedContinuation<SupportLogExportOutcome, Never>] = []
    }

    private let subject: CurrentValueSubject<InstallStatus, Never>
    private let opensSettings: Bool
    private let exportOutcome: SupportLogExportOutcome
    private let exportHolds = Locked(ExportHolds())
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

    /// Holds every `exportSupportLog(_:)` from now on: each one records its context and suspends until
    /// `completeExport(with:)` answers it.
    public func holdExports() {
        exportHolds.withLock { $0.holding = true }
    }

    /// Answers the oldest held `exportSupportLog(_:)` with `outcome`; `false` when none is held.
    @discardableResult
    public func completeExport(with outcome: SupportLogExportOutcome) -> Bool {
        let oldest: CheckedContinuation<SupportLogExportOutcome, Never>? = exportHolds.withLock { holds in
            holds.waiting.isEmpty ? nil : holds.waiting.removeFirst()
        }
        guard let oldest else { return false }
        oldest.resume(returning: outcome)
        return true
    }

    /// How many `exportSupportLog(_:)` calls are held and not yet answered.
    public var pendingExportCount: Int { exportHolds.current.waiting.count }

    public func exportSupportLog(_ context: SupportReportContext) async -> SupportLogExportOutcome {
        await withCheckedContinuation { (continuation: CheckedContinuation<SupportLogExportOutcome, Never>) in
            // Recorded and registered in one critical section, so a test that sees the context can always answer the export.
            exportHolds.withLock { holds in
                exports.append(context)
                if holds.holding {
                    holds.waiting.append(continuation)
                } else {
                    continuation.resume(returning: exportOutcome)
                }
            }
        }
    }
}
